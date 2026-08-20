#!/bin/bash
# ============================================================
#  fix-plugins.sh — Deploy plugins + fix config + restart
# ============================================================
#  Chạy trên Termux:
#    sh lampac-termux/fix-plugins.sh
# ============================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "========================================"
echo "  Fix Plugins — Deploy + Config"
echo "========================================"
echo ""

# ─── Step 1: Create plugin dir ──────────────────────────────
echo "[1/3] Deploying plugins..."

proot-distro login ubuntu -- bash -c '
  mkdir -p /opt/lampac/plugins/override

  # Remove old files
  rm -f /opt/lampac/plugins/override/*.js

  echo "Plugin dir ready: /opt/lampac/plugins/override/"
'

# ─── Step 2: Copy plugins (using cat to avoid path issues) ──
echo "[2/3] Copying plugin files..."

for plugin in no-apk-force.js vn-sources.js torrshelf-streams.js; do
  if [ -f "$SCRIPT_DIR/plugins/$plugin" ]; then
    proot-distro login ubuntu -- bash -c "cat > /opt/lampac/plugins/override/$plugin" < "$SCRIPT_DIR/plugins/$plugin"
    echo "  ✅ $plugin"
  else
    echo "  ❌ $plugin NOT FOUND at $SCRIPT_DIR/plugins/$plugin"
  fi
done

# ─── Step 3: Fix init.conf ──────────────────────────────────
echo "[3/3] Fixing init.conf..."

proot-distro login ubuntu -- bash -c '
  CONF="/opt/lampac/init.conf"
  
  # Create init.conf if not exists
  if [ ! -f "$CONF" ]; then
    echo "{\"listen\":{\"version\":true,\"ip\":\"0.0.0.0\",\"port\":9118,\"scheme\":\"http\",\"localhost\":\"127.0.0.1\"},\"BaseModule\":{\"SkipModules\":[\"TorrServer\"]},\"LampaWeb\":{\"customPlugins\":[{\"url\":\"{localhost}/no-apk-force.js\",\"status\":1},{\"url\":\"{localhost}/vn-sources.js\",\"status\":1},{\"url\":\"{localhost}/torrshelf-streams.js\",\"status\":1}]}}" > "$CONF"
    echo "✅ Created init.conf"
  else
    # Fix with python
    python3 -c "
import json
with open(\"$CONF\",\"r\") as f: data=json.load(f)
if \"LampaWeb\" not in data: data[\"LampaWeb\"]={}
if \"customPlugins\" not in data[\"LampaWeb\"]: data[\"LampaWeb\"][\"customPlugins\"]=[]
plugins=[\"{localhost}/no-apk-force.js\",\"{localhost}/vn-sources.js\",\"{localhost}/torrshelf-streams.js\"]
cur=[p.get(\"url\",\"\") for p in data[\"LampaWeb\"][\"customPlugins\"]]
for p in plugins:
  if p not in cur: data[\"LampaWeb\"][\"customPlugins\"].insert(0,{\"url\":p,\"status\":1})
if \"BaseModule\" not in data: data[\"BaseModule\"]={}
if \"SkipModules\" not in data[\"BaseModule\"]: data[\"BaseModule\"][\"SkipModules\"]=[\"TorrServer\"]
with open(\"$CONF\",\"w\") as f: json.dump(data,f,indent=2,ensure_ascii=False)
print(\"✅ init.conf fixed\")
"
  fi

  # Show result
  echo ""
  echo "=== Plugins in override ==="
  ls -la /opt/lampac/plugins/override/
  echo ""
  echo "=== LampaWeb config ==="
  python3 -c "
import json
with open(\"$CONF\") as f: data=json.load(f)
print(json.dumps(data.get(\"LampaWeb\",{}),indent=2))
"
'

echo ""
echo "========================================"
echo "  DONE!"
echo "========================================"
echo ""
echo "Next:"
echo "  1. pkill -f 'dotnet Core.dll'"
echo "  2. lampac"
echo "  3. Open Incognito: http://127.0.0.1:9118"
echo ""
echo "If APK modal still shows:"
echo "  - F12 → Console → check [NoAPK] log"
echo "  - Clear browser cache"
echo ""
