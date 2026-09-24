// Star Circuit multiplayer server.
//
// Players keep their own saves; this server shares presence (who's where),
// chat, item gifts and crates dropped on planets. One small binary:
//
//	star-circuit-server -addr :7777
//	star-circuit-server -addr :7777 -password hunter2 -data drops.json
//	star-circuit-server -addr :443 -tls-cert fullchain.pem -tls-key privkey.pem
//
// Clients connect to ws://host:7777/ws (or wss:// behind TLS). The game
// trusts its players' clients: run it for friends, not strangers.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"log"
	"net"
	"net/http"
	"net/url"
	"path"
	"strings"
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
	origins := flag.String("allow-origin", "", "comma-separated browser origins allowed to connect (e.g. example.com, *.example.com, or *); the game itself sends none")
	flag.Parse()

	var allow []string
	for _, o := range strings.Split(*origins, ",") {
		if o = strings.TrimSpace(o); o != "" {
			allow = append(allow, o)
		}
	}
	hub := NewHub(Config{Name: *name, Password: *password, Motd: *motd, MaxPlayers: *maxPlayers, DataFile: *data, DropTTL: *ttl, AllowOrigins: allow})
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
		// the game sends no Origin; a web page does, and isn't let in unless allowed
		if o := r.Header.Get("Origin"); o != "" && !originAllowed(o, hub.cfg.AllowOrigins) {
			http.Error(w, "Browser connections aren't allowed on this server.", http.StatusForbidden)
			return
		}
		conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true}) // origin checked above
		if err != nil {
			return
		}
		serve(r.Context(), hub, conn, clientIP(r))
	})
	return mux
}

// originAllowed matches an Origin header's host against -allow-origin patterns.
func originAllowed(origin string, patterns []string) bool {
	u, err := url.Parse(origin)
	if err != nil || u.Host == "" {
		return false
	}
	host := strings.ToLower(u.Host)
	for _, p := range patterns {
		p = strings.ToLower(p)
		if p == "*" {
			return true
		}
		if ok, _ := path.Match(p, host); ok {
			return true
		}
		if ok, _ := path.Match(p, u.Hostname()); ok {
			return true
		}
	}
	return false
}

// clientIP is the connecting address. Behind a reverse proxy on the same
// machine, the proxy's X-Forwarded-For entry (the last one) is used.
func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	if ip := net.ParseIP(host); ip != nil && ip.IsLoopback() {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			parts := strings.Split(xff, ",")
			if last := strings.TrimSpace(parts[len(parts)-1]); net.ParseIP(last) != nil {
				return last
			}
		}
	}
	return host
}

func serve(ctx context.Context, hub *Hub, conn *websocket.Conn, remote string) {
	conn.SetReadLimit(16 * 1024)
	c := hub.Register(remote)
	if c == nil {
		log.Printf("%s refused: too many connections", remote)
		conn.Close(websocket.StatusTryAgainLater, "The server is busy.")
		return
	}
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
