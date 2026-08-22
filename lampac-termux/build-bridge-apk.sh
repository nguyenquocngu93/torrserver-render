#!/bin/bash
# ============================================================
# SubBridge APK Builder for Termux
# Tạo APK bridge gửi subtitle từ Lampa → MXPlayer
# ============================================================
set -e

APP_NAME="SubBridge"
PACKAGE="com.lampac.bridge"
VERSION="1.0"
BUILD_DIR="$(pwd)/build-bridge"
SRC_DIR="$(pwd)/mxplayer-bridge-app"

echo "============================================"
echo "  $APP_NAME APK Builder v$VERSION"
echo "============================================"

# --- Step 1: Install required packages ---
echo ""
echo "[1/8] Installing build dependencies..."

# Auto-detect Android SDK on Termux
if [ -z "$ANDROID_HOME" ] || [ ! -d "$ANDROID_HOME" ]; then
    if [ -d "$PREFIX/share/android-sdk" ]; then
        export ANDROID_HOME="$PREFIX/share/android-sdk"
    elif [ -d "/data/data/com.termux/files/usr/share/android-sdk" ]; then
        export ANDROID_HOME="/data/data/com.termux/files/usr/share/android-sdk"
    fi
fi
echo "  ANDROID_HOME=$ANDROID_HOME"

# Install packages if needed
for pkg in aapt2 dx apksigner openjdk-17; do
    pkg install -y "$pkg" 2>/dev/null || true
done

# d8 command: on Termux 'dx' provides 'dx' not 'd8'
# We'll use 'dx --dex' as fallback
D8_CMD=""
if command -v d8 &>/dev/null; then
    D8_CMD="d8"
elif command -v dx &>/dev/null; then
    D8_CMD="dx"
    echo "  ℹ Using 'dx' instead of 'd8'"
else
    echo "  ✗ Neither d8 nor dx found. Install:"
    echo "    pkg install dx"
    exit 1
fi

# Verify other tools
for cmd in aapt2 apksigner javac keytool; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "  ✗ $cmd not found"
        exit 1
    fi
done
echo "  ✓ All build tools ready (DEX compiler: $D8_CMD)"

# --- Step 2: Clean build directory ---
echo ""
echo "[2/8] Preparing build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"/{gen,obj,bin,apk}

# --- Step 3: Generate app icon ---
echo ""
echo "[3/8] Generating app icon..."
ICON_DIR="$SRC_DIR/res/mipmap-hdpi"
mkdir -p "$ICON_DIR"

# Create a simple 72x72 PNG icon using printf (minimal valid PNG)
# This is a tiny blue square icon
python3 -c "
import struct, zlib
width, height = 72, 72
# Create raw image data (RGBA - blue icon with white 'S')
raw = b''
for y in range(height):
    raw += b'\x00'  # filter byte
    for x in range(width):
        # Simple blue background with rounded feel
        if 4 < y < height-4 and 4 < x < width-4:
            raw += b'\x21\x96\xf3\xff'  # Blue
        else:
            raw += b'\x00\x00\x00\x00'  # Transparent

# PNG chunks
def chunk(name, data):
    c = name + data
    crc = struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    return struct.pack('>I', len(data)) + c + crc

sig = b'\x89PNG\r\n\x1a\n'
ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
idat = zlib.compress(raw)
png = sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')

with open('$ICON_DIR/ic_launcher.png', 'wb') as f:
    f.write(png)
print('  ✓ Icon generated')
" 2>/dev/null || {
    # Fallback: create 1x1 PNG if python fails
    printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' > "$ICON_DIR/ic_launcher.png"
    echo "  ✓ Fallback icon created"
}

# --- Step 4: Compile resources ---
echo ""
echo "[4/8] Compiling resources..."
aapt2 compile -o "$BUILD_DIR/obj/" --dir "$SRC_DIR/res"
echo "  ✓ Resources compiled"

# Find android.jar
ANDROID_JAR=""
for ver in 34 33 32 31 30; do
    if [ -f "$ANDROID_HOME/platforms/android-$ver/android.jar" ]; then
        ANDROID_JAR="$ANDROID_HOME/platforms/android-$ver/android.jar"
        break
    fi
done
if [ -z "$ANDROID_JAR" ]; then
    echo "  ✗ android.jar not found in $ANDROID_HOME/platforms/"
    echo "  Available: $(ls $ANDROID_HOME/platforms/ 2>/dev/null || echo 'none')"
    exit 1
fi
echo "  Using: $ANDROID_JAR"

# --- Step 5: Link resources ---
echo ""
echo "[5/8] Linking resources..."
aapt2 link -o "$BUILD_DIR/apk/$APP_NAME.unsigned.apk" \
    -I "$ANDROID_JAR" \
    --manifest "$SRC_DIR/AndroidManifest.xml" \
    --java "$BUILD_DIR/gen" \
    --auto-add-overlay \
    "$BUILD_DIR"/obj/*.flat
echo "  ✓ Resources linked"

# --- Step 6: Compile Java ---
echo ""
echo "[6/8] Compiling Java source..."
# Find all java files
find "$SRC_DIR/src" "$BUILD_DIR/gen" -name "*.java" > "$BUILD_DIR/sources.txt"

javac \
    -source 1.8 -target 1.8 \
    -bootclasspath "$ANDROID_JAR" \
    -classpath "$ANDROID_JAR" \
    -d "$BUILD_DIR/bin" \
    @"$BUILD_DIR/sources.txt"
echo "  ✓ Java compiled"

# --- Step 7: Convert to DEX ---
echo ""
echo "[7/8] Converting to DEX..."
# Collect all .class files
find "$BUILD_DIR/bin" -name "*.class" > "$BUILD_DIR/classes.txt"

if [ "$D8_CMD" = "d8" ]; then
    d8 --output "$BUILD_DIR/" \
        --lib "$ANDROID_JAR" \
        @"$BUILD_DIR/classes.txt"
else
    # Use dx --dex (legacy but works)
    dx --dex --output="$BUILD_DIR/classes.dex" \
        @"$BUILD_DIR/classes.txt"
fi
echo "  ✓ DEX converted"

# --- Step 8: Package APK ---
echo ""
echo "[8/8] Packaging APK..."

# Add DEX to APK
cd "$BUILD_DIR"
cp "apk/$APP_NAME.unsigned.apk" "$APP_NAME.tmp.apk"
# Use zip to add classes.dex
zip -j "$APP_NAME.tmp.apk" classes.dex
mv "$APP_NAME.tmp.apk" "apk/$APP_NAME.unsigned.apk"

# Zipalign (if available)
if command -v zipalign &>/dev/null; then
    zipalign -f 4 "apk/$APP_NAME.unsigned.apk" "apk/$APP_NAME.aligned.apk"
    APK_IN="apk/$APP_NAME.aligned.apk"
else
    APK_IN="apk/$APP_NAME.unsigned.apk"
fi

# Sign APK
KEYSTORE="$BUILD_DIR/bridge.keystore"
if [ ! -f "$KEYSTORE" ]; then
    keytool -genkeypair -v \
        -keystore "$KEYSTORE" \
        -alias bridge \
        -keyalg RSA -keysize 2048 \
        -validity 10000 \
        -storepass bridge123 \
        -keypass bridge123 \
        -dname "CN=SubBridge, OU=Lampac, O=Bridge, L=HCM, ST=HCM, C=VN" \
        2>&1 | grep -v 'Generating' || true
fi

apksigner sign \
    --ks "$KEYSTORE" \
    --ks-pass pass:bridge123 \
    --key-pass pass:bridge123 \
    --ks-key-alias bridge \
    --out "apk/$APP_NAME.apk" \
    "$APK_IN"

cd - > /dev/null

FINAL_APK="$BUILD_DIR/apk/$APP_NAME.apk"
if [ -f "$FINAL_APK" ]; then
    SIZE=$(du -h "$FINAL_APK" | cut -f1)
    echo ""
    echo "============================================"
    echo "  ✓ BUILD SUCCESS!"
    echo "  APK: $FINAL_APK"
    echo "  Size: $SIZE"
    echo "============================================"
    echo ""
    echo "Install on Android:"
    echo "  termux-open $FINAL_APK"
    echo "  # or"
    echo "  cp $FINAL_APK ~/storage/downloads/"
    echo ""
    echo "Or transfer to phone:"
    echo "  termux-share $FINAL_APK"
else
    echo "✗ Build failed!"
    exit 1
fi
