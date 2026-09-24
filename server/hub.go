package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode"
)

// ProtocolVersion is bumped when messages change incompatibly.
const ProtocolVersion = "2"

// Msg is every message in both directions. Unused fields are omitted.
type Msg struct {
	T string `json:"t"`

	// identity
	ID       int            `json:"id,omitempty"`
	Name     string         `json:"name,omitempty"`
	Robot    string         `json:"robot,omitempty"`
	Look     map[string]any `json:"look,omitempty"`
	Version  string         `json:"version,omitempty"`
	Password string         `json:"password,omitempty"`

	// where a player is: scene "planet", "space" or "away" (a cave, the sea...)
	Scene  string    `json:"scene,omitempty"`
	Star   *int      `json:"star,omitempty"`
	Planet *int      `json:"planet,omitempty"`
	Label  string    `json:"label,omitempty"`
	Pos    []float64 `json:"pos,omitempty"`
	Fwd    []float64 `json:"fwd,omitempty"`
	Anim   string    `json:"anim,omitempty"`
	// a shared space inside a scene: "planet:0:2", "space:0", "dig:<cave key>", "sea:<sea key>"
	Room string `json:"room,omitempty"`

	// room events (dig a tile, open a clam, a kill...): relayed to everyone in the same room
	Kind string          `json:"kind,omitempty"`
	Data json.RawMessage `json:"data,omitempty"`

	// chat, gifts, drops
	Text  string         `json:"text,omitempty"`
	To    int            `json:"to,omitempty"`
	Item  string         `json:"item,omitempty"`
	Qty   int            `json:"qty,omitempty"`
	Items map[string]int `json:"items,omitempty"`
	Drop  *Drop          `json:"drop,omitempty"`

	// welcome
	Players []*PlayerInfo `json:"players,omitempty"`
	Drops   []*Drop       `json:"drops,omitempty"`
	Motd    string        `json:"motd,omitempty"`
}

// PlayerInfo is what others see of a connected player.
type PlayerInfo struct {
	ID    int            `json:"id"`
	Name  string         `json:"name"`
	Robot string         `json:"robot"`
	Look  map[string]any `json:"look,omitempty"`
	State *Msg           `json:"state,omitempty"`
}

// Drop is a crate of items left on a planet for anyone to pick up.
type Drop struct {
	ID     int            `json:"id"`
	Star   int            `json:"star"`
	Planet int            `json:"planet"`
	Pos    []float64      `json:"pos"`
	Items  map[string]int `json:"items"`
	By     string         `json:"by"`
	At     int64          `json:"at"`
}

// Client is one connection. Outgoing messages go through send; the
// connection's writer goroutine drains it.
type Client struct {
	info    PlayerInfo
	send    chan []byte
	joined  bool
	drops   int
	lastMsg time.Time
	budget  float64 // token bucket against floods
	room    string
}

type Config struct {
	Name       string
	Password   string
	Motd       string
	MaxPlayers int
	DataFile   string
	DropTTL    time.Duration
	MaxDrops   int
}

// Hub holds every player and drop. One mutex: the game is small.
type Hub struct {
	cfg     Config
	mu      sync.Mutex
	clients map[*Client]bool
	drops   map[int]*Drop
	nextID  int
	dirty   bool
}

func NewHub(cfg Config) *Hub {
	if cfg.MaxPlayers <= 0 {
		cfg.MaxPlayers = 16
	}
	if cfg.MaxDrops <= 0 {
		cfg.MaxDrops = 500
	}
	h := &Hub{cfg: cfg, clients: map[*Client]bool{}, drops: map[int]*Drop{}, nextID: 1}
	h.load()
	return h
}

var itemRe = regexp.MustCompile(`^[a-z0-9_]{1,40}$`)

func cleanText(s string, max int) string {
	s = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return -1
		}
		return r
	}, s)
	s = strings.TrimSpace(s)
	if r := []rune(s); len(r) > max {
		s = string(r[:max])
	}
	return s
}

func validVec(v []float64) bool {
	if len(v) != 3 {
		return false
	}
	for _, f := range v {
		if math.IsNaN(f) || math.IsInf(f, 0) || math.Abs(f) > 1e7 {
			return false
		}
	}
	return true
}

func validItems(items map[string]int) bool {
	if len(items) == 0 || len(items) > 20 {
		return false
	}
	for k, q := range items {
		if !itemRe.MatchString(k) || q < 1 || q > 9999 {
			return false
		}
	}
	return true
}

func encode(m *Msg) []byte {
	b, _ := json.Marshal(m)
	return b
}

// queue sends to one client without blocking. Position updates are
// droppable; anything else that can't be queued disconnects a stuck client.
func (h *Hub) queue(c *Client, b []byte, droppable bool) {
	select {
	case c.send <- b:
	default:
		if !droppable {
			h.dropClientLocked(c)
		}
	}
}

func (h *Hub) broadcast(m *Msg, except *Client, droppable bool) {
	b := encode(m)
	for c := range h.clients {
		if c != except && c.joined {
			h.queue(c, b, droppable)
		}
	}
}

func (h *Hub) dropClientLocked(c *Client) {
	if !h.clients[c] {
		return
	}
	delete(h.clients, c)
	close(c.send)
	if c.joined {
		h.broadcast(&Msg{T: "leave", ID: c.info.ID}, nil, false)
	}
}

// Register a new connection (before hello).
func (h *Hub) Register() *Client {
	c := &Client{send: make(chan []byte, 256), lastMsg: time.Now(), budget: 40}
	h.mu.Lock()
	h.clients[c] = true
	h.mu.Unlock()
	return c
}

func (h *Hub) Unregister(c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.dropClientLocked(c)
}

func (h *Hub) uniqueName(name string) string {
	taken := map[string]bool{}
	for c := range h.clients {
		if c.joined {
			taken[strings.ToLower(c.info.Name)] = true
		}
	}
	if !taken[strings.ToLower(name)] {
		return name
	}
	for i := 2; ; i++ {
		n := fmt.Sprintf("%s (%d)", name, i)
		if !taken[strings.ToLower(n)] {
			return n
		}
	}
}

func (h *Hub) reply(c *Client, m *Msg) {
	h.queue(c, encode(m), false)
}

// Handle one decoded message from a client. Returns false to disconnect.
func (h *Hub) Handle(c *Client, m *Msg) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	if !h.clients[c] {
		return false
	}
	// token bucket: 60 messages a second sustained, bursts of 80
	now := time.Now()
	c.budget = math.Min(80, c.budget+now.Sub(c.lastMsg).Seconds()*60)
	c.lastMsg = now
	if c.budget < 1 {
		return true // ignore the flood, keep the connection
	}
	c.budget--

	if !c.joined {
		if m.T != "hello" {
			return false
		}
		return h.hello(c, m)
	}
	switch m.T {
	case "state":
		if m.Pos != nil && !validVec(m.Pos) || m.Fwd != nil && !validVec(m.Fwd) {
			return true
		}
		c.room = cleanText(m.Room, 80)
		st := &Msg{T: "state", ID: c.info.ID, Scene: cleanText(m.Scene, 12), Star: m.Star, Planet: m.Planet,
			Label: cleanText(m.Label, 40), Pos: m.Pos, Fwd: m.Fwd, Anim: cleanText(m.Anim, 12), Room: c.room}
		c.info.State = st
		h.broadcast(st, c, true)
	case "chat":
		text := cleanText(m.Text, 200)
		if text != "" {
			h.broadcast(&Msg{T: "chat", ID: c.info.ID, Name: c.info.Name, Text: text}, nil, false)
		}
	case "look":
		c.info.Look = m.Look
		h.broadcast(&Msg{T: "look", ID: c.info.ID, Look: m.Look}, c, false)
	case "give":
		h.give(c, m)
	case "drop":
		h.drop(c, m)
	case "pickup":
		h.pickup(c, m)
	case "ev":
		h.event(c, m)
	case "ping":
		h.reply(c, &Msg{T: "pong"})
	}
	return true
}

func (h *Hub) hello(c *Client, m *Msg) bool {
	if m.Version != ProtocolVersion {
		h.reply(c, &Msg{T: "error", Text: fmt.Sprintf("This server speaks protocol %s; your game speaks %s. Update the game or the server.", ProtocolVersion, m.Version)})
		return false
	}
	if h.cfg.Password != "" && m.Password != h.cfg.Password {
		h.reply(c, &Msg{T: "error", Text: "Wrong server password."})
		return false
	}
	n := 0
	for o := range h.clients {
		if o.joined {
			n++
		}
	}
	if n >= h.cfg.MaxPlayers {
		h.reply(c, &Msg{T: "error", Text: "The server is full."})
		return false
	}
	name := cleanText(m.Name, 20)
	if name == "" {
		name = "Unit"
	}
	c.info = PlayerInfo{ID: h.nextID, Name: h.uniqueName(name), Robot: cleanText(m.Robot, 20), Look: m.Look}
	h.nextID++
	c.joined = true
	players := []*PlayerInfo{}
	for o := range h.clients {
		if o != c && o.joined {
			info := o.info
			players = append(players, &info)
		}
	}
	drops := []*Drop{}
	for _, d := range h.drops {
		drops = append(drops, d)
	}
	log.Printf("%s joined (%d online)", c.info.Name, n+1)
	h.reply(c, &Msg{T: "welcome", ID: c.info.ID, Name: c.info.Name, Players: players, Drops: drops, Motd: h.cfg.Motd})
	info := c.info
	h.broadcast(&Msg{T: "join", ID: info.ID, Name: info.Name, Robot: info.Robot, Look: info.Look}, c, false)
	return true
}

// event relays a room event to everyone else currently in that room.
func (h *Hub) event(c *Client, m *Msg) {
	room := cleanText(m.Room, 80)
	kind := cleanText(m.Kind, 20)
	if room == "" || kind == "" || len(m.Data) > 8192 || (len(m.Data) > 0 && !json.Valid(m.Data)) {
		return
	}
	b := encode(&Msg{T: "ev", ID: c.info.ID, Name: c.info.Name, Room: room, Kind: kind, Data: m.Data})
	for o := range h.clients {
		if o != c && o.joined && o.room == room {
			h.queue(o, b, false)
		}
	}
}

func (h *Hub) find(id int) *Client {
	for c := range h.clients {
		if c.joined && c.info.ID == id {
			return c
		}
	}
	return nil
}

// give forwards items to another player. The sender has already taken them
// out of their hold; give_fail hands them back.
func (h *Hub) give(c *Client, m *Msg) {
	if !itemRe.MatchString(m.Item) || m.Qty < 1 || m.Qty > 9999 {
		return
	}
	to := h.find(m.To)
	if to == nil || to == c {
		h.reply(c, &Msg{T: "give_fail", Item: m.Item, Qty: m.Qty, Text: "That player isn't here any more."})
		return
	}
	h.reply(to, &Msg{T: "gift", ID: c.info.ID, Name: c.info.Name, Item: m.Item, Qty: m.Qty})
	h.reply(c, &Msg{T: "give_ok", To: to.info.ID, Name: to.info.Name, Item: m.Item, Qty: m.Qty})
}

func (h *Hub) drop(c *Client, m *Msg) {
	if m.Star == nil || m.Planet == nil || !validVec(m.Pos) || !validItems(m.Items) {
		return
	}
	if len(h.drops) >= h.cfg.MaxDrops || c.drops >= 50 {
		h.reply(c, &Msg{T: "drop_fail", Items: m.Items, Text: "Too many crates are lying around. Pick some up first."})
		return
	}
	d := &Drop{ID: h.nextID, Star: *m.Star, Planet: *m.Planet, Pos: m.Pos, Items: m.Items, By: c.info.Name, At: time.Now().Unix()}
	h.nextID++
	h.drops[d.ID] = d
	c.drops++
	h.dirty = true
	h.broadcast(&Msg{T: "drop_add", Drop: d}, nil, false)
}

// pickup: the first request for a crate wins; everyone else is told it's gone.
func (h *Hub) pickup(c *Client, m *Msg) {
	d, ok := h.drops[m.ID]
	if !ok {
		h.reply(c, &Msg{T: "pickup_fail", ID: m.ID})
		return
	}
	delete(h.drops, m.ID)
	h.dirty = true
	h.reply(c, &Msg{T: "pickup_ok", ID: d.ID, Items: d.Items, Name: d.By})
	h.broadcast(&Msg{T: "drop_remove", ID: d.ID}, nil, false)
}

// Sweep expires old crates and saves drops if they changed.
func (h *Hub) Sweep() {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.cfg.DropTTL > 0 {
		cut := time.Now().Add(-h.cfg.DropTTL).Unix()
		for id, d := range h.drops {
			if d.At < cut {
				delete(h.drops, id)
				h.dirty = true
				h.broadcast(&Msg{T: "drop_remove", ID: id}, nil, false)
			}
		}
	}
	if h.dirty {
		h.save()
		h.dirty = false
	}
}

type saved struct {
	NextID int     `json:"next_id"`
	Drops  []*Drop `json:"drops"`
}

func (h *Hub) save() {
	if h.cfg.DataFile == "" {
		return
	}
	s := saved{NextID: h.nextID}
	for _, d := range h.drops {
		s.Drops = append(s.Drops, d)
	}
	b, _ := json.MarshalIndent(s, "", "  ")
	tmp := h.cfg.DataFile + ".tmp"
	if os.WriteFile(tmp, b, 0o644) == nil {
		os.Rename(tmp, h.cfg.DataFile)
	}
}

func (h *Hub) load() {
	if h.cfg.DataFile == "" {
		return
	}
	b, err := os.ReadFile(h.cfg.DataFile)
	if err != nil {
		return
	}
	var s saved
	if json.Unmarshal(b, &s) != nil {
		return
	}
	for _, d := range s.Drops {
		if d != nil && validItems(d.Items) && validVec(d.Pos) {
			h.drops[d.ID] = d
		}
	}
	if s.NextID > h.nextID {
		h.nextID = s.NextID
	}
}

// Status is the public summary served at GET /.
func (h *Hub) Status() map[string]any {
	h.mu.Lock()
	defer h.mu.Unlock()
	names := []string{}
	for c := range h.clients {
		if c.joined {
			names = append(names, c.info.Name)
		}
	}
	return map[string]any{"game": "Star Circuit", "name": h.cfg.Name, "protocol": ProtocolVersion,
		"players": names, "max_players": h.cfg.MaxPlayers, "drops": len(h.drops), "password": h.cfg.Password != ""}
}
