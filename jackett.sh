#!/bin/sh
# Starts Jackett (port 9117) and exposes it via a cloudflared trycloudflare tunnel.
# Cấu hình indexer trước bằng:  sh jackett-setup.sh
set -e

cd "$(dirname "$0")"

# Self-healing: fetch binaries if the workspace copy is missing.
if [ ! -x ./bin/jackett/jackett ]; then
  echo "==> Chưa có Jackett — đang tải..."
  mkdir -p bin
  ARCH=$(uname -m)
  case "$ARCH" in
    aarch64|arm64) ASSET="Jackett.Binaries.LinuxARM64.tar.gz" ;;
    armv7l|armv8l|arm) ASSET="Jackett.Binaries.LinuxARM32.tar.gz" ;;
    *) ASSET="Jackett.Binaries.LinuxAMDx64.tar.gz" ;;
  esac
  curl -sL -o bin/jackett.tar.gz "https://github.com/Jackett/Jackett/releases/latest/download/$ASSET"
  tar xzf bin/jackett.tar.gz -C bin
  rm -f bin/jackett.tar.gz
  echo "    OK: bin/jackett/jackett"
fi
if [ ! -x ./bin/cloudflared ]; then
  mkdir -p bin
  curl -sL -o bin/cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
  chmod +x bin/cloudflared
fi

mkdir -p data/jackett

# Start Jackett (binds loopback on port 9117 by default).
./bin/jackett/jackett --DataFolder ./data/jackett --Port 9117 --NoUpdates &
JACKETT_PID=$!

# Wait until the web UI is answering.
ready=0
i=0
while [ "$i" -lt 90 ]; do
  if curl -sf -o /dev/null "http://127.0.0.1:9117"; then
    ready=1
    break
  fi
  sleep 1
  i=$((i + 1))
done

if [ "$ready" -ne 1 ]; then
  echo "Jackett did not become ready on port 9117"
  kill "$JACKETT_PID" 2>/dev/null || true
  exit 1
fi

echo "Jackett is up on http://127.0.0.1:9117, opening cloudflared tunnel..."

# Keep the tunnel open in the foreground; Jackett keeps running as our child.
# --protocol http2: this sandbox blocks QUIC/UDP, so force the reliable HTTP/2 transport.
exec ./bin/cloudflared tunnel --url http://127.0.0.1:9117 --no-autoupdate --protocol http2
