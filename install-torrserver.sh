#!/bin/sh
# Install TorrServer on an Oracle Cloud / Ubuntu / Oracle Linux VPS.
# Run as root:  sudo sh ./install-torrserver.sh
# Applies the proven performance tuning: BBR congestion control on the OS,
# and TCP-only (uTP disabled) + 512MB cache + aggressive preload in TorrServer.
#
# PEERS_PORT: cổng cố định cho traffic torrent (peer + DHT). Để FIXED (không
# phải 0 = random) để mở được trong firewall/security list — peer ngoài kết nối
# vào được thì tải mới nhanh, đặc biệt quan trọng trên VPS datacenter IP.
set -e

VERSION="MatriX.142.2"
URL="https://github.com/YouROK/TorrServer/releases/download/${VERSION}/TorrServer-linux-amd64"
BIN="/opt/torrserver/torrserver"
DATA="/var/lib/torrserver"
PORT="${PORT:-8090}"
PEERS_PORT="${PEERS_PORT:-45000}"

echo "==> Creating directories"
mkdir -p /opt/torrserver "$DATA"
chown -R root:root /opt/torrserver "$DATA"

echo "==> Downloading TorrServer ${VERSION}"
if [ ! -x "$BIN" ]; then
  curl -sL -o "$BIN" "$URL"
  chmod +x "$BIN"
fi
"$BIN" -h >/dev/null 2>&1 || true

echo "==> Creating systemd service (port ${PORT})"
cat > /etc/systemd/system/torrserver.service <<EOF
[Unit]
Description=TorrServer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN} -d ${DATA} -p ${PORT}
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

echo "==> Starting service"
systemctl daemon-reload
systemctl enable torrserver
systemctl restart torrserver
sleep 2
systemctl status torrserver --no-pager -l | head -15 || true

echo "==> Opening ports in instance firewall: ${PORT}/tcp (web UI) + ${PEERS_PORT} (torrent traffic, TCP+UDP)"
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${PORT}/tcp" 2>/dev/null || true
  ufw allow "${PEERS_PORT}/tcp" 2>/dev/null || true
  ufw allow "${PEERS_PORT}/udp" 2>/dev/null || true
  ufw reload 2>/dev/null || true
fi
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=${PORT}/tcp 2>/dev/null || true
  firewall-cmd --permanent --add-port=${PEERS_PORT}/tcp 2>/dev/null || true
  firewall-cmd --permanent --add-port=${PEERS_PORT}/udp 2>/dev/null || true
  firewall-cmd --reload 2>/dev/null || true
fi

echo "==> Enabling BBR congestion control (helps long-distance torrent traffic)"
modprobe tcp_bbr 2>/dev/null || true
modprobe sch_fq 2>/dev/null || true
cat > /etc/sysctl.d/99-torr-bbr.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p /etc/sysctl.d/99-torr-bbr.conf >/dev/null 2>&1 || true

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

# TorrServer reads trackers.txt when a torrent is ADDED, so re-add existing
# torrents (or just leave them) to pick up the extra trackers.

echo "==> Sizing cache to available RAM"
MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
if [ "${MEM_KB:-0}" -lt 2097152 ]; then
  CACHE_BYTES=268435456
  echo "    low-RAM box (${MEM_KB} KB) -> 256MB cache (prevents OOM crashes)"
else
  CACHE_BYTES=536870912
  echo "    RAM ${MEM_KB} KB -> 512MB cache"
fi

echo "==> Applying performance settings (uTP off, cache tuned, preload 95)"
# Wait until the web API answers, then push the full tuned settings object.
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
  cat > /tmp/torr-settings.json <<EOF
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
  "EnableIPv6": false,
  "DisableTCP": false,
  "DisableUTP": true,
  "DisableUPNP": false,
  "DisableDHT": false,
  "DisablePEX": false,
  "DisableUpload": false,
  "DownloadRateLimit": 0,
  "UploadRateLimit": 0,
  "ConnectionsLimit": 300,
  "PeersListenPort": ${PEERS_PORT},
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
  { echo '{"action":"set","sets":'; cat /tmp/torr-settings.json; echo '}'; } > /tmp/torr-settings-req.json
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${PORT}/settings" \
    -H "Content-Type: application/json" \
    --data-binary @/tmp/torr-settings-req.json)
  rm -f /tmp/torr-settings.json /tmp/torr-settings-req.json
  if [ "$code" = "200" ]; then
    echo "    settings applied ✅ (HTTP 200)"
  else
    echo "    FAILED (HTTP $code) — settings NOT applied! Paste the response above to debug."
  fi
else
  echo "    WARNING: API not ready, settings not applied. Run the API POST manually."
fi

echo ""
echo "==> Installing private-tracker search helper (rutracker.org + toloka.to)"
# Cần có file tracker-search.sh nằm cạnh script này (copy cả repo lên VPS).
SRC_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -f "$SRC_DIR/tracker-search.sh" ]; then
  cp "$SRC_DIR/tracker-search.sh" /opt/torrserver/tracker-search.sh
  chmod +x /opt/torrserver/tracker-search.sh
  echo "    Đã cài: /opt/torrserver/tracker-search.sh"
  echo "    Dùng:   sh /opt/torrserver/tracker-search.sh search 'tên phim'"
  echo "            sh /opt/torrserver/tracker-search.sh add <số>"
  echo "    (tài khoản semi-private mặc định nằm trong tracker-search.sh — đổi mật khẩu thì sửa ở đó)"
else
  echo "    Không thấy tracker-search.sh cùng thư mục — copy thủ công nếu cần."
fi

echo ""
echo "==> Installing Jackett (optional, set JACKETT=1 to enable)"
# Tổng hợp indexer tìm torrent (rutracker, toloka, rutor, 1337x, TPB) qua web UI.
SRC_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "${JACKETT:-0}" = "1" ] && [ -f "$SRC_DIR/jackett-setup.sh" ]; then
  echo "    Cài Jackett + cấu hình indexer..."
  JACKETT_EXTERNAL=1 sh "$SRC_DIR/jackett-setup.sh"
  echo "    Jackett: http://<IP>:9117 (nhớ mở TCP 9117 trong Oracle Cloud console)"
elif [ "${JACKETT:-0}" = "1" ]; then
  echo "    Không thấy jackett-setup.sh cùng thư mục — copy cả repo lên VPS."
else
  echo "    Bỏ qua (chạy lại với JACKETT=1 để cài Jackett)."
fi

echo ""
echo "Done! TorrServer is running on port ${PORT}."
echo "Check locally:  curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:${PORT}"
echo ""
echo "IMPORTANT: also open BOTH ports in the Oracle Cloud console:"
echo "  Networking -> Virtual Cloud Networks -> <your VCN> -> Security Lists"
echo "  -> Default Security List -> Add Ingress Rule -> Source 0.0.0.0/0:"
echo "     - TCP ${PORT}        (web UI)"
echo "     - TCP + UDP ${PEERS_PORT}  (traffic torrent — mở UDP mới có DHT)"
echo "  Không mở cổng peer = peer ngoài không kết nối vào = tải chậm dù nhiều seed."
