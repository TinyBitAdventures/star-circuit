// Star Circuit multiplayer server.
//
// Players keep their own saves; this server shares presence (who's where),
// chat, item gifts and crates dropped on planets. One small binary:
//
//	star-circuit-server -addr :7777
//	star-circuit-server -addr :7777 -password hunter2 -data drops.json
//	star-circuit-server -addr :443 -tls-cert fullchain.pem -tls-key privkey.pem
//
// Clients connect to ws://host:7777/ws (or wss:// behind TLS).
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"log"
	"net/http"
	"time"

	"github.com/coder/websocket"
)

func main() {
	addr := flag.String("addr", ":7777", "listen address")
	name := flag.String("name", "Star Circuit server", "server name shown to players")
	password := flag.String("password", "", "optional password players must enter")
	motd := flag.String("motd", "", "message of the day shown when players join")
	maxPlayers := flag.Int("max-players", 16, "most players at once")
	data := flag.String("data", "star-circuit-drops.json", "file that keeps dropped crates across restarts (empty to disable)")
	ttl := flag.Duration("drop-ttl", 72*time.Hour, "how long an untouched crate lasts")
	cert := flag.String("tls-cert", "", "TLS certificate (serve wss:// directly)")
	key := flag.String("tls-key", "", "TLS private key")
	flag.Parse()

	hub := NewHub(Config{Name: *name, Password: *password, Motd: *motd, MaxPlayers: *maxPlayers, DataFile: *data, DropTTL: *ttl})
	go func() {
		for range time.Tick(10 * time.Second) {
			hub.Sweep()
		}
	}()

	srv := &http.Server{Addr: *addr, Handler: NewMux(hub), ReadHeaderTimeout: 10 * time.Second}
	log.Printf("Star Circuit server %q listening on %s (protocol %s)", *name, *addr, ProtocolVersion)
	var err error
	if *cert != "" {
		err = srv.ListenAndServeTLS(*cert, *key)
	} else {
		err = srv.ListenAndServe()
	}
	log.Fatal(err)
}

// NewMux serves the status page at / and the game socket at /ws.
func NewMux(hub *Hub) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(hub.Status())
	})
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		// game clients send no Origin; browsers are welcome too
		conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
		if err != nil {
			return
		}
		serve(r.Context(), hub, conn, r.RemoteAddr)
	})
	return mux
}

func serve(ctx context.Context, hub *Hub, conn *websocket.Conn, remote string) {
	conn.SetReadLimit(64 * 1024)
	c := hub.Register()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// writer: everything queued for this client, until the hub closes send
	go func() {
		for b := range c.send {
			wctx, wcancel := context.WithTimeout(ctx, 5*time.Second)
			err := conn.Write(wctx, websocket.MessageText, b)
			wcancel()
			if err != nil {
				cancel()
				return
			}
		}
		// the hub dropped us: flush a close so the client sees why
		conn.Close(websocket.StatusNormalClosure, "")
		cancel()
	}()

	for {
		// clients send state several times a second and ping when idle
		rctx, rcancel := context.WithTimeout(ctx, 30*time.Second)
		typ, data, err := conn.Read(rctx)
		rcancel()
		if err != nil {
			if !errors.Is(err, context.Canceled) {
				log.Printf("%s disconnected: %v", remote, websocket.CloseStatus(err))
			}
			break
		}
		if typ != websocket.MessageText {
			continue
		}
		var m Msg
		if json.Unmarshal(data, &m) != nil {
			continue
		}
		if !hub.Handle(c, &m) {
			// give a rejected hello time to deliver its error
			time.Sleep(200 * time.Millisecond)
			break
		}
	}
	hub.Unregister(c)
	conn.Close(websocket.StatusNormalClosure, "bye")
}
