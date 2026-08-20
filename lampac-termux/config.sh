#!/bin/bash
# config.sh — Edit Lampac + TorrShelf configuration
# Usage: sh lampac-termux/config.sh [lampac|torrshelf|init]

set -e

CONFIG_TYPE="${1:-init}"

echo "=== Configuration Editor ==="
echo ""

case "$CONFIG_TYPE" in
  lampac)
    echo "Opening Lampac init.conf..."
    proot-distro login ubuntu -- bash -c 'nano /opt/lampac/init.conf'
    ;;
    
  torrshelf)
    echo "Opening TorrShelf config..."
    proot-distro login ubuntu -- bash -c '
      cat > /opt/torrshelf/config.json << "TSCONF"
{
  "sources": {
    "kkphim": {
      "enabled": true,
      "base": "https://khophim.co"
    },
    "ophim": {
      "enabled": true,
      "base": "https://ophim.me"
    },
    "uhdmovie": {
      "enabled": true,
      "base": "https://uhdmovie.dev"
    },
    "khd4k": {
      "enabled": true,
      "base": "https://4khdhub.com"
    }
  },
  "api_port": 8788,
  "api_host": "0.0.0.0"
}
TSCONF
      nano /opt/torrshelf/config.json
    '
    ;;
    
  init|*)
    echo "=== Quick Config ==="
    echo ""
    echo "1. Lampac Web UI:     http://127.0.0.1:9118"
    echo "2. TorrShelf API:     http://127.0.0.1:8788"
    echo ""
    echo "To edit Lampac config:"
    echo "  sh lampac-termux/config.sh lampac"
    echo ""
    echo "To edit TorrShelf config:"
    echo "  sh lampac-termux/config.sh torrshelf"
    echo ""
    echo "Current init.conf:"
    echo "---"
    proot-distro login ubuntu -- bash -c 'cat /opt/lampac/init.conf 2>/dev/null || echo "File not found"'
    echo "---"
    ;;
esac
