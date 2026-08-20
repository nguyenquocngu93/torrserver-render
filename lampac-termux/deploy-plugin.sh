#!/bin/bash
# deploy-plugin.sh — Deploy Vietnamese sources plugin into Lampac proot
# Usage: sh lampac-termux/deploy-plugin.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_SRC="$SCRIPT_DIR/plugins/vn-sources.js"

echo "=== Deploy Vietnamese Sources Plugin ==="

# Check plugin file exists
if [ ! -f "$PLUGIN_SRC" ]; then
  echo "ERROR: Plugin file not found: $PLUGIN_SRC"
  exit 1
fi

echo "[1/3] Copy plugin to proot..."
proot-distro login ubuntu -- bash -c "
  mkdir -p /opt/lampac/plugins/override
  cp '$PLUGIN_SRC' /opt/lampac/plugins/override/vn-sources.js
  echo 'Plugin copied to /opt/lampac/plugins/override/vn-sources.js'
"

echo "[2/3] Check init.conf for LampaWeb config..."
proot-distro login ubuntu -- bash -c '
  CONF="/opt/lampac/init.conf"
  if [ ! -f "$CONF" ]; then
    echo "ERROR: init.conf not found"
    exit 1
  fi

  # Check if LampaWeb section exists
  if grep -q "\"LampaWeb\"" "$CONF"; then
    echo "LampaWeb section already exists in init.conf"
  else
    echo "WARNING: LampaWeb section not found in init.conf"
    echo "Please add manually or run lampac-config to add:"
    echo ""
    echo "  \"LampaWeb\": {"
    echo "    \"customPlugins\": ["
    echo "      { \"url\": \"{localhost}/vn-sources.js\", \"status\": 1 }"
    echo "    ]"
    echo "  }"
  fi
'

echo "[3/3] Verify deployment..."
proot-distro login ubuntu -- bash -c '
  if [ -f /opt/lampac/plugins/override/vn-sources.js ]; then
    SIZE=$(wc -c < /opt/lampac/plugins/override/vn-sources.js)
    echo "✅ Plugin deployed successfully ($SIZE bytes)"
    echo "   Location: /opt/lampac/plugins/override/vn-sources.js"
  else
    echo "❌ Plugin deployment failed"
    exit 1
  fi
'

echo ""
echo "=== Done ==="
echo "Restart Lampac to apply changes:"
echo "  lampac-stop && lampac"
