#!/bin/bash
# ============================================================
#  run-all.sh — Start both Lampac + TorrShelf on Termux
# ============================================================
#  Usage:  sh run-all.sh
#  Stop:   sh run-all.sh stop
#  Status: sh run-all.sh status
#
#  Requires:
#    - Lampac installed via sh lampac-termux/setup.sh
#    - TorrShelf cloned and npm installed
# ============================================================

set -e

TORRSHELF_DIR="${TORRSHELF_DIR:-$HOME/torr-shelf}"
LAMPAC_PORT=9118
TORRSHELF_PORT=8787

# Colors
R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' C='\033[0;36m' NC='\033[0m'

banner() {
  echo ""
  echo -e "${C}  =======================================${NC}"
  echo -e "${C}   Lampac + TorrShelf — Media Stack${NC}"
  echo -e "${C}  =======================================${NC}"
  echo ""
}

# ---- Stop all ----
do_stop() {
  echo "Stopping Lampac..."
  lampac-stop 2>/dev/null || pkill -f "dotnet Core.dll" 2>/dev/null || true
  echo "Stopping TorrShelf..."
  pkill -f "node server.mjs" 2>/dev/null || true
  echo -e "${G}All services stopped.${NC}"
}

# ---- Status ----
do_status() {
  echo ""
  echo "=== Services Status ==="
  echo ""

  # Lampac
  if curl -sf -o /dev/null "http://127.0.0.1:$LAMPAC_PORT/" 2>/dev/null; then
    echo -e "  ${G}●${NC} Lampac      : ${G}RUNNING${NC}  http://127.0.0.1:$LAMPAC_PORT"
  else
    echo -e "  ${R}●${NC} Lampac      : ${R}STOPPED${NC}"
  fi

  # TorrShelf
  if curl -sf -o /dev/null "http://127.0.0.1:$TORRSHELF_PORT/" 2>/dev/null; then
    echo -e "  ${G}●${NC} TorrShelf   : ${G}RUNNING${NC}  http://127.0.0.1:$TORRSHELF_PORT"
  else
    echo -e "  ${R}●${NC} TorrShelf   : ${R}STOPPED${NC}"
  fi

  # TorrServer
  if curl -sf -o /dev/null "http://127.0.0.1:8090/" 2>/dev/null; then
    echo -e "  ${G}●${NC} TorrServer  : ${G}RUNNING${NC}  http://127.0.0.1:8090"
  else
    echo -e "  ${R}●${NC} TorrServer  : ${R}STOPPED${NC}"
  fi

  echo ""
  echo "  URLs:"
  echo "    Lampac    : http://127.0.0.1:$LAMPAC_PORT"
  echo "    TorrShelf : http://127.0.0.1:$TORRSHELF_PORT"
  echo "    TorrServer: http://127.0.0.1:8090"
  echo ""
}

# ---- Start Lampac ----
start_lampac() {
  echo -e "${Y}[1/2]${NC} Starting Lampac..."
  if curl -sf -o /dev/null "http://127.0.0.1:$LAMPAC_PORT/" 2>/dev/null; then
    echo -e "  ${G}Already running${NC}"
    return 0
  fi
  lampac &
  LAMPAC_PID=$!
  echo "  PID: $LAMPAC_PID"

  # Wait for ready
  i=0
  while [ "$i" -lt 30 ]; do
    if curl -sf -o /dev/null "http://127.0.0.1:$LAMPAC_PORT/" 2>/dev/null; then
      echo -e "  ${G}Lampac ready!${NC}"
      return 0
    fi
    sleep 2
    i=$((i + 2))
  done
  echo -e "  ${Y}Lampac still starting...${NC}"
}

# ---- Start TorrShelf ----
start_torrshelf() {
  echo -e "${Y}[2/2]${NC} Starting TorrShelf..."
  if curl -sf -o /dev/null "http://127.0.0.1:$TORRSHELF_PORT/" 2>/dev/null; then
    echo -e "  ${G}Already running${NC}"
    return 0
  fi

  if [ ! -d "$TORRSHELF_DIR" ]; then
    echo -e "  ${R}TorrShelf not found at $TORRSHELF_DIR${NC}"
    echo "  Clone it first:"
    echo "    git clone https://github.com/nguyenquocngu93/fshare.git $TORRSHELF_DIR"
    echo "    cd $TORRSHELF_DIR && npm install"
    return 1
  fi

  cd "$TORRSHELF_DIR"

  if [ ! -f "server.mjs" ]; then
    echo -e "  ${R}server.mjs not found in $TORRSHELF_DIR${NC}"
    return 1
  fi

  # Install deps if needed
  if [ ! -d "node_modules" ]; then
    echo "  Installing dependencies..."
    npm install 2>/dev/null || true
  fi

  npm start &
  TORRSHELF_PID=$!
  echo "  PID: $TORRSHELF_PID"

  # Wait for ready
  i=0
  while [ "$i" -lt 30 ]; do
    if curl -sf -o /dev/null "http://127.0.0.1:$TORRSHELF_PORT/" 2>/dev/null; then
      echo -e "  ${G}TorrShelf ready!${NC}"
      return 0
    fi
    sleep 2
    i=$((i + 2))
  done
  echo -e "  ${Y}TorrShelf still starting...${NC}"
}

# ---- Deploy plugins ----
deploy_plugins() {
  echo ""
  echo "Deploying Lampa plugins to Lampac..."

  PLUGIN_DIR="/opt/lampac/plugins/override"
  MY_PLUGINS="$(cd "$(dirname "$0")" && pwd)/plugins"

  proot-distro login ubuntu -- bash -c "
    mkdir -p '$PLUGIN_DIR'
    cp '$MY_PLUGINS/vn-sources.js' '$PLUGIN_DIR/' 2>/dev/null && echo '  vn-sources.js OK' || true
    cp '$MY_PLUGINS/torrshelf-streams.js' '$PLUGIN_DIR/' 2>/dev/null && echo '  torrshelf-streams.js OK' || true
  "
}

# ---- Main ----
case "${1:-}" in
  stop)
    banner
    do_stop
    ;;
  status)
    banner
    do_status
    ;;
  deploy)
    banner
    deploy_plugins
    ;;
  *)
    banner
    echo "Starting all services..."
    echo ""

    start_lampac
    echo ""
    start_torrshelf

    echo ""
    echo -e "${G}=======================================${NC}"
    echo -e "${G}  All services started!${NC}"
    echo -e "${G}=======================================${NC}"
    echo ""
    echo "  Lampac    : http://127.0.0.1:$LAMPAC_PORT"
    echo "  TorrShelf : http://127.0.0.1:$TORRSHELF_PORT"
    echo "  TorrServer: http://127.0.0.1:8090"
    echo ""
    echo "  Lampa plugins:"
    echo "    - Phim Viet (KKPhim/OPhim/UHDMovie/4KHDHub)"
    echo "    - TorrShelf Streams (UHDMovies/4KHDHub/MoviesDrive)"
    echo ""
    echo "  Stop: sh $0 stop"
    echo "  Status: sh $0 status"
    echo ""

    # Keep running
    echo "Press Ctrl+C to stop all..."
    trap do_stop EXIT INT TERM
    wait
    ;;
esac
