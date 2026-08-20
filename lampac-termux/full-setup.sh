#!/bin/bash
# ============================================================
#  full-setup.sh — Complete setup: Lampac + TorrShelf + Plugins
# ============================================================
#  Usage:
#    sh lampac-termux/full-setup.sh           # Full setup
#    sh lampac-termux/full-setup.sh --quick   # Just deploy plugins
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TORRSHELF_DIR="${TORRSHELF_DIR:-$HOME/torr-shelf}"

R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' C='\033[0;36m' NC='\033[0m'

echo ""
echo -e "${C}============================================${NC}"
echo -e "${C}  Lampac + TorrShelf Full Setup${NC}"
echo -e "${C}============================================${NC}"
echo ""

# ─── Check proot-distro ──────────────────────────────────────
echo -e "${Y}[1/7]${NC} Checking proot-distro..."
if ! command -v proot-distro &>/dev/null; then
  echo "  Installing proot-distro..."
  pkg install -y proot-distro 2>/dev/null || apt install -y proot-distro
fi
echo -e "  ${G}✅${NC} proot-distro ready"

# ─── Check Ubuntu proot ──────────────────────────────────────
echo -e "${Y}[2/7]${NC} Checking Ubuntu proot..."
if ! proot-distro list 2>/dev/null | grep -q "ubuntu"; then
  echo "  Installing Ubuntu proot..."
  proot-distro install ubuntu
fi
echo -e "  ${G}✅${NC} Ubuntu proot ready"

# ─── Install dependencies ────────────────────────────────────
echo -e "${Y}[3/7]${NC} Installing dependencies in proot..."
proot-distro login ubuntu -- bash -c '
  apt-get update -qq 2>/dev/null
  apt-get install -y -qq libicu78 curl wget unzip 2>/dev/null || \
  apt-get install -y libicu-dev curl wget unzip 2>/dev/null || true
' 2>/dev/null
echo -e "  ${G}✅${NC} Dependencies ready"

# ─── Check Lampac installed ──────────────────────────────────
echo -e "${Y}[4/7]${NC} Checking Lampac..."
LAMPAC_OK=$(proot-distro login ubuntu -- bash -c '
  if [ -f /opt/lampac/Core.dll ]; then
    echo "yes"
  else
    echo "no"
  fi
' 2>/dev/null)

if [ "$LAMPAC_OK" = "yes" ]; then
  echo -e "  ${G}✅${NC} Lampac already installed"
else
  echo "  Installing Lampac..."
  sh "$SCRIPT_DIR/setup.sh"
fi

# ─── Deploy ALL plugins ─────────────────────────────────────
echo -e "${Y}[5/7]${NC} Deploying plugins..."
proot-distro login ubuntu -- bash -c "
  PLUGIN_DIR='/opt/lampac/plugins/override'
  mkdir -p \"\$PLUGIN_DIR\"

  # Plugin 1: vn-sources.js (Vietnamese sources)
  if [ -f '$SCRIPT_DIR/plugins/vn-sources.js' ]; then
    cp '$SCRIPT_DIR/plugins/vn-sources.js' \"\$PLUGIN_DIR/vn-sources.js\"
    echo '✅ vn-sources.js deployed'
  else
    echo '❌ vn-sources.js not found'
  fi

  # Plugin 2: torrshelf-streams.js (TorrShelf integration)
  if [ -f '$SCRIPT_DIR/plugins/torrshelf-streams.js' ]; then
    cp '$SCRIPT_DIR/plugins/torrshelf-streams.js' \"\$PLUGIN_DIR/torrshelf-streams.js\"
    echo '✅ torrshelf-streams.js deployed'
  else
    echo '❌ torrshelf-streams.js not found'
  fi

  # Plugin 3: no-apk-force.js (Bypass APK requirement)
  if [ -f '$SCRIPT_DIR/plugins/no-apk-force.js' ]; then
    cp '$SCRIPT_DIR/plugins/no-apk-force.js' \"\$PLUGIN_DIR/no-apk-force.js\"
    echo '✅ no-apk-force.js deployed'
  else
    echo '❌ no-apk-force.js not found'
  fi

  # Verify
  echo ''
  echo 'Plugins in override directory:'
  ls -la \"\$PLUGIN_DIR/\"
" 2>/dev/null

# ─── Configure init.conf ─────────────────────────────────────
echo -e "${Y}[6/7]${NC} Configuring init.conf..."
proot-distro login ubuntu -- bash -c '
  CONF="/opt/lampac/init.conf"
  
  if [ ! -f "$CONF" ]; then
    # Create from template
    cp /dev/null "$CONF"
  fi

  # Check if LampaWeb section exists
  if grep -q "LampaWeb" "$CONF"; then
    echo "  LampaWeb section already exists"
    
    # Check if plugins are listed
    if grep -q "vn-sources.js" "$CONF"; then
      echo "  ✅ vn-sources.js configured"
    else
      echo "  ⚠️  vn-sources.js not in config"
    fi
    
    if grep -q "torrshelf-streams.js" "$CONF"; then
      echo "  ✅ torrshelf-streams.js configured"
    else
      echo "  ⚠️  torrshelf-streams.js not in config"
    fi
    
    if grep -q "no-apk-force.js" "$CONF"; then
      echo "  ✅ no-apk-force.js configured"
    else
      echo "  ⚠️  no-apk-force.js not in config"
    fi
  else
    echo "  ⚠️  LampaWeb section not found in init.conf"
    echo "  Adding LampaWeb section..."
    
    # Add LampaWeb section before closing brace
    python3 -c "
import json, sys
try:
    with open(\"$CONF\", \"r\") as f:
        data = json.load(f)
except:
    data = {}

data[\"LampaWeb\"] = {
    \"customPlugins\": [
        {\"url\": \"{localhost}/no-apk-force.js\", \"status\": 1},
        {\"url\": \"{localhost}/vn-sources.js\", \"status\": 1},
        {\"url\": \"{localhost}/torrshelf-streams.js\", \"status\": 1}
    ]
}

# Also ensure SkipModules disables torrent modules
if \"BaseModule\" not in data:
    data[\"BaseModule\"] = {}
if \"SkipModules\" not in data[\"BaseModule\"]:
    data[\"BaseModule\"][\"SkipModules\"] = [\"TorrServer\"]

with open(\"$CONF\", \"w\") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(\"✅ init.conf updated with LampaWeb section\")
" 2>/dev/null || echo "  ⚠️  Could not update init.conf automatically"
  fi
' 2>/dev/null

# ─── Patch TorrShelf (if exists) ─────────────────────────────
echo -e "${Y}[7/7]${NC} Patching TorrShelf..."
if [ -d "$TORRSHELF_DIR" ] && [ -f "$TORRSHELF_DIR/server.mjs" ]; then
  echo "  TorrShelf found at $TORRSHELF_DIR"
  
  # Check if already patched
  if grep -q "/api/streams" "$TORRSHELF_DIR/server.mjs" 2>/dev/null; then
    echo "  ✅ TorrShelf already patched"
  else
    echo "  Patching TorrShelf server.mjs..."
    
    # Backup original
    cp "$TORRSHELF_DIR/server.mjs" "$TORRSHELF_DIR/server.mjs.bak" 2>/dev/null || true
    
    # Apply patch
    cp "$SCRIPT_DIR/server.mjs.patched" "$TORRSHELF_DIR/server.mjs" 2>/dev/null || {
      echo "  ⚠️  Could not apply patch automatically"
      echo "  Please manually apply: $SCRIPT_DIR/torrshelf-api-patch.mjs"
    }
    
    if grep -q "/api/streams" "$TORRSHELF_DIR/server.mjs" 2>/dev/null; then
      echo "  ✅ TorrShelf patched successfully"
    else
      echo "  ❌ Patch failed"
    fi
  fi
else
  echo "  ⚠️  TorrShelf not found at $TORRSHELF_DIR"
  echo "  To use TorrShelf, clone it first:"
  echo "    git clone https://github.com/your-repo/torr-shelf.git $TORRSHELF_DIR"
fi

# ─── Create management commands ──────────────────────────────
echo ""
echo "Creating management commands..."

# lampac
cat > ~/lampac 2>/dev/null << 'LAMPEOF' || true
#!/bin/bash
proot-distro login ubuntu -- bash -c 'cd /opt/lampac && export DOTNET_gcServer=0 && export DOTNET_gcHeapHardLimit=512 && export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 && export LAMPA_MODULE_GSTREAMER=0 && dotnet Core.dll --urls http://0.0.0.0:9118'
LAMPEOF
chmod +x ~/lampac 2>/dev/null || true

# lampac-stop
cat > ~/lampac-stop 2>/dev/null << 'STOPEOF' || true
#!/bin/bash
proot-distro login ubuntu -- bash -c 'pkill -f "dotnet Core.dll" 2>/dev/null && echo "Lampac stopped" || echo "Lampac not running"'
STOPEOF
chmod +x ~/lampac-stop 2>/dev/null || true

# lampac-status
cat > ~/lampac-status 2>/dev/null << 'STATUSEOF' || true
#!/bin/bash
proot-distro login ubuntu -- bash -c '
  echo "=== Media Stack Status ==="
  echo ""
  if pgrep -f "dotnet Core.dll" >/dev/null; then
    PID=$(pgrep -f "dotnet Core.dll")
    echo "Lampac:    ✅ Running (PID: $PID) - http://127.0.0.1:9118"
  else
    echo "Lampac:    ❌ Not running"
  fi
  if pgrep -f "node server.mjs" >/dev/null; then
    PID=$(pgrep -f "node server.mjs")
    echo "TorrShelf: ✅ Running (PID: $PID) - http://127.0.0.1:8787"
  else
    echo "TorrShelf: ❌ Not running"
  fi
  echo ""
  echo "Plugins:"
  ls -la /opt/lampac/plugins/override/ 2>/dev/null || echo "  No plugins found"
'
STATUSEOF
chmod +x ~/lampac-status 2>/dev/null || true

# Update PATH
if ! grep -q 'export PATH="$HOME:$PATH"' ~/.bashrc 2>/dev/null; then
  echo 'export PATH="$HOME:$PATH"' >> ~/.bashrc 2>/dev/null || true
fi

echo -e "${G}✅${NC} Management commands created"

# ─── Summary ─────────────────────────────────────────────────
echo ""
echo -e "${G}============================================${NC}"
echo -e "${G}  Setup Complete!${NC}"
echo -e "${G}============================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Start TorrShelf (if using):"
echo "     cd ~/torr-shelf && npm start"
echo ""
echo "  2. Start Lampac:"
echo "     lampac"
echo ""
echo "  3. Open browser:"
echo "     http://127.0.0.1:9118"
echo ""
echo "  4. In Lampa, go to Settings → Source"
echo "     - Select 'Phim Việt' or 'Tất cả nguồn Việt'"
echo "     - Or click 'TorrShelf' button on movie detail page"
echo ""
echo "Management commands:"
echo "  lampac          — Start Lampac"
echo "  lampac-stop     — Stop Lampac"
echo "  lampac-status   — Check status"
echo ""
echo "Stop all:"
echo "  pkill -f 'dotnet Core.dll'"
echo "  pkill -f 'node server.mjs'"
echo ""
