#!/usr/bin/env bash
# Cross-compile the multiplayer server for every platform into ../build/server/.
set -euo pipefail
cd "$(dirname "$0")"
out=../build/server
mkdir -p "$out"
for target in darwin/arm64 darwin/amd64 windows/amd64 linux/amd64 linux/arm64; do
	os=${target%/*}
	arch=${target#*/}
	ext=""
	[[ $os == windows ]] && ext=".exe"
	name="star-circuit-server-$os-$arch$ext"
	CGO_ENABLED=0 GOOS=$os GOARCH=$arch go build -trimpath -ldflags "-s -w" -o "$out/$name" .
	echo "built $out/$name"
done
