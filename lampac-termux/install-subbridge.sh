#!/bin/bash
# ============================================================
# SubBridge Full Installer
# Cài APK bridge + deploy plugin vào Lampa
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_URL="https://cdn.jsdelivr.net/gh/nguyenquocngu7863-ai/lampac@4c02065/subsense-auto-v3.js"
BRIDGE_PORT=8484
LAMPA_DIR="/opt/lampac"

echo "============================================"
echo "  SubBridge Installer v1.0"
echo "  Bridge: Lampa ↔ MXPlayer"
echo "============================================"

# --- Step 1: Install build deps ---
echo ""
echo "[1/5] Installing build dependencies..."

INSTALL_PKGS=""
for cmd in aapt2 d8 apksigner javac python3; do
    if ! command -v "$cmd" &>/dev/null; then
        case "$cmd" in
            aapt2)     INSTALL_PKGS="$INSTALL_PKGS aapt2" ;;
            d8)        INSTALL_PKGS="$INSTALL_PKGS dx" ;;
            apksigner) INSTALL_PKGS="$INSTALL_PKGS apksigner" ;;
            javac)     INSTALL_PKGS="$INSTALL_PKGS openjdk-17" ;;
            python3)   INSTALL_PKGS="$INSTALL_PKGS python" ;;
        esac
    fi
done

if [ -n "$INSTALL_PKGS" ]; then
    pkg install -y $INSTALL_PKGS 2>/dev/null || true
fi
echo "  ✓ Build tools ready"

# --- Step 2: Build APK ---
echo ""
echo "[2/5] Building SubBridge APK..."
cd "$SCRIPT_DIR"
bash build-bridge-apk.sh

APK_PATH="$(pwd)/build-bridge/apk/SubBridge.apk"
if [ ! -f "$APK_PATH" ]; then
    echo "  ✗ APK build failed!"
    exit 1
fi
echo "  ✓ APK built: $APK_PATH"

# --- Step 3: Install APK ---
echo ""
echo "[3/5] Installing APK on device..."

# Try termux-open first
if command -v termux-open &>/dev/null; then
    termux-open "$APK_PATH" 2>/dev/null && {
        echo "  ✓ APK opened for install"
    } || echo "  ⚠ Open Settings > Apps to install manually"
elif command -v xdg-open &>/dev/null; then
    xdg-open "$APK_PATH" 2>/dev/null || true
fi

# Also copy to Downloads
if [ -d "$HOME/storage/downloads" ]; then
    cp "$APK_PATH" "$HOME/storage/downloads/SubBridge.apk" 2>/dev/null && \
        echo "  ✓ Copied to ~/storage/downloads/SubBridge.apk"
fi
echo "  ⚠ Install the APK manually if not prompted"

# --- Step 4: Deploy plugin to Lampa ---
echo ""
echo "[4/5] Deploying SubBridge plugin to Lampa..."

PLUGIN_SRC="$SCRIPT_DIR/plugins/subbridge-plugin.js"
PLUGIN_DEST="$LAMPA_DIR/plugins/override/subbridge-plugin.js"

if [ -f "$PLUGIN_SRC" ]; then
    mkdir -p "$LAMPA_DIR/plugins/override" 2>/dev/null || sudo mkdir -p "$LAMPA_DIR/plugins/override"
    cp "$PLUGIN_SRC" "$PLUGIN_DEST" 2>/dev/null || sudo cp "$PLUGIN_SRC" "$PLUGIN_DEST"
    echo "  ✓ Plugin deployed: $PLUGIN_DEST"
else
    echo "  ✗ Plugin source not found: $PLUGIN_SRC"
fi

# --- Step 5: Configure Lampa ---
echo ""
echo "[5/5] Configuring Lampa customPlugins..."

CONF="$LAMPA_DIR/init.conf"
if [ -f "$CONF" ]; then
    # Check if SubBridge plugin already configured
    if ! grep -q "subbridge-plugin.js" "$CONF" 2>/dev/null; then
        # Add SubBridge plugin to customPlugins
        if grep -q "customPlugins" "$CONF"; then
            # Append to existing array
            sudo sed -i 's|"customPlugins":\[|"customPlugins":[{"url":"{localhost}/subbridge-plugin.js","status":1},' "$CONF" 2>/dev/null || \
            sed -i 's|"customPlugins":\[|"customPlugins":[{"url":"{localhost}/subbridge-plugin.js","status":1},' "$CONF" 2>/dev/null
        else
            # Add new customPlugins field
            sudo sed -i 's|"BaseModule"|{"LampaWeb":{"customPlugins":[{"url":"{localhost}/subbridge-plugin.js","status":1}]},"BaseModule"|' "$CONF" 2>/dev/null || \
            sed -i 's|"BaseModule"|{"LampaWeb":{"customPlugins":[{"url":"{localhost}/subbridge-plugin.js","status":1}]},"BaseModule"|' "$CONF" 2>/dev/null
        fi
        echo "  ✓ Plugin added to init.conf"
    else
        echo "  ✓ Plugin already configured"
    fi
else
    echo "  ⚠ init.conf not found, create it later"
fi

# --- Done ---
echo ""
echo "============================================"
echo "  ✓ INSTALLATION COMPLETE!"
echo "============================================"
echo ""
echo "Cách sử dụng:"
echo ""
echo "1. Cài APK trên điện thoại:"
echo "   termux-open $APK_PATH"
echo "   Hoặc: Cài từ ~/storage/downloads/SubBridge.apk"
echo ""
echo "2. Mở SubBridge app trên điện thoại"
echo "   (server sẽ chạy trên port $BRIDGE_PORT)"
echo ""
echo "3. Mở Lampa trong browser:"
echo "   http://127.0.0.1:9118"
echo ""
echo "4. Settings → SubBridge MXPlayer → Bật"
echo ""
echo "5. Chơi phim → Nút 📱 MXPlayer sẽ hiện"
echo "   → Click để mở qua MXPlayer + phụ đề"
echo ""
echo "Lưu ý:"
echo "  - SubBridge app phải đang chạy"
echo "  - MXPlayer phải cài trên điện thoại"
echo "  - Plugin subsense-auto-v3.js sẽ tự lấy sub"
echo "============================================"
