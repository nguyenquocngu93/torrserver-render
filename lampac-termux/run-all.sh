#!/bin/bash
# ============================================================
#  run-all.sh — Run Lampac + TorrShelf together
# ============================================================
#  Usage:
#    sh run-all.sh          Start both
#    sh run-all.sh stop     Stop both
#    sh run-all.sh status   Check status
# ============================================================

set -e

TORRSHELF_DIR="${TORRSHELF_DIR:-$HOME/torr-shelf}"
LAMPAC_PORT=9118
TORRSHELF_PORT=8787
TORRSERVER_PORT=8090

R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' C='\033[0;36m' NC='\033[0m'

do_stop() {
  echo "Stopping Lampac..."
  lampac-stop 2>/dev/null || pkill -f "dotnet Core.dll" 2>/dev/null || true
  echo "Stopping TorrShelf..."
  pkill -f "node server.mjs" 2>/dev/null || true
  echo -e "${G}All stopped.${NC}"
}

do_status() {
  echo ""
  echo "=== Services ==="
  echo ""
  for svc in "Lampac:$LAMPAC_PORT" "TorrShelf:$TORRSHELF_PORT" "TorrServer:$TORRSERVER_PORT"; do
    name="${svc%%:*}"
    port="${svc##*:}"
    if curl -sf -o /dev/null "http://127.0.0.1:$port/" 2>/dev/null; then
      echo -e "  ${G}●${NC} $name : RUNNING  http://127.0.0.1:$port"
    else
      echo -e "  ${R}●${NC} $name : STOPPED"
    fi
  done
  echo ""
}

do_start() {
  echo ""
  echo -e "${C}====================================${NC}"
  echo -e "${C}  Lampac + TorrShelf Media Stack${NC}"
  echo -e "${C}====================================${NC}"
  echo ""

  # ---- Lampac ----
  echo -e "${Y}[1/2]${NC} Lampac..."
  if curl -sf -o /dev/null "http://127.0.0.1:$LAMPAC_PORT/" 2>/dev/null; then
    echo -e "  ${G}Already running${NC}"
  else
    lampac &
    i=0
    while [ "$i" -lt 20 ]; do
      curl -sf -o /dev/null "http://127.0.0.1:$LAMPAC_PORT/" 2>/dev/null && break
      sleep 2; i=$((i+2))
    done
    curl -sf -o /dev/null "http://127.0.0.1:$LAMPAC_PORT/" 2>/dev/null \
      && echo -e "  ${G}Ready${NC}" \
      || echo -e "  ${Y}Still starting...${NC}"
  fi

  # ---- TorrShelf ----
  echo ""
  echo -e "${Y}[2/2]${NC} TorrShelf..."
  if curl -sf -o /dev/null "http://127.0.0.1:$TORRSHELF_PORT/" 2>/dev/null; then
    echo -e "  ${G}Already running${NC}"
  elif [ ! -d "$TORRSHELF_DIR" ] || [ ! -f "$TORRSHELF_DIR/server.mjs" ]; then
    echo -e "  ${R}Not found at $TORRSHELF_DIR${NC}"
    echo "  Clone: git clone https://github.com/nguyenquocngu93/fshare.git $TORRSHELF_DIR"
  else
    cd "$TORRSHELF_DIR"
    [ ! -d node_modules ] && npm install 2>/dev/null
    npm start &
    i=0
    while [ "$i" -lt 20 ]; do
      curl -sf -o /dev/null "http://127.0.0.1:$TORRSHELF_PORT/" 2>/dev/null && break
      sleep 2; i=$((i+2))
    done
    curl -sf -o /dev/null "http://127.0.0.1:$TORRSHELF_PORT/" 2>/dev/null \
      && echo -e "  ${G}Ready${NC}" \
      || echo -e "  ${Y}Still starting...${NC}"
  fi

  echo ""
  echo -e "${G}=======================================${NC}"
  echo -e "${G}  All services started${NC}"
  echo -e "${G}=======================================${NC}"
  echo ""
  echo "  Lampac    : http://127.0.0.1:$LAMPAC_PORT   (browse phim, Lampa UI)"
  echo "  TorrShelf : http://127.0.0.1:$TORRSHELF_PORT (TMDB + scrapers)"
  echo "  TorrServer: http://127.0.0.1:$TORRSERVER_PORT (APK - torrents)"
  echo ""
  echo "  Torrents handled by TorrServer APK (not Lampac)"
  echo "  Scrapers handled by TorrShelf (UHDMovies, 4KHDHub, etc.)"
  echo ""
  echo "  Stop: sh $0 stop"
  echo "  Status: sh $0 status"
  echo ""
}

case "${1:-}" in
  stop)   do_stop ;;
  status) do_status ;;
  *)      do_start ;;
esac
