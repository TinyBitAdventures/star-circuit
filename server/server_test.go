package main

import (
	"context"
	"encoding/json"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"
)

type tclient struct {
	t    *testing.T
	conn *websocket.Conn
	in   chan Msg
}

func dial(t *testing.T, srv *httptest.Server) *tclient {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	url := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"
	conn, _, err := websocket.Dial(ctx, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	c := &tclient{t: t, conn: conn, in: make(chan Msg, 256)}
	go func() {
		for {
			_, b, err := conn.Read(context.Background())
			if err != nil {
				close(c.in)
				return
			}
			var m Msg
			json.Unmarshal(b, &m)
			c.in <- m
		}
	}()
	return c
}

func (c *tclient) send(m Msg) {
	b, _ := json.Marshal(m)
	if err := c.conn.Write(context.Background(), websocket.MessageText, b); err != nil {
		c.t.Fatal(err)
	}
}

// expect waits for the next message of type typ, skipping others.
func (c *tclient) expect(typ string) Msg {
	c.t.Helper()
	deadline := time.After(3 * time.Second)
	for {
		select {
		case m, ok := <-c.in:
			if !ok {
				c.t.Fatalf("connection closed waiting for %q", typ)
			}
			if m.T == typ {
				return m
			}
		case <-deadline:
			c.t.Fatalf("timed out waiting for %q", typ)
		}
	}
}

func join(t *testing.T, srv *httptest.Server, name string) (*tclient, Msg) {
	c := dial(t, srv)
	c.send(Msg{T: "hello", Name: name, Robot: "scout", Version: ProtocolVersion})
	return c, c.expect("welcome")
}

func ip(v int) *int { return &v }

func newServer(t *testing.T, cfg Config) (*Hub, *httptest.Server) {
	hub := NewHub(cfg)
	srv := httptest.NewServer(NewMux(hub))
	t.Cleanup(srv.Close)
	return hub, srv
}

func TestJoinStateChat(t *testing.T) {
	_, srv := newServer(t, Config{})
	a, wa := join(t, srv, "Austin")
	b, wb := join(t, srv, "Austin") // same name gets a suffix
	if wb.Name != "Austin (2)" || len(wb.Players) != 1 || wb.Players[0].Name != "Austin" {
		t.Fatalf("welcome for b: %+v", wb)
	}
	j := a.expect("join")
	if j.ID != wb.ID {
		t.Fatalf("join id %d, want %d", j.ID, wb.ID)
	}
	b.send(Msg{T: "state", Scene: "planet", Star: ip(0), Planet: ip(0), Pos: []float64{1, 2, 3}, Fwd: []float64{0, 0, 1}, Anim: "walk"})
	st := a.expect("state")
	if st.ID != wb.ID || st.Pos[2] != 3 || *st.Planet != 0 {
		t.Fatalf("state relay: %+v", st)
	}
	a.send(Msg{T: "chat", Text: "  hello\x07 there  "})
	ch := b.expect("chat")
	if ch.Text != "hello there" || ch.Name != "Austin" || ch.ID != wa.ID {
		t.Fatalf("chat: %+v", ch)
	}
	b.conn.Close(websocket.StatusNormalClosure, "")
	if l := a.expect("leave"); l.ID != wb.ID {
		t.Fatalf("leave: %+v", l)
	}
}

func TestGive(t *testing.T) {
	_, srv := newServer(t, Config{})
	a, _ := join(t, srv, "A")
	b, wb := join(t, srv, "B")
	a.send(Msg{T: "give", To: wb.ID, Item: "ferrite", Qty: 12})
	g := b.expect("gift")
	if g.Item != "ferrite" || g.Qty != 12 || g.Name != "A" {
		t.Fatalf("gift: %+v", g)
	}
	if ok := a.expect("give_ok"); ok.To != wb.ID {
		t.Fatalf("give_ok: %+v", ok)
	}
	a.send(Msg{T: "give", To: 999, Item: "ferrite", Qty: 3})
	if f := a.expect("give_fail"); f.Qty != 3 {
		t.Fatalf("give_fail: %+v", f)
	}
	a.send(Msg{T: "give", To: wb.ID, Item: "Bad Item!", Qty: 3}) // ignored
	a.send(Msg{T: "ping"})
	a.expect("pong")
}

func TestDropPickupRace(t *testing.T) {
	_, srv := newServer(t, Config{})
	a, _ := join(t, srv, "A")
	b, _ := join(t, srv, "B")
	c, _ := join(t, srv, "C")
	a.send(Msg{T: "drop", Star: ip(0), Planet: ip(2), Pos: []float64{5, 170, 0}, Items: map[string]int{"lumen": 4, "biofiber": 10}})
	d := b.expect("drop_add").Drop
	c.expect("drop_add")
	if d == nil || d.Items["lumen"] != 4 || d.By != "A" || d.Planet != 2 {
		t.Fatalf("drop_add: %+v", d)
	}
	// B and C grab it at the same moment: exactly one wins
	var wg sync.WaitGroup
	for _, cl := range []*tclient{b, c} {
		wg.Add(1)
		go func(cl *tclient) { defer wg.Done(); cl.send(Msg{T: "pickup", ID: d.ID}) }(cl)
	}
	wg.Wait()
	wins := 0
	for _, cl := range []*tclient{b, c} {
		deadline := time.After(3 * time.Second)
	loop:
		for {
			select {
			case m := <-cl.in:
				if m.T == "pickup_ok" {
					wins++
					if m.Items["biofiber"] != 10 {
						t.Fatalf("pickup_ok items: %+v", m.Items)
					}
					break loop
				}
				if m.T == "pickup_fail" {
					break loop
				}
			case <-deadline:
				t.Fatal("no pickup reply")
			}
		}
	}
	if wins != 1 {
		t.Fatalf("%d players got the crate, want exactly 1", wins)
	}
	if r := a.expect("drop_remove"); r.ID != d.ID {
		t.Fatalf("drop_remove: %+v", r)
	}
	// invalid drops are ignored
	a.send(Msg{T: "drop", Star: ip(0), Planet: ip(2), Pos: []float64{1, 2}, Items: map[string]int{"lumen": 1}})
	a.send(Msg{T: "drop", Star: ip(0), Planet: ip(2), Pos: []float64{1, 2, 3}, Items: map[string]int{"lumen": 0}})
	a.send(Msg{T: "ping"})
	for m := range a.in {
		if m.T == "drop_add" {
			t.Fatal("invalid drop was accepted")
		}
		if m.T == "pong" {
			break
		}
	}
}

func TestPasswordAndVersion(t *testing.T) {
	_, srv := newServer(t, Config{Password: "hunter2"})
	c := dial(t, srv)
	c.send(Msg{T: "hello", Name: "X", Version: ProtocolVersion, Password: "nope"})
	if e := c.expect("error"); !strings.Contains(e.Text, "password") {
		t.Fatalf("error: %+v", e)
	}
	c2 := dial(t, srv)
	c2.send(Msg{T: "hello", Name: "X", Version: "0", Password: "hunter2"})
	if e := c2.expect("error"); !strings.Contains(e.Text, "protocol") {
		t.Fatalf("error: %+v", e)
	}
	c3 := dial(t, srv)
	c3.send(Msg{T: "hello", Name: "X", Version: ProtocolVersion, Password: "hunter2"})
	c3.expect("welcome")
}

func TestDropsPersist(t *testing.T) {
	file := filepath.Join(t.TempDir(), "drops.json")
	hub, srv := newServer(t, Config{DataFile: file})
	a, _ := join(t, srv, "A")
	a.send(Msg{T: "drop", Star: ip(3), Planet: ip(1), Pos: []float64{1, 2, 3}, Items: map[string]int{"fire_opal": 1}})
	a.expect("drop_add")
	hub.Sweep()
	// a fresh server on the same file still has the crate
	_, srv2 := newServer(t, Config{DataFile: file})
	_, w := join(t, srv2, "B")
	if len(w.Drops) != 1 || w.Drops[0].Items["fire_opal"] != 1 || w.Drops[0].Star != 3 {
		t.Fatalf("drops after restart: %+v", w.Drops)
	}
}

func TestRoomEvents(t *testing.T) {
	_, srv := newServer(t, Config{})
	a, _ := join(t, srv, "A")
	b, _ := join(t, srv, "B")
	c, _ := join(t, srv, "C")
	a.send(Msg{T: "state", Scene: "dig", Room: "dig:0:0:7", Star: ip(0), Planet: ip(0)})
	b.send(Msg{T: "state", Scene: "dig", Room: "dig:0:0:7", Star: ip(0), Planet: ip(0)})
	c.send(Msg{T: "state", Scene: "planet", Room: "planet:0:0", Star: ip(0), Planet: ip(0)})
	b.expect("state")
	a.send(Msg{T: "ping"})
	a.expect("pong")
	a.send(Msg{T: "ev", Room: "dig:0:0:7", Kind: "dig", Data: json.RawMessage(`{"x":3,"y":40}`)})
	e := b.expect("ev")
	var d map[string]int
	json.Unmarshal(e.Data, &d)
	if e.Kind != "dig" || e.Name != "A" || d["y"] != 40 {
		t.Fatalf("ev: %+v %v", e, d)
	}
	// C is in another room and never hears it; bad payloads are dropped
	a.send(Msg{T: "ev", Room: "dig:0:0:7", Kind: "dig", Data: json.RawMessage(`{bad json`)})
	c.send(Msg{T: "ping"})
	for m := range c.in {
		if m.T == "ev" {
			t.Fatal("event leaked to another room")
		}
		if m.T == "pong" {
			break
		}
	}
}
