#!/bin/bash
# Lampac NextGen - Termux setup via proot-distro (Ubuntu)
# Usage: sh setup.sh

set -e

echo ""
echo "  Lampac NextGen - Termux Installer"
echo "  ================================="
echo ""

# Step 1: Install proot-distro
echo "[1/5] Installing proot-distro..."
if ! command -v proot-distro >/dev/null 2>&1; then
  pkg update -y
  pkg install -y proot-distro
else
  echo "  proot-distro already installed"
fi

# Step 2: Install Ubuntu
echo ""
echo "[2/5] Installing Ubuntu (proot)..."
if proot-distro list 2>/dev/null | grep -qi "ubuntu"; then
  echo "  Ubuntu already installed"
else
  proot-distro install ubuntu || true
fi

# Step 3: Setup Lampac inside Ubuntu
echo ""
echo "[3/5] Setting up Lampac inside Ubuntu..."

proot-distro login ubuntu -- bash -c '
set -e

echo "  Installing dependencies..."
apt-get update -qq
apt-get install -y -qq curl wget unzip

# Auto-detect and install libicu
echo "  Installing libicu..."
ICU_PKG=$(apt-cache search "^libicu[0-9]" | grep -v dev | grep -v java | sort -V | tail -1 | cut -d" " -f1)
if [ -n "$ICU_PKG" ]; then
  apt-get install -y -qq "$ICU_PKG"
fi

# libssl
apt-get install -y -qq libssl3 2>/dev/null \
  || apt-get install -y -qq libssl3t64 2>/dev/null \
  || apt-get install -y -qq libssl-dev 2>/dev/null \
  || true

# Install .NET 10
echo "  Installing .NET 10 runtime..."
if ! command -v dotnet >/dev/null 2>&1; then
  cd /tmp
  curl -sSL https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
  chmod +x dotnet-install.sh
  ./dotnet-install.sh --runtime aspnetcore --channel 10.0
  rm -f dotnet-install.sh

  export DOTNET_ROOT="$HOME/.dotnet"
  export PATH="$DOTNET_ROOT:$PATH"
  echo "export DOTNET_ROOT=\$HOME/.dotnet" >> /root/.bashrc
  echo "export PATH=\$DOTNET_ROOT:\$PATH" >> /root/.bashrc
else
  echo "  .NET already installed"
fi

export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$PATH"

# Download Lampac
LAMPAC_DIR="/opt/lampac"
mkdir -p "$LAMPAC_DIR"

echo "  Downloading Lampac latest release..."
cd /tmp
LATEST_URL=$(curl -sL "https://api.github.com/repos/lampac-nextgen/lampac/releases/latest" \
  | grep "browser_download_url.*lampac-nextgen.zip" | head -1 | cut -d"\"" -f4)

if [ -z "$LATEST_URL" ]; then
  echo "  ERROR: Could not find release URL"
  exit 1
fi

curl -sL "$LATEST_URL" -o lampac-nextgen.zip
unzip -qo lampac-nextgen.zip -d "$LAMPAC_DIR"
rm -f lampac-nextgen.zip

# Create init.conf if not exists
if [ ! -f "$LAMPAC_DIR/init.conf" ]; then
  if [ -f "$LAMPAC_DIR/config/example.init.conf" ]; then
    cp "$LAMPAC_DIR/config/example.init.conf" "$LAMPAC_DIR/init.conf"
  fi
fi

# Disable GStreamer module - rename all GStreamer DLLs to prevent loading
echo "  Disabling GStreamer module (not needed for basic usage)..."
find "$LAMPAC_DIR" -iname "*gstreamer*.dll" -exec mv {} {}.disabled \; 2>/dev/null || true
find "$LAMPAC_DIR/module/GStreamer" -name "*.dll" -exec mv {} {}.disabled \; 2>/dev/null || true

# Create startup script
cat > /opt/lampac/start.sh << "STARTSCRIPT"
#!/bin/bash
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$PATH"
cd /opt/lampac
dotnet Core.dll
STARTSCRIPT
chmod +x /opt/lampac/start.sh

echo "  Lampac installed to $LAMPAC_DIR"
'

# Step 4: Create Termux wrapper scripts
echo ""
echo "[4/5] Creating launcher scripts..."

cat > "$PREFIX/bin/lampac" << 'EOF'
#!/bin/bash
echo ""
echo "  Starting Lampac NextGen..."
echo "  Web UI: http://127.0.0.1:9118"
echo "  Press Ctrl+C to stop"
echo ""
proot-distro login ubuntu -- bash /opt/lampac/start.sh
EOF
chmod +x "$PREFIX/bin/lampac"

cat > "$PREFIX/bin/lampac-stop" << 'EOF'
#!/bin/bash
proot-distro login ubuntu -- bash -c 'pkill -f "dotnet Core.dll" 2>/dev/null && echo "Lampac stopped" || echo "Lampac not running"'
EOF
chmod +x "$PREFIX/bin/lampac-stop"

cat > "$PREFIX/bin/lampac-status" << 'EOF'
#!/bin/bash
proot-distro login ubuntu -- bash -c 'pgrep -f "dotnet Core.dll" >/dev/null 2>&1 && echo "Lampac: RUNNING" || echo "Lampac: STOPPED"'
EOF
chmod +x "$PREFIX/bin/lampac-status"

cat > "$PREFIX/bin/lampac-config" << 'EOF'
#!/bin/bash
proot-distro login ubuntu -- nano /opt/lampac/init.conf
EOF
chmod +x "$PREFIX/bin/lampac-config"

# Step 5: Done
echo ""
echo "[5/5] Setup complete!"
echo ""
echo "  Commands:"
echo "    lampac          - Start Lampac"
echo "    lampac-stop     - Stop Lampac"
echo "    lampac-status   - Check status"
echo "    lampac-config   - Edit config"
echo ""
echo "  After starting, open:"
echo "    http://127.0.0.1:9118"
echo ""
echo "  First time: edit init.conf to enable providers:"
echo "    lampac-config"
echo ""
