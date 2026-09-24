# Star Circuit multiplayer server

A small Go program that lets friends play Star Circuit together. Everyone keeps
their own save; the server shares who is where (you see each other's robots on
the same planet and flying in the same system), chat, item gifts, and crates
dropped on planets for anyone to pick up. Mac and Windows players can share a
server.

## Run it

Download the binary for your machine from the release (or build it, below) and run:

    ./star-circuit-server                      # listens on port 7777
    ./star-circuit-server -password hunter2    # players must enter the password
    ./star-circuit-server -motd "Welcome! Be nice."

Options: `-addr :7777`, `-name`, `-password`, `-motd`, `-max-players 16`,
`-data star-circuit-drops.json` (keeps dropped crates across restarts, `""` to
disable), `-drop-ttl 72h`, `-tls-cert` / `-tls-key` (serve `wss://` directly).
Open `http://host:7777/` to see who's online.

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

    go build -o star-circuit-server .    # this machine
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
