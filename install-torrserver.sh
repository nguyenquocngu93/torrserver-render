#!/bin/sh
# Install TorrServer on an Oracle Cloud / Ubuntu / Oracle Linux VPS.
# Run as root:  sudo sh ./install-torrserver.sh
# Applies the proven performance tuning: BBR congestion control on the OS,
# and TCP-only (uTP disabled) + 512MB cache + aggressive preload in TorrServer.
set -e

VERSION="MatriX.142.2"
URL="https://github.com/YouROK/TorrServer/releases/download/${VERSION}/TorrServer-linux-amd64"
BIN="/opt/torrserver/torrserver"
DATA="/var/lib/torrserver"
PORT="${PORT:-8090}"

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

echo "==> Opening port ${PORT} in instance firewall"
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${PORT}/tcp" 2>/dev/null || true
  ufw reload 2>/dev/null || true
fi
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=${PORT}/tcp 2>/dev/null || true
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
udp://tracker.opentrackr.org:1337/announce
udp://tracker.openbittorrent.com:6969/announce
udp://exodus.desync.com:6969/announce
udp://tracker.torrent.eu.org:451/announce
udp://tracker.moeking.me:6969/announce
udp://open.stealth.si:80/announce
udp://tracker.cyberia.is:6969/announce
https://tracker.nanoha.org:443/announce
EOF

# TorrServer reads trackers.txt when a torrent is ADDED, so re-add existing
# torrents (or just leave them) to pick up the extra trackers.

echo "==> Applying performance settings (uTP off, 512MB cache, tuned preload)"
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
  "CacheSize": 536870912,
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
  "EnableRutorSearch": false,
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
  curl -s -X POST "http://127.0.0.1:${PORT}/settings" \
    -H "Content-Type: application/json" \
    --data-binary @/tmp/torr-settings.json -o /dev/null || true
  rm -f /tmp/torr-settings.json
  echo "    settings applied."
else
  echo "    WARNING: API not ready, settings not applied. Run the API POST manually."
fi

echo ""
echo "Done! TorrServer is running on port ${PORT}."
echo "Check locally:  curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:${PORT}"
echo ""
echo "IMPORTANT: also open TCP ${PORT} in the Oracle Cloud console:"
echo "  Networking -> Virtual Cloud Networks -> <your VCN> -> Security Lists"
echo "  -> Default Security List -> Add Ingress Rule -> Source 0.0.0.0/0, TCP ${PORT}"
