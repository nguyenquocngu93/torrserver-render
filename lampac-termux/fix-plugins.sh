#!/bin/bash
# ============================================================
#  fix-plugins.sh — Fix: deploy plugins + config + bypass APK
# ============================================================
#  Chạy trên Termux khi plugin không hoạt động:
#    sh lampac-termux/fix-plugins.sh
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "============================================"
echo "  Fix Plugins — Deploy + Config + APK Bypass"
echo "============================================"
echo ""

# ─── Step 1: Deploy ALL plugins ──────────────────────────────
echo "[1/4] Deploying plugins to Lampac..."
proot-distro login ubuntu -- bash -c "
  PLUGIN_DIR='/opt/lampac/plugins/override'
  mkdir -p \"\$PLUGIN_DIR\"

  echo 'Deploying to: \$PLUGIN_DIR'
  echo ''

  # Plugin 1: no-apk-force.js (MUST BE FIRST!)
  if [ -f '$SCRIPT_DIR/plugins/no-apk-force.js' ]; then
    cp '$SCRIPT_DIR/plugins/no-apk-force.js' \"\$PLUGIN_DIR/no-apk-force.js\"
    echo '  ✅ no-apk-force.js'
  else
    echo '  ❌ no-apk-force.js NOT FOUND'
  fi

  # Plugin 2: vn-sources.js (Vietnamese sources)
  if [ -f '$SCRIPT_DIR/plugins/vn-sources.js' ]; then
    cp '$SCRIPT_DIR/plugins/vn-sources.js' \"\$PLUGIN_DIR/vn-sources.js\"
    echo '  ✅ vn-sources.js'
  else
    echo '  ❌ vn-sources.js NOT FOUND'
  fi

  # Plugin 3: torrshelf-streams.js
  if [ -f '$SCRIPT_DIR/plugins/torrshelf-streams.js' ]; then
    cp '$SCRIPT_DIR/plugins/torrshelf-streams.js' \"\$PLUGIN_DIR/torrshelf-streams.js\"
    echo '  ✅ torrshelf-streams.js'
  else
    echo '  ❌ torrshelf-streams.js NOT FOUND'
  fi

  echo ''
  echo 'Files in override:'
  ls -la \"\$PLUGIN_DIR/\"
" 2>/dev/null

# ─── Step 2: Fix init.conf ───────────────────────────────────
echo ""
echo "[2/4] Fixing init.conf..."
proot-distro login ubuntu -- bash -c '
  CONF="/opt/lampac/init.conf"
  
  if [ ! -f "$CONF" ]; then
    echo "Creating init.conf from scratch..."
    cat > "$CONF" << '\''CONFEOF'\''
{
  "listen": {
    "version": true,
    "ip": "0.0.0.0",
    "port": 9118,
    "scheme": "http",
    "localhost": "127.0.0.1"
  },
  "BaseModule": {
    "SkipModules": ["TorrServer"]
  },
  "LampaWeb": {
    "customPlugins": [
      {"url": "{localhost}/no-apk-force.js", "status": 1},
      {"url": "{localhost}/vn-sources.js", "status": 1},
      {"url": "{localhost}/torrshelf-streams.js", "status": 1}
    ]
  }
}
CONFEOF
    echo "✅ init.conf created"
  else
    # Check and fix existing config
    python3 << '\''PYEOF'\''
import json, sys

with open("/opt/lampac/init.conf", "r") as f:
    data = json.load(f)

changed = False

# Ensure LampaWeb section exists
if "LampaWeb" not in data:
    data["LampaWeb"] = {"customPlugins": []}
    changed = True
    print("Added LampaWeb section")

# Ensure customPlugins array exists
if "customPlugins" not in data["LampaWeb"]:
    data["LampaWeb"]["customPlugins"] = []
    changed = True
    print("Added customPlugins array")

# Ensure plugins are listed (order matters!)
plugins_needed = [
    {"url": "{localhost}/no-apk-force.js", "status": 1},
    {"url": "{localhost}/vn-sources.js", "status": 1},
    {"url": "{localhost}/torrshelf-streams.js", "status": 1}
]

current_urls = [p.get("url", "") for p in data["LampaWeb"]["customPlugins"]]

for plugin in plugins_needed:
    if plugin["url"] not in current_urls:
        data["LampaWeb"]["customPlugins"].insert(0, plugin)
        changed = True
        print(f"Added: {plugin['url']}")

# Ensure SkipModules disables TorrServer
if "BaseModule" not in data:
    data["BaseModule"] = {}
if "SkipModules" not in data["BaseModule"]:
    data["BaseModule"]["SkipModules"] = ["TorrServer"]
    changed = True
    print("Added SkipModules for TorrServer")

if changed:
    with open("/opt/lampac/init.conf", "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print("✅ init.conf updated")
else:
    print("✅ init.conf already correct")

# Show current config
print("")
print("Current LampaWeb config:")
print(json.dumps(data.get("LampaWeb", {}), indent=2))
PYEOF
  fi
' 2>/dev/null

# ─── Step 3: Remove GStreamer (if causing issues) ────────────
echo ""
echo "[3/4] Cleaning up GStreamer (if present)..."
proot-distro login ubuntu -- bash -c '
  if [ -d /opt/lampac/module/GStreamer ]; then
    rm -rf /opt/lampac/module/GStreamer
    find /opt/lampac/runtimes -iname "*gstreamer*" -delete 2>/dev/null
    find /opt/lampac/runtimes -iname "*gst*" -delete 2>/dev/null
    echo "  ✅ GStreamer removed"
  else
    echo "  ✅ GStreamer not present"
  fi
' 2>/dev/null

# ─── Step 4: Kill and restart Lampac ─────────────────────────
echo ""
echo "[4/4] Restarting Lampac..."
proot-distro login ubuntu -- bash -c '
  # Kill existing
  pkill -f "dotnet Core.dll" 2>/dev/null || true
  sleep 2

  # Verify plugins
  echo ""
  echo "=== Plugin Verification ==="
  ls -la /opt/lampac/plugins/override/

  echo ""
  echo "=== init.conf LampaWeb section ==="
  python3 -c "
import json
with open(\"/opt/lampac/init.conf\") as f:
    data = json.load(f)
print(json.dumps(data.get(\"LampaWeb\", {}), indent=2))
" 2>/dev/null || echo "Could not read init.conf"

  echo ""
  echo "=== Starting Lampac ==="
  cd /opt/lampac
  export DOTNET_gcServer=0
  export DOTNET_gcHeapHardLimit=512
  export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
  export LAMPA_MODULE_GSTREAMER=0
  echo "Starting..."
  dotnet Core.dll --urls http://0.0.0.0:9118 &
  
  # Wait for startup
  sleep 5
  if pgrep -f "dotnet Core.dll" >/dev/null; then
    echo ""
    echo "✅ Lampac started!"
    echo "   http://127.0.0.1:9118"
  else
    echo ""
    echo "❌ Lampac failed to start"
    echo "Check: tail -20 /opt/lampac/logs/*.log"
  fi
' 2>/dev/null || true

echo ""
echo "============================================"
echo "  Done! Open browser: http://127.0.0.1:9118"
echo "============================================"
echo ""
echo "If APK modal still appears:"
echo "  1. Clear browser cache (Ctrl+Shift+Delete)"
echo "  2. Open in Incognito/Private mode"
echo "  3. Check Console (F12) for [NoAPKForce] log"
echo ""
