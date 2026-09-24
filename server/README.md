# Star Circuit multiplayer server

A small Go program that lets friends play Star Circuit together. Everyone keeps
their own save; the server shares who is where (you see each other's robots on
the same planet and flying in the same system), chat, item gifts, and crates
dropped on planets for anyone to pick up. Mac and Windows players can share a
server.

**Play with friends.** Each game keeps its own save and the server trusts what
players' games tell it (items given, kills shared, tunnels dug), so anyone who
joins could cheat or mess with the shared caves. Set a password and only give
it to people you know.

## Run it

Download the binary for your machine from the release (or build it, below). The
release files are named for the system they run on:

| System | File |
|---|---|
| macOS, Apple silicon | `star-circuit-server-darwin-arm64` |
| macOS, Intel | `star-circuit-server-darwin-amd64` |
| Windows | `star-circuit-server-windows-amd64.exe` |
| Linux, x86-64 | `star-circuit-server-linux-amd64` |
| Linux, ARM (Raspberry Pi 4/5) | `star-circuit-server-linux-arm64` |

Run it from a terminal (the examples use the Apple silicon name; use yours):

    ./star-circuit-server-darwin-arm64                      # listens on port 7777
    ./star-circuit-server-darwin-arm64 -password hunter2    # players must enter the password
    ./star-circuit-server-darwin-arm64 -motd "Welcome! Be nice."

Options: `-addr :7777`, `-name`, `-password`, `-motd`, `-max-players 16`,
`-data star-circuit-drops.json` (keeps dropped crates across restarts, `""` to
disable), `-drop-ttl 72h`, `-tls-cert` / `-tls-key` (serve `wss://` directly),
`-allow-origin` (let web pages from these hosts connect; the game itself never
needs it). Open `http://host:7777/` to see how many are online (and who, unless
the server has a password).

The crate file (`star-circuit-drops.json`) is written to the folder you run the
server from, so start it from the same folder each time (or pass `-data` a full path).

### macOS

    chmod +x star-circuit-server-darwin-arm64
    xattr -d com.apple.quarantine star-circuit-server-darwin-arm64
    ./star-circuit-server-darwin-arm64

The `xattr` line stops macOS refusing to run a download it can't verify. The
first time, macOS may ask whether to accept incoming connections: allow them.

### Windows

Open PowerShell in the download folder and run `.\star-circuit-server-windows-amd64.exe`
(double-clicking works too). If SmartScreen warns, choose More info > Run anyway.
When Windows Firewall asks, allow it on the networks your friends connect from.

### Linux

    chmod +x star-circuit-server-linux-amd64
    ./star-circuit-server-linux-amd64 -password hunter2

To keep it running, a systemd unit (`/etc/systemd/system/star-circuit.service`):

    [Unit]
    Description=Star Circuit server
    After=network-online.target

    [Service]
    ExecStart=/opt/star-circuit/star-circuit-server-linux-amd64 -password hunter2
    WorkingDirectory=/var/lib/star-circuit
    StateDirectory=star-circuit
    DynamicUser=yes
    Restart=on-failure

    [Install]
    WantedBy=multi-user.target

The crate file lands in `/var/lib/star-circuit`. Then `sudo systemctl enable --now star-circuit`,
and `journalctl -u star-circuit -f` shows the log.

### Limits

The server holds up to twice `-max-players` (plus 8) open connections, closes any that
don't join within 5 seconds, and makes an address wait (up to 5 minutes) after three wrong
passwords. Each address can have 50 crates lying around at once (500 on the server). Chat,
looks, gifts and crates are rate limited; a gift or crate the server refuses always goes
back to the sender. Behind a reverse proxy on the same machine, the proxy's
`X-Forwarded-For` address is used for these limits.

## Joining

In the game press **P** (or Esc, then Multiplayer) and enter the address:

| Where | Players type |
|---|---|
| Same network | the host's LAN address, e.g. `192.168.1.20` (port 7777 is assumed) |
| Over the internet | the host's public IP or domain, e.g. `play.example.com` (forward TCP 7777 on the router) |
| Behind HTTPS | `wss://play.example.com` |

### HTTPS with Caddy

    play.example.com {
        reverse_proxy /ws localhost:7777
        reverse_proxy / localhost:7777
    }

## Build

    go build -o star-circuit-server .    # this machine (the gitignored ./star-circuit-server)
    ./build.sh                           # every platform into ../build/server/
    go test -race ./...

## Protocol

JSON text frames over a WebSocket at `/ws`. The client sends `hello` (name,
robot, look, version, password), then `state` about 10 times a second
(scene, star, planet, position, facing, animation), plus `chat`, `give`,
`drop`, `pickup`, `look` and `ping`. The server answers `welcome` (your id, the
players and crates already there), relays `join` / `leave` / `state` / `chat` /
`look`, forwards gifts (`gift`, `give_ok`, `give_fail`) and owns crates
(`drop_add`, `drop_remove`, `pickup_ok`, `pickup_fail`): the first pickup
request wins. Space positions are relative to the nearest planet, because
orbits run on each player's own clock. See `hub.go` for the message struct.

Each `state` names a **room** (`planet:<star>:<planet>`, `space:<star>`, `dig:<cave>`, `sea:<sea>`). An `ev`
message (`room`, `kind`, `data`) goes only to the other players in that room: tiles dug, dug-tile masks when
someone arrives, clams, kelp, the wreck, batched hits on drones (`hits`) and kills (`kill`, `skill` in space).
A player can only send events to the room their last `state` put them in. Protocol 2 added rooms;
protocol 3 made every refused gift or crate answer `give_fail` / `drop_fail` with a reason, trimmed
looks to the known keys (head, top, pack, finish, shell, accent, glow, flame) and gave space kills an
`id`. The game and the server must match.
