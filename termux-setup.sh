#!/data/data/com.termux/files/usr/bin/sh
# ============================================================
#  TorrServer setup for Termux (Android)
#  Run inside Termux:   sh termux-setup.sh
#  Applies the same proven tuning as the VPS install:
#    - uTP OFF (force TCP)  <-- biggest speed fix
#    - 256MB cache, PreloadCache 95, ReaderReadAHead 100
#    - ResponsiveMode ON, EnableIPv6 ON (helps mobile NAT)
#  CÀI KÈM JACKETT (mặc định): tổng hợp indexer rutracker/toloka/rutor/
#  1337x/TPB tại http://localhost:9117 (JACKETT=0 để bỏ qua).
#  Jackett là binary .NET/glibc nên script tự cài glibc-repo + glibc-runner (grun).
# ============================================================
set -e

# ------------------- CONFIG (edit here) -------------------
PORT="${PORT:-8090}"            # TorrServer web UI port
CACHE_MB="${CACHE_MB:-256}"     # cache size in MB (phone: 256 is safe)
ENABLE_IPV6="${ENABLE_IPV6:-1}" # 1 = on (mobile carriers use IPv6 a lot)
JACKETT="${JACKETT:-1}"         # 1 = cài kèm Jackett (mặc định), 0 = bỏ qua
VERSION="MatriX.142.2"
# -----------------------------------------------------------

# Convert IPv6 toggle to a JSON boolean (Go rejects 1/0 for bool fields -> HTTP 400)
if [ "${ENABLE_IPV6:-1}" = "1" ] || [ "${ENABLE_IPV6:-1}" = "true" ]; then
  IPV6_JSON=true
else
  IPV6_JSON=false
fi

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BASE="$HOME/.torrserver"
BIN="$BASE/torrserver"
DATA="$BASE/data"
CACHE_BYTES=$((CACHE_MB * 1048576))

echo "==> Installing curl (if needed)"
command -v curl >/dev/null 2>&1 || pkg install -y curl

echo "==> Creating directories"
mkdir -p "$BASE" "$DATA"

echo "==> Detecting architecture"
ARCH=$(uname -m)
case "$ARCH" in
  aarch64|arm64) ASSET="TorrServer-linux-arm64" ;;
  armv7l|armv8l|arm) ASSET="TorrServer-linux-arm7" ;;
  x86_64|amd64) ASSET="TorrServer-linux-amd64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac
echo "    arch=$ARCH -> $ASSET"

echo "==> Downloading TorrServer ${VERSION} (${ASSET})"
if [ ! -x "$BIN" ]; then
  curl -sL -o "$BIN" "https://github.com/YouROK/TorrServer/releases/download/${VERSION}/${ASSET}"
  chmod +x "$BIN"
fi
"$BIN" -h >/dev/null 2>&1 || true

# ------------------- BBR (best effort, needs root) ---------
if [ "$(id -u)" = 0 ]; then
  echo "==> Trying to enable BBR (root available)"
  if sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1; then
    echo "    BBR enabled ✅"
  else
    echo "    BBR not available on this kernel (normal on Android)"
  fi
else
  echo "==> BBR skipped (no root) — uTP off already fixes the main issue"
fi

# ------------------- Run as daemon --------------------------
if [ -d "$PREFIX/var/service" ] && command -v sv-enable >/dev/null 2>&1; then
  echo "==> Setting up termux-services daemon"
  mkdir -p "$PREFIX/var/service/torrserver"
  cat > "$PREFIX/var/service/torrserver/run" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec $BIN -d $DATA -p $PORT
EOF
  chmod +x "$PREFIX/var/service/torrserver/run"
  sv-enable torrserver 2>/dev/null || true
  sv up torrserver 2>/dev/null || true
else
  echo "==> termux-services not found, using nohup (install with: pkg install termux-services)"
  pkill -f "$BIN" 2>/dev/null || true
  nohup "$BIN" -d "$DATA" -p "$PORT" > "$BASE/torrserver.log" 2>&1 &
  echo "    started, log: $BASE/torrserver.log"
fi

# ------------------- Extra trackers --------------------------
echo "==> Writing extra trackers (trackers.txt -> applied to every new torrent)"
cat > "$DATA/trackers.txt" <<'EOF'
# Public trackers (fallback when GitHub tracker list is unreachable)
udp://tracker.opentrackr.org:1337/announce
udp://tracker.openbittorrent.com:6969/announce
udp://exodus.desync.com:6969/announce
udp://tracker.torrent.eu.org:451/announce
udp://tracker.moeking.me:6969/announce
udp://open.stealth.si:80/announce
udp://tracker.cyberia.is:6969/announce
https://tracker.nanoha.org:443/announce
http://tracker.openbittorrent.com:80/announce
http://tracker.opentrackr.org:1337/announce
# RU trackers: rutracker (bt.t-ru.org) + RU ISP retracker — helps Nga/EU sources find peers
http://bt.t-ru.org/announce
http://bt2.t-ru.org/announce
http://bt3.t-ru.org/announce
http://bt4.t-ru.org/announce
http://retracker.mgts.by:80/announce
EOF

# ------------------- Apply tuned settings -------------------
echo "==> Applying performance settings (uTP off, ${CACHE_MB}MB cache, IPv6 ${ENABLE_IPV6})"
ready=0
i=0
while [ "$i" -lt 30 ]; do
  if curl -sf -o /dev/null "http://127.0.0.1:${PORT}/"; then
    ready=1
    break
  fi
  sleep 1
  i=$((i + 1))
done

if [ "$ready" -eq 1 ]; then
  cat > "$BASE/settings.json" <<EOF
{
  "CacheSize": ${CACHE_BYTES},
  "ReaderReadAHead": 100,
  "PreloadCache": 95,
  "UseDisk": false,
  "TorrentsSavePath": "",
  "RemoveCacheOnDrop": false,
  "ForceEncrypt": false,
  "RetrackersMode": 1,
  "TorrentDisconnectTimeout": 86400,
  "EnableDebug": false,
  "EnableDLNA": false,
  "EnableBonjour": false,
  "FriendlyName": "",
  "EnableRutorSearch": true,
  "EnableTorznabSearch": false,
  "TorznabUrls": null,
  "TMDBSettings": {
    "APIKey": "",
    "APIURL": "",
    "ImageURL": "",
    "ImageURLRu": ""
  },
  "EnableIPv6": ${IPV6_JSON},
  "DisableTCP": false,
  "DisableUTP": true,
  "DisableUPNP": false,
  "DisableDHT": false,
  "DisablePEX": false,
  "DisableUpload": false,
  "DownloadRateLimit": 0,
  "UploadRateLimit": 0,
  "ConnectionsLimit": 300,
  "PeersListenPort": 0,
  "EnableLPD": false,
  "LPDIPv6": true,
  "SslPort": 0,
  "SslCert": "",
  "SslKey": "",
  "ResponsiveMode": true,
  "ShowFSActiveTorr": false,
  "StoreSettingsInJson": false,
  "StoreViewedInJson": false,
  "TrackTimecode": false
}
EOF
  # TorrServer API expects {"action":"set","sets":{...}}
  { echo '{"action":"set","sets":'; cat "$BASE/settings.json"; echo '}'; } > "$BASE/settings-req.json"
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${PORT}/settings" \
    -H "Content-Type: application/json" \
    --data-binary @"$BASE/settings-req.json")
  rm -f "$BASE/settings-req.json"
  if [ "$code" = "200" ]; then
    echo "    settings applied ✅ (HTTP 200)"
  else
    echo "    FAILED (HTTP $code) — settings NOT applied! Paste the response above to debug."
  fi
else
  echo "    WARNING: API not ready — check '$BASE/torrserver.log'"
fi

# ------------------- Private trackers helper (rutracker + toloka) ------------------
echo ""
echo "==> Cài helper tìm torrent từ tracker bán riêng tư (rutracker.org + toloka.to)"
# Cần có file tracker-search.sh nằm cạnh script này (copy cả repo vào Termux).
SRC_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -f "$SRC_DIR/tracker-search.sh" ]; then
  cp "$SRC_DIR/tracker-search.sh" "$BASE/tracker-search.sh"
  chmod +x "$BASE/tracker-search.sh"
  echo "    Đã cài: $BASE/tracker-search.sh"
  echo "    Dùng:   sh $BASE/tracker-search.sh search 'tên phim'"
  echo "            sh $BASE/tracker-search.sh add <số>"
  echo "    (tài khoản semi-private mặc định nằm trong tracker-search.sh — đổi mật khẩu thì sửa ở đó)"
else
  echo "    Không thấy tracker-search.sh cùng thư mục — copy thủ công nếu cần."
fi

# ------------------- Jackett (kèm mặc định) ------------------
# Jackett là binary .NET/glibc nên Termux (Android dùng bionic libc) cần
# repo glibc (gói glibc-repo) + glibc-runner (lệnh grun) để chạy được.
SRC_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "${JACKETT:-1}" = "1" ]; then
  if [ ! -f "$SRC_DIR/jackett-setup.sh" ]; then
    echo "==> Không thấy jackett-setup.sh cùng thư mục — copy cả repo vào Termux."
  else
    echo "==> Cài Jackett (JACKETT=1, đặt JACKETT=0 để bỏ qua)"
    if ! command -v grun >/dev/null 2>&1 && ! command -v glibc-runner >/dev/null 2>&1; then
      echo "    Termux cần termux-glibc để chạy Jackett (binary .NET/glibc)..."
      pkg install -y glibc-repo 2>/dev/null \
      || echo "    pkg install glibc-repo thất bại — chạy thủ công rồi chạy lại script."
      pkg update -y 2>/dev/null || true
      pkg install -y glibc-runner 2>/dev/null \
      || echo "    pkg install glibc-runner thất bại — chạy lại script sau khi cài xong."
      # Jackett (.NET) cần ICU + OpenSSL bản glibc
      pkg install -y libicu-glibc openssl-glibc 2>/dev/null \
      || echo "    pkg install libicu-glibc openssl-glibc thất bại — Jackett có thể lỗi thiếu thư viện."
    fi
    sh "$SRC_DIR/jackett-setup.sh" \
      || echo "    Jackett cài lỗi (xem log phía trên) — TorrServer vẫn chạy bình thường."
    echo "    Jackett: http://localhost:9117"
  fi
fi

# ------------------- Done + reminders ----------------------
echo ""
echo "======================================================="
echo "  TorrServer đang chạy: http://localhost:${PORT}"
echo "  (trên điện thoại mở trình duyệt vô URL này)"
if [ "${JACKETT:-1}" = "1" ]; then
  echo "  Jackett tìm torrent:  http://localhost:9117"
  echo "    (bỏ Jackett lần sau: chạy lại script với JACKETT=0)"
  echo "    (tìm nguồn chậm / tắt nguồn: sh jackett-setup.sh speedtest / disable rutracker)"
fi
echo ""
echo "  BẮT BUỘC làm 2 việc này để không bị chậm/ngắt:"
echo "  1. termux-wake-lock        (pkg install termux-api)"
echo "  2. Settings Android -> Pin -> Tối ưu hoá pin"
echo "     -> Termux -> Không giới hạn"
echo ""
echo "  Re-run script này bất cứ lúc nào để reset settings."
echo "======================================================="
