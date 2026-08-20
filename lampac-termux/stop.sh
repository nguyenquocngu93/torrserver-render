#!/bin/bash
# stop.sh — Stop both Lampac + TorrShelf services
# Usage: sh lampac-termux/stop.sh [services]
#   Default: stop both
#   Options: --lampac, --torrshelf, --all

set -e

SERVICE="${1:---all}"

echo "=== Media Stack Stop ==="
echo ""

if [ "$SERVICE" = "--torrshelf" ] || [ "$SERVICE" = "--all" ]; then
  echo "[1/2] Stopping TorrShelf API..."
  proot-distro login ubuntu -- bash -c '
    if pgrep -f "python3.*server.py" >/dev/null; then
      pkill -f "python3.*server.py"
      echo "  ✅ TorrShelf API stopped"
    else
      echo "  TorrShelf API not running"
    fi
  '
fi

if [ "$SERVICE" = "--lampac" ] || [ "$SERVICE" = "--all" ]; then
  echo "[2/2] Stopping Lampac NextGen..."
  proot-distro login ubuntu -- bash -c '
    if pgrep -f "dotnet Core.dll" >/dev/null; then
      pkill -f "dotnet Core.dll"
      echo "  ✅ Lampac stopped"
    else
      echo "  Lampac not running"
    fi
  '
fi

echo ""
echo "=== All services stopped ==="
