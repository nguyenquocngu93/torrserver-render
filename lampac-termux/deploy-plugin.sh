#!/bin/bash
# Deploy Vietnamese Sources plugin to Lampac
# Usage: sh deploy-plugin.sh
#
# This copies vn-sources.js to Lampac's plugins directory
# and configures LampaWeb to auto-load it.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_SRC="$SCRIPT_DIR/plugins/vn-sources.js"
LAMPAC_DIR="/opt/lampac"
PLUGIN_DIR="$LAMPAC_DIR/plugins/override"

echo ""
echo "  Deploying Vietnamese Sources plugin..."
echo ""

# Check plugin file exists
if [ ! -f "$PLUGIN_SRC" ]; then
  echo "ERROR: $PLUGIN_SRC not found"
  echo "Make sure vn-sources.js is in $(dirname "$0")/plugins/"
  exit 1
fi

# Deploy inside proot
proot-distro login ubuntu -- bash -c "
set -e

PLUGIN_DIR=\"$PLUGIN_DIR\"
PLUGIN_SRC_HOST=\"$PLUGIN_SRC\"

# The proot path mapping: host /home -> /home in proot
# But lampac-termux is in the host repo, so we need to copy via stdin

echo '[1/3] Creating plugin directory...'
mkdir -p \"\$PLUGIN_DIR\"

echo '[2/3] Copying vn-sources.js...'
# Read from host path (proot maps /home)
cp \"\$PLUGIN_SRC_HOST\" \"\$PLUGIN_DIR/vn-sources.js\" 2>/dev/null || {
  echo 'Direct copy failed, trying via cat...'
  cat \"\$PLUGIN_SRC_HOST\" > \"\$PLUGIN_DIR/vn-sources.js\" 2>/dev/null || {
    echo 'ERROR: Cannot copy plugin file'
    echo 'Manual: cp vn-sources.js to /opt/lampac/plugins/override/vn-sources.js inside proot'
    exit 1
  }
}

echo '[3/3] Plugin deployed to: \$PLUGIN_DIR/vn-sources.js'
ls -la \"\$PLUGIN_DIR/vn-sources.js\"

echo ''
echo 'To load the plugin, add to init.conf:'
echo '  \"LampaWeb\": { \"customPlugins\": [{\"url\": \"{localhost}/vn-sources.js\", \"status\": 1}] }'
echo ''
echo 'Or restart Lampac and it will auto-reload.'
"

echo ""
echo "Done! To activate:"
echo ""
echo "  Option 1 — Edit init.conf:"
echo "    lampac-config"
echo "    Add this inside the JSON:"
echo '    "LampaWeb": {'
echo '      "customPlugins": ['
echo '        {"url": "{localhost}/vn-sources.js", "status": 1}'
echo '      ]'
echo '    }'
echo ""
echo "  Option 2 — Use nano inside proot:"
echo "    proot-distro login ubuntu"
echo "    nano /opt/lampac/init.conf"
echo ""
echo "  Then restart:"
echo "    lampac-stop && lampac"
echo ""
echo "  Open Lampa: http://127.0.0.1:9118"
echo "  Select source: Phim Viet"
echo ""
