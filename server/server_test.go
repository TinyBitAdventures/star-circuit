package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
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

// expectNone checks no message of type typ arrives before a pong.
func (c *tclient) expectNone(typ string) {
	c.t.Helper()
	c.send(Msg{T: "ping"})
	deadline := time.After(3 * time.Second)
	for {
		select {
		case m, ok := <-c.in:
			if !ok {
				c.t.Fatalf("connection closed waiting for pong")
			}
			if m.T == typ {
				c.t.Fatalf("unexpected %q: %+v", typ, m)
			}
			if m.T == "pong" {
				return
			}
		case <-deadline:
			c.t.Fatal("timed out waiting for pong")
		}
	}
}

// closed reports whether the server closed the connection within d.
func (c *tclient) closed(d time.Duration) bool {
	deadline := time.After(d)
	for {
		select {
		case _, ok := <-c.in:
			if !ok {
				return true
			}
		case <-deadline:
			return false
		}
	}
}

func TestLookCleanedAndRateLimited(t *testing.T) {
	_, srv := newServer(t, Config{})
	a, _ := join(t, srv, "A")
	b, _ := join(t, srv, "B")
	huge := strings.Repeat("x", 5000)
	a.send(Msg{T: "look", Look: map[string]any{"shell": "#ff8a5b", "head": "visor", "evil": "x", "top": huge,
		"glow": map[string]any{"nested": 1}, "accent": "<script>"}})
	l := b.expect("look")
	if len(l.Look) != 2 || l.Look["shell"] != "#ff8a5b" || l.Look["head"] != "visor" {
		t.Fatalf("look not cleaned: %+v", l.Look)
	}
	// a burst of looks: only a few get through
	for i := 0; i < 30; i++ {
		a.send(Msg{T: "look", Look: map[string]any{"shell": "#000000"}})
	}
	b.send(Msg{T: "ping"})
	time.Sleep(300 * time.Millisecond)
	n := 0
	for len(b.in) > 0 {
		if m := <-b.in; m.T == "look" {
			n++
		}
	}
	if n == 0 || n > 5 {
		t.Fatalf("%d looks relayed from a burst of 30, want 1..5", n)
	}
	// hello looks are cleaned too
	_, w := join(t, srv, "C")
	for _, p := range w.Players {
		if p.Name == "A" && len(p.Look) > 2 {
			t.Fatalf("stored look: %+v", p.Look)
		}
	}
}

func TestChatRateLimited(t *testing.T) {
	_, srv := newServer(t, Config{})
	a, _ := join(t, srv, "A")
	b, _ := join(t, srv, "B")
	for i := 0; i < 30; i++ {
		a.send(Msg{T: "chat", Text: "spam"})
	}
	time.Sleep(300 * time.Millisecond)
	n := 0
	for len(b.in) > 0 {
		if m := <-b.in; m.T == "chat" {
			n++
		}
	}
	if n == 0 || n > 6 {
		t.Fatalf("%d chats relayed from a burst of 30, want 1..6", n)
	}
}

func TestOversizeMessageDisconnects(t *testing.T) {
	_, srv := newServer(t, Config{})
	a, _ := join(t, srv, "A")
	a.send(Msg{T: "chat", Text: strings.Repeat("y", 20*1024)})
	if !a.closed(3 * time.Second) {
		t.Fatal("a 20 KB message was accepted")
	}
}

func TestConnectionCapAndHelloTimeout(t *testing.T) {
	_, srv := newServer(t, Config{MaxPlayers: 1, MaxConns: 3, HelloTimeout: 300 * time.Millisecond})
	idle := []*tclient{dial(t, srv), dial(t, srv), dial(t, srv)}
	extra := dial(t, srv)
	if !extra.closed(2 * time.Second) {
		t.Fatal("a fourth socket was kept open over the cap of 3")
	}
	for _, c := range idle {
		if !c.closed(2 * time.Second) {
			t.Fatal("a socket that never said hello was kept open")
		}
	}
	// room again once they're gone
	join(t, srv, "A")
}

func TestPasswordBackoff(t *testing.T) {
	_, srv := newServer(t, Config{Password: "hunter2"})
	for i := 0; i < failFree; i++ {
		c := dial(t, srv)
		c.send(Msg{T: "hello", Name: "X", Version: ProtocolVersion, Password: "nope"})
		if e := c.expect("error"); !strings.Contains(e.Text, "Wrong") {
			t.Fatalf("attempt %d: %+v", i, e)
		}
	}
	// now even the right password waits
	c := dial(t, srv)
	c.send(Msg{T: "hello", Name: "X", Version: ProtocolVersion, Password: "hunter2"})
	if e := c.expect("error"); !strings.Contains(e.Text, "Too many") {
		t.Fatalf("backoff: %+v", e)
	}
	time.Sleep(1100 * time.Millisecond)
	c2 := dial(t, srv)
	c2.send(Msg{T: "hello", Name: "X", Version: ProtocolVersion, Password: "hunter2"})
	c2.expect("welcome")
}

func TestItemRefusalsAlwaysAnswer(t *testing.T) {
	_, srv := newServer(t, Config{})
	a, _ := join(t, srv, "A")
	_, wb := join(t, srv, "B")
	for _, m := range []Msg{
		{T: "give", To: wb.ID, Item: "ferrite", Qty: 10000},
		{T: "give", To: wb.ID, Item: "ferrite", Qty: 0},
		{T: "give", To: wb.ID, Item: "Bad Item!", Qty: 3},
		{T: "give", To: 999, Item: "ferrite", Qty: 3},
	} {
		a.send(m)
		f := a.expect("give_fail")
		if f.Text == "" || f.Item != m.Item || f.Qty != m.Qty {
			t.Fatalf("give_fail for %+v: %+v", m, f)
		}
	}
	many := map[string]int{}
	for i := 0; i < 21; i++ {
		many[fmt.Sprintf("item_%d", i)] = 1
	}
	for _, m := range []Msg{
		{T: "drop", Star: ip(0), Planet: ip(0), Pos: []float64{1, 2, 3}, Items: map[string]int{"lumen": 10000}},
		{T: "drop", Star: ip(0), Planet: ip(0), Pos: []float64{1, 2, 3}, Items: many},
		{T: "drop", Star: ip(0), Planet: ip(0), Pos: []float64{1, 2}, Items: map[string]int{"lumen": 1}},
		{T: "drop", Planet: ip(0), Pos: []float64{1, 2, 3}, Items: map[string]int{"lumen": 1}},
	} {
		a.send(m)
		f := a.expect("drop_fail")
		if f.Text == "" || len(f.Items) != len(m.Items) {
			t.Fatalf("drop_fail for %+v: %+v", m, f)
		}
	}
	// giving too fast: every one is answered, some refused
	time.Sleep(2100 * time.Millisecond) // the refusals above used up the burst
	ok, fail := 0, 0
	for i := 0; i < 20; i++ {
		a.send(Msg{T: "give", To: wb.ID, Item: "ferrite", Qty: 1})
	}
	for ok+fail < 20 {
		select {
		case m := <-a.in:
			switch m.T {
			case "give_ok":
				ok++
			case "give_fail":
				fail++
			}
		case <-time.After(3 * time.Second):
			t.Fatalf("only %d of 20 gifts answered", ok+fail)
		}
	}
	if fail == 0 || ok == 0 {
		t.Fatalf("rate limit: ok=%d fail=%d", ok, fail)
	}
}

func TestEventsOnlyFromYourRoom(t *testing.T) {
	_, srv := newServer(t, Config{})
	a, _ := join(t, srv, "A")
	b, _ := join(t, srv, "B")
	b.send(Msg{T: "state", Scene: "dig", Room: "dig:0:0:7", Star: ip(0), Planet: ip(0)})
	a.send(Msg{T: "state", Scene: "planet", Room: "planet:0:0", Star: ip(0), Planet: ip(0)})
	a.expect("state")
	b.expect("state")
	// A isn't in the cave, so can't dig it
	a.send(Msg{T: "ev", Room: "dig:0:0:7", Kind: "mask", Data: json.RawMessage(`{"dug":"////"}`)})
	a.send(Msg{T: "ping"})
	a.expect("pong")
	b.expectNone("ev")
}

func TestCrateLimitPerAddress(t *testing.T) {
	_, srv := newServer(t, Config{})
	a, _ := join(t, srv, "A")
	for i := 0; i < maxCratesPerIP; i++ {
		a.send(Msg{T: "drop", Star: ip(0), Planet: ip(0), Pos: []float64{1, 2, 3}, Items: map[string]int{"lumen": 1}})
		a.expect("drop_add")
		time.Sleep(260 * time.Millisecond) // under the crate rate limit
	}
	a.send(Msg{T: "drop", Star: ip(0), Planet: ip(0), Pos: []float64{1, 2, 3}, Items: map[string]int{"lumen": 1}})
	a.expect("drop_fail")
	// reconnecting doesn't reset it
	a.conn.Close(websocket.StatusNormalClosure, "")
	a2, _ := join(t, srv, "A")
	a2.send(Msg{T: "drop", Star: ip(0), Planet: ip(0), Pos: []float64{1, 2, 3}, Items: map[string]int{"lumen": 1}})
	if f := a2.expect("drop_fail"); !strings.Contains(f.Text, "Too many crates") {
		t.Fatalf("drop after reconnect: %+v", f)
	}
}

func TestNamesIgnoreInvisibleCharsAndCase(t *testing.T) {
	if got := cleanText("Aus​tin‮⁦!", 20); got != "Austin!" {
		t.Fatalf("cleanText: %q", got)
	}
	_, srv := newServer(t, Config{})
	join(t, srv, "Austin")
	_, w := join(t, srv, "AUS​TIN")
	if w.Name != "AUSTIN (2)" {
		t.Fatalf("lookalike name: %q", w.Name)
	}
}

func TestOriginAndStatus(t *testing.T) {
	hub, srv := newServer(t, Config{Password: "pw"})
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	url := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"
	if _, _, err := websocket.Dial(ctx, url, &websocket.DialOptions{HTTPHeader: http.Header{"Origin": {"https://evil.example"}}}); err == nil {
		t.Fatal("a browser origin was let in")
	}
	hub.cfg.AllowOrigins = []string{"*.example"}
	c, _, err := websocket.Dial(ctx, url, &websocket.DialOptions{HTTPHeader: http.Header{"Origin": {"https://good.example"}}})
	if err != nil {
		t.Fatalf("allowed origin refused: %v", err)
	}
	c.Close(websocket.StatusNormalClosure, "")
	if _, ok := hub.Status()["players"]; ok {
		t.Fatal("a password server lists its players")
	}
}
