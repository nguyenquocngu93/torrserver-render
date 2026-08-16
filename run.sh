#!/bin/sh
# Starts TorrServer (port 8090) and exposes it via a cloudflared trycloudflare tunnel.
set -e

cd "$(dirname "$0")"

# Self-healing: fetch binaries if the workspace copy is missing.
if [ ! -x ./bin/torrserver ]; then
  mkdir -p bin
  curl -sL -o bin/torrserver "https://github.com/YouROK/TorrServer/releases/download/MatriX.142.2/TorrServer-linux-amd64"
  chmod +x bin/torrserver
fi
if [ ! -x ./bin/cloudflared ]; then
  mkdir -p bin
  curl -sL -o bin/cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
  chmod +x bin/cloudflared
fi

mkdir -p data

# Start TorrServer (binds all interfaces on port 8090 by default).
./bin/torrserver -d ./data -p 8090 &
TORR_PID=$!

# Wait until the web UI is answering.
ready=0
i=0
while [ "$i" -lt 60 ]; do
  if curl -sf -o /dev/null "http://127.0.0.1:8090"; then
    ready=1
    break
  fi
  sleep 1
  i=$((i + 1))
done

if [ "$ready" -ne 1 ]; then
  echo "TorrServer did not become ready on port 8090"
  kill "$TORR_PID" 2>/dev/null || true
  exit 1
fi

echo "TorrServer is up on http://127.0.0.1:8090, opening cloudflared tunnel..."

# Keep the tunnel open in the foreground; TorrServer keeps running as our child.
# --protocol http2: this sandbox blocks QUIC/UDP, so force the reliable HTTP/2 transport.
exec ./bin/cloudflared tunnel --url http://127.0.0.1:8090 --no-autoupdate --protocol http2
