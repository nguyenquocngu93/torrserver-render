#!/bin/bash
# status.sh — Check status of Lampac + TorrShelf services
# Usage: sh lampac-termux/status.sh

set -e

echo "=== Media Stack Status ==="
echo ""

proot-distro login ubuntu -- bash -c '
  # TorrShelf API
  echo "┌─────────────────────────────────────────┐"
  echo "│ TorrShelf API                           │"
  echo "├─────────────────────────────────────────┤"
  if pgrep -f "python3.*server.py" >/dev/null; then
    PID=$(pgrep -f "python3.*server.py")
    echo "│ Status:  ✅ Running (PID: $PID)          │"
    echo "│ Port:    8788                           │"
    echo "│ API:     http://127.0.0.1:8788         │"
    echo "│                                        │"
    echo "│ Sources:                                │"
    curl -s http://127.0.0.1:8788/api/sources 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for s in data:
        print(f\"│   • {s}\")
except:
    print(\"│   (cannot connect)\")
" 2>/dev/null || echo "│   (cannot connect)"
  else
    echo "│ Status:  ❌ Not running                 │"
    echo "│ Start:   torrshelf                      │"
  fi
  echo "└─────────────────────────────────────────┘"
  echo ""

  # Lampac
  echo "┌─────────────────────────────────────────┐"
  echo "│ Lampac NextGen                          │"
  echo "├─────────────────────────────────────────┤"
  if pgrep -f "dotnet Core.dll" >/dev/null; then
    PID=$(pgrep -f "dotnet Core.dll")
    echo "│ Status:  ✅ Running (PID: $PID)          │"
    echo "│ Port:    9118                           │"
    echo "│ Web UI:  http://127.0.0.1:9118         │"
    echo "│                                        │"
    # Check plugin
    if [ -f /opt/lampac/plugins/override/vn-sources.js ]; then
      echo "│ Plugin:  ✅ vn-sources.js deployed      │"
    else
      echo "│ Plugin:  ❌ Not deployed                │"
    fi
    # Check init.conf
    if grep -q "LampaWeb" /opt/lampac/init.conf 2>/dev/null; then
      echo "│ Config:  ✅ LampaWeb configured          │"
    else
      echo "│ Config:  ⚠️  LampaWeb not configured      │"
    fi
  else
    echo "│ Status:  ❌ Not running                 │"
    echo "│ Start:   lampac                         │"
  fi
  echo "└─────────────────────────────────────────┘"
  echo ""

  # Port conflicts
  echo "Port Check:"
  for port in 8788 8789 9118; do
    if ss -tlnp 2>/dev/null | grep -q ":$port " || netstat -tlnp 2>/dev/null | grep -q ":$port "; then
      echo "  Port $port: ✅ In use"
    else
      echo "  Port $port: ❌ Free"
    fi
  done
'
