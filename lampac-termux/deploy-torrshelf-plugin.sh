#!/bin/bash
# Deploy TorrShelf Streams Plugin to Lampac + patch TorrShelf server
# Usage: sh deploy-torrshelf-plugin.sh
#
# This script:
# 1. Patches TorrShelf server.mjs to add /api/streams endpoint
# 2. Copies Lampa plugin to Lampac plugins directory
# 3. Shows instructions to activate

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  TorrShelf Streams Plugin — Deploy"
echo "  ================================="
echo ""

# Check files exist
for f in "plugins/torrshelf-streams.js" "torrshelf-api-patch.mjs"; do
  if [ ! -f "$SCRIPT_DIR/$f" ]; then
    echo "ERROR: $f not found in $SCRIPT_DIR"
    exit 1
  fi
done

echo "[1/3] Patching TorrShelf server.mjs..."
echo ""
echo "  You need to manually add the /api/streams endpoint to your"
echo "  TorrShelf server.mjs. The patch code is in:"
echo "    $SCRIPT_DIR/torrshelf-api-patch.mjs"
echo ""
echo "  Find the request handler in server.mjs (the part that checks"
echo "  req.url) and paste the code from the patch file."
echo ""

# Deploy plugin to Lampac
echo "[2/3] Deploying Lampa plugin to Lampac..."
proot-distro login ubuntu -- bash -c "
PLUGIN_DIR='/opt/lampac/plugins/override'
mkdir -p \"\$PLUGIN_DIR\"

# Copy plugin
cp '$SCRIPT_DIR/plugins/torrshelf-streams.js' \"\$PLUGIN_DIR/torrshelf-streams.js\" 2>/dev/null || {
  cat '$SCRIPT_DIR/plugins/torrshelf-streams.js' > \"\$PLUGIN_DIR/torrshelf-streams.js\"
}

echo 'Plugin deployed to: \$PLUGIN_DIR/torrshelf-streams.js'
ls -la \"\$PLUGIN_DIR/torrshelf-streams.js\"
"

echo ""
echo "[3/3] Done!"
echo ""
echo "=== How to activate ==="
echo ""
echo "1. Patch TorrShelf server.mjs (see torrshelf-api-patch.mjs)"
echo ""
echo "2. Add to Lampac init.conf:"
echo '   "LampaWeb": {'
echo '     "customPlugins": ['
echo '       {"url": "{localhost}/torrshelf-streams.js", "status": 1}'
echo '     ]'
echo '   }'
echo ""
echo "3. Restart both services:"
echo "   lampac-stop && lampac"
echo "   cd ~/torr-shelf && npm start"
echo ""
echo "4. In Lampa, open any movie detail page"
echo "   -> Click 'TorrShelf' button"
echo "   -> Select provider (UHDMovies, 4KHDHub, etc.)"
echo "   -> Pick stream -> Play!"
echo ""
echo "=== TorrShelf Settings ==="
echo ""
echo "In Lampa Settings -> TorrShelf:"
echo "  API URL: http://127.0.0.1:8787"
echo ""
