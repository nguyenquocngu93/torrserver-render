#!/bin/bash
# ============================================================
#  setup-mxplayer-bridge.sh — Cài MXPlayer Bridge Server
# ============================================================
#  Bridge giữa Lampa Web UI và MXPlayer trên Android
#  Hỗ trợ gửi subtitle (SRT, ASS, VTT) sang MXPlayer
#
#  Usage:
#    sh lampac-termux/setup-mxplayer-bridge.sh
#
#  Requirements:
#    - MXPlayer đã cài trên Android
#    - Termux đang chạy
#    - Lampa/Lampac đang chạy trên port 9118
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DIR="$HOME/mxplayer-bridge"
BRIDGE_PORT="${MX_BRIDGE_PORT:-8484}"

echo ""
echo "============================================"
echo "  MXPlayer Bridge Server Setup"
echo "============================================"
echo ""

# ─── Step 1: Check MXPlayer installed ──────────────────────
echo "[1/4] Kiểm tra MXPlayer..."
MX_CHECK=$(pm list packages 2>/dev/null | grep com.mxtech || echo "")
if [ -z "$MX_CHECK" ]; then
  echo "  ⚠️  MXPlayer chưa cài!"
  echo "  Cài MXPlayer từ Google Play hoặc APK."
  echo "  Link: https://play.google.com/store/apps/details?id=com.mxtech.videoplayer.ad"
  echo ""
  read -p "  Tiếp tục cài bridge? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
else
  echo "  ✅ MXPlayer found: $MX_CHECK"
fi

# ─── Step 2: Create bridge directory ───────────────────────
echo "[2/4] Tạo bridge directory..."
mkdir -p "$BRIDGE_DIR"

# ─── Step 3: Copy server.js ────────────────────────────────
echo "[3/4] Copy bridge server..."
if [ -f "$SCRIPT_DIR/mxplayer-bridge/server.js" ]; then
  cp "$SCRIPT_DIR/mxplayer-bridge/server.js" "$BRIDGE_DIR/server.js"
  echo "  ✅ server.js copied"
else
  echo "  ❌ server.js not found at $SCRIPT_DIR/mxplayer-bridge/server.js"
  exit 1
fi

# ─── Step 4: Create start script ───────────────────────────
echo "[4/4] Tạo startup scripts..."

# Bridge server start
cat > "$BRIDGE_DIR/start.sh" << 'EOF'
#!/bin/bash
cd ~/mxplayer-bridge
export MX_BRIDGE_PORT="${MX_BRIDGE_PORT:-8484}"
echo "Starting MXPlayer Bridge on port $MX_BRIDGE_PORT..."
echo "Health: http://127.0.0.1:$MX_BRIDGE_PORT/health"
echo "Play: POST http://127.0.0.1:$MX_BRIDGE_PORT/play"
echo ""
node server.js "$MX_BRIDGE_PORT"
EOF
chmod +x "$BRIDGE_DIR/start.sh"

# Termux command
cat > ~/mxplayer-bridge 2>/dev/null << 'CMDEOF' || true
#!/bin/bash
cd ~/mxplayer-bridge
node server.js "${MX_BRIDGE_PORT:-8484}"
CMDEOF
chmod +x ~/mxplayer-bridge 2>/dev/null || true

# Stop command
cat > ~/mxplayer-bridge-stop 2>/dev/null << 'CMDEOF' || true
#!/bin/bash
pkill -f "node.*server.js" 2>/dev/null && echo "MXPlayer Bridge stopped" || echo "Bridge not running"
CMDEOF
chmod +x ~/mxplayer-bridge-stop 2>/dev/null || true

# Status command
cat > ~/mxplayer-bridge-status 2>/dev/null << 'CMDEOF' || true
#!/bin/bash
if pgrep -f "node.*server.js" >/dev/null; then
  PID=$(pgrep -f "node.*server.js")
  echo "✅ MXPlayer Bridge running (PID: $PID)"
  echo "   Health: http://127.0.0.1:${MX_BRIDGE_PORT:-8484}/health"
  curl -s "http://127.0.0.1:${MX_BRIDGE_PORT:-8484}/health" 2>/dev/null || echo "   (cannot connect)"
else
  echo "❌ MXPlayer Bridge not running"
fi
CMDEOF
chmod +x ~/mxplayer-bridge-status 2>/dev/null || true

# ─── Step 5: Deploy Lampa plugin ───────────────────────────
echo ""
echo "[Bonus] Deploying Lampa plugin..."

# Copy plugin to Lampac
if [ -f "$SCRIPT_DIR/plugins/lampa-mxplayer-bridge.js" ]; then
  proot-distro login ubuntu -- bash -c "
    mkdir -p /opt/lampac/plugins/override
    cp '$SCRIPT_DIR/plugins/lampa-mxplayer-bridge.js' /opt/lampac/plugins/override/lampa-mxplayer-bridge.js
    echo 'Plugin deployed to /opt/lampac/plugins/override/lampa-mxplayer-bridge.js'
  " 2>/dev/null && echo "  ✅ Plugin deployed" || echo "  ⚠️  Could not deploy plugin (run manually)"
fi

# ─── Summary ───────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "Sử dụng:"
echo ""
echo "  1. Start bridge server:"
echo "     mxplayer-bridge"
echo "     # hoặc:"
echo "     cd ~/mxplayer-bridge && node server.js"
echo ""
echo "  2. Start Lampac:"
echo "     lampac"
echo ""
echo "  3. Mở Lampa: http://127.0.0.1:9118"
echo ""
echo "  4. Trong Lampa:"
echo "     - Vào Settings → MXPlayer Bridge"
echo "     - Bật 'Mở bằng MXPlayer'"
echo "     - Set Bridge Port: $BRIDGE_PORT"
echo ""
echo "  5. Khi xem phim:"
echo "     - Click '📱 MXPlayer' button"
echo "     - Hoặc bật 'Mở bằng MXPlayer' → Play tự động"
echo ""
echo "Commands:"
echo "  mxplayer-bridge          - Start bridge"
echo "  mxplayer-bridge-stop     - Stop bridge"
echo "  mxplayer-bridge-status   - Check status"
echo ""
echo "API Endpoints:"
echo "  GET  /health             - Kiểm tra sức khỏe"
echo "  GET  /status             - Trạng thái MXPlayer"
echo "  POST /play               - Phát video + subtitle"
echo ""
echo "Subtitle formats supported:"
echo "  ✅ SRT (.srt)"
echo "  ✅ ASS/SSA (.ass, .ssa)"
echo "  ✅ VTT (.vtt)"
echo "  ✅ SUB (.sub)"
echo ""
