#!/bin/bash
# setup.sh — Install Lampac NextGen in proot Ubuntu on Termux
# Usage: sh lampac-termux/setup.sh

set -e

echo "=== Lampac NextGen Setup ==="
echo "Cài đặt Lampac trong proot Ubuntu trên Termux"
echo ""

# ─── Step 1: Check proot-distro ──────────────────────────────
echo "[1/5] Checking proot-distro..."
if ! command -v proot-distro &>/dev/null; then
  echo "  Installing proot-distro..."
  pkg install -y proot-distro 2>/dev/null || apt install -y proot-distro
fi
echo "  ✅ proot-distro installed"

# ─── Step 2: Check Ubuntu proot ──────────────────────────────
echo "[2/5] Checking Ubuntu proot..."
if ! proot-distro list 2>/dev/null | grep -q "ubuntu"; then
  echo "  Installing Ubuntu proot..."
  proot-distro install ubuntu
fi
echo "  ✅ Ubuntu proot available"

# ─── Step 3: Install dependencies in proot ──────────────────
echo "[3/5] Installing dependencies in proot..."
proot-distro login ubuntu -- bash -c '
  apt-get update -qq
  apt-get install -y -qq libicu78 curl wget unzip 2>/dev/null || \
  apt-get install -y libicu-dev curl wget unzip 2>/dev/null || true
  echo "Dependencies installed"
'
echo "  ✅ Dependencies ready"

# ─── Step 4: Download Lampac ─────────────────────────────────
echo "[4/5] Downloading Lampac NextGen..."
proot-distro login ubuntu -- bash -c '
  LAMPAC_DIR="/opt/lampac"

  if [ -d "$LAMPAC_DIR" ]; then
    echo "Lampac already exists at $LAMPAC_DIR — skipping download"
    echo "To reinstall: rm -rf $LAMPAC_DIR && re-run setup.sh"
  else
    echo "Creating $LAMPAC_DIR..."
    mkdir -p "$LAMPAC_DIR"
    cd "$LAMPAC_DIR"

    # Download latest Lampac release
    echo "Downloading Lampac NextGen..."
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
      DOWNLOAD_URL="https://github.com/yourok12345/Lampac/releases/latest/download/Lampac.linux-arm64.zip"
    else
      DOWNLOAD_URL="https://github.com/yourok12345/Lampac/releases/latest/download/Lampac.linux-x64.zip"
    fi

    curl -sL -o lampac.zip "$DOWNLOAD_URL" 2>/dev/null || \
    wget -q -O lampac.zip "$DOWNLOAD_URL" 2>/dev/null || {
      echo "ERROR: Failed to download Lampac"
      echo "Please download manually from: https://github.com/yourok12345/Lampac/releases"
      echo "Place the zip in /opt/lampac/ and re-run setup.sh"
      exit 1
    }

    unzip -o lampac.zip -d .
    rm -f lampac.zip
    chmod +x Core.dll 2>/dev/null || true
    echo "Lampac downloaded and extracted"
  fi
'
echo "  ✅ Lampac downloaded"

# ─── Step 5: Create start/stop scripts ──────────────────────
echo "[5/5] Creating management scripts..."
proot-distro login ubuntu -- bash -c '
  # start.sh
  cat > /opt/lampac/start.sh << "STARTSH"
#!/bin/bash
cd /opt/lampac
export DOTNET_gcServer=0
export DOTNET_gcHeapHardLimit=512
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# Disable GStreamer module (causes crashes on ARM)
export LAMPA_MODULE_GSTREAMER=0

echo "Starting Lampac NextGen..."
echo "Web UI: http://127.0.0.1:9118"
echo "Press Ctrl+C to stop"
echo ""

dotnet Core.dll --urls http://0.0.0.0:9118
STARTSH
  chmod +x /opt/lampac/start.sh

  # Default init.conf if not exists
  if [ ! -f /opt/lampac/init.conf ]; then
    cat > /opt/lampac/init.conf << "INITCONF"
{
  "listen": {
    "ip": "0.0.0.0",
    "port": 9118
  },
  "BaseModule": {
    "api": "https://rh.api.lampa.mx"
  },
  "LampaWeb": {
    "customPlugins": [
      { "url": "{localhost}/vn-sources.js", "status": 1 }
    ]
  }
}
INITCONF
    echo "Default init.conf created"
  fi
'
echo "  ✅ Scripts created"

# ─── Create Termux wrapper commands ──────────────────────────
echo ""
echo "Creating Termux wrapper commands..."

# lampac command
cat > ~/lampac 2>/dev/null << 'LAMPEOF' || true
#!/bin/bash
proot-distro login ubuntu -- bash -c 'cd /opt/lampac && sh start.sh'
LAMPEOF
chmod +x ~/lampac 2>/dev/null || true

# lampac-stop command
cat > ~/lampac-stop 2>/dev/null << 'STOPEOF' || true
#!/bin/bash
proot-distro login ubuntu -- bash -c '
  pkill -f "dotnet Core.dll" 2>/dev/null && echo "Lampac stopped" || echo "Lampac not running"
'
STOPEOF
chmod +x ~/lampac-stop 2>/dev/null || true

# lampac-status command
cat > ~/lampac-status 2>/dev/null << 'STATUSEOF' || true
#!/bin/bash
proot-distro login ubuntu -- bash -c '
  if pgrep -f "dotnet Core.dll" >/dev/null; then
    PID=$(pgrep -f "dotnet Core.dll")
    echo "✅ Lampac is running (PID: $PID)"
    echo "   Web UI: http://127.0.0.1:9118"
  else
    echo "❌ Lampac is not running"
  fi
'
STATUSEOF
chmod +x ~/lampac-status 2>/dev/null || true

# lampac-config command
cat > ~/lampac-config 2>/dev/null << 'CONFIGEOF' || true
#!/bin/bash
proot-distro login ubuntu -- bash -c 'nano /opt/lampac/init.conf'
CONFIGEOF
chmod +x ~/lampac-config 2>/dev/null || true

# Add to PATH if not already
if ! grep -q 'export PATH="$HOME:$PATH"' ~/.bashrc 2>/dev/null; then
  echo 'export PATH="$HOME:$PATH"' >> ~/.bashrc 2>/dev/null || true
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Commands available:"
echo "  lampac          — Start Lampac NextGen"
echo "  lampac-stop     — Stop Lampac"
echo "  lampac-status   — Check status"
echo "  lampac-config   — Edit config"
echo ""
echo "Next steps:"
echo "  1. Deploy plugin: sh lampac-termux/deploy-plugin.sh"
echo "  2. Start Lampac: lampac"
echo "  3. Open browser: http://127.0.0.1:9118"
echo ""
echo "If GStreamer errors appear, run:"
echo "  proot-distro login ubuntu -- bash -c '"
echo "    rm -rf /opt/lampac/module/GStreamer"
echo "    find /opt/lampac/runtimes -iname \"*gstreamer*\" -delete 2>/dev/null"
echo "    find /opt/lampac/runtimes -iname \"*gst*\" -delete 2>/dev/null"
echo "    find /opt/lampac/runtimes -iname \"*libglib*\" -delete 2>/dev/null"
echo "    echo \"GStreamer removed!\"'"
