#!/bin/bash
# start.sh — Start both Lampac + TorrShelf services
# Usage: sh lampac-termux/start.sh [services]
#   Default: start both
#   Options: --lampac, --torrshelf, --all

set -e

SERVICE="${1:---all}"

echo "=== Media Stack Start ==="
echo ""

# ─── Start TorrShelf API ────────────────────────────────────
if [ "$SERVICE" = "--torrshelf" ] || [ "$SERVICE" = "--all" ]; then
  echo "[1/2] Starting TorrShelf API..."
  proot-distro login ubuntu -- bash -c '
    if pgrep -f "python3.*server.py" >/dev/null; then
      echo "  TorrShelf API already running"
    else
      cd /opt/torrshelf && nohup python3 server.py > /tmp/torrshelf.log 2>&1 &
      sleep 2
      if pgrep -f "python3.*server.py" >/dev/null; then
        echo "  ✅ TorrShelf API started (port 8788)"
      else
        echo "  ❌ TorrShelf API failed to start"
        echo "  Check: cat /tmp/torrshelf.log"
      fi
    fi
  '
  echo ""
fi

# ─── Start Lampac ───────────────────────────────────────────
if [ "$SERVICE" = "--lampac" ] || [ "$SERVICE" = "--all" ]; then
  echo "[2/2] Starting Lampac NextGen..."
  proot-distro login ubuntu -- bash -c '
    if pgrep -f "dotnet Core.dll" >/dev/null; then
      echo "  Lampac already running"
    else
      cd /opt/lampac && nohup sh start.sh > /tmp/lampac.log 2>&1 &
      sleep 3
      if pgrep -f "dotnet Core.dll" >/dev/null; then
        echo "  ✅ Lampac started (port 9118)"
      else
        echo "  ❌ Lampac failed to start"
        echo "  Check: cat /tmp/lampac.log"
      fi
    fi
  '
  echo ""
fi

echo "=== Status ==="
proot-distro login ubuntu -- bash -c '
  echo "TorrShelf API:"
  if pgrep -f "python3.*server.py" >/dev/null; then
    echo "  ✅ Running (port 8788)"
  else
    echo "  ❌ Not running"
  fi

  echo "Lampac:"
  if pgrep -f "dotnet Core.dll" >/dev/null; then
    echo "  ✅ Running (port 9118)"
  else
    echo "  ❌ Not running"
  fi
'

echo ""
echo "Access:"
echo "  Lampac UI:     http://127.0.0.1:9118"
echo "  TorrShelf API: http://127.0.0.1:8788"
echo ""
echo "To stop all: sh lampac-termux/stop.sh"
