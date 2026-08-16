#!/bin/sh
# ============================================================
#  jackett-add.sh — thêm torrent tìm được trên Jackett thẳng
#  vào TorrServer (bỏ qua bước tải .torrent thủ công).
#
#  Cách dùng:
#    sh jackett-add.sh "http://localhost:9117/dl/...torrent"   (link tải từ Jackett UI)
#    sh jackett-add.sh "magnet:?xt=urn:btih:..."              (magnet bất kỳ)
#
#  Biến môi trường:
#    TS_URL   địa chỉ TorrServer (mặc định http://127.0.0.1:8090)
# ============================================================
set -u

TS_URL="${TS_URL:-http://127.0.0.1:8090}"
url="${1:-}"

if [ -z "$url" ]; then
  echo "Cách dùng: sh $0 <link .torrent hoặc magnet>"
  exit 1
fi

command -v curl >/dev/null 2>&1 || { echo "Lỗi: thiếu 'curl'."; exit 1; }

case "$url" in
  magnet:*)
    echo "Thêm magnet vào TorrServer ($TS_URL) ..."
    curl -s -X POST "$TS_URL/torrents" -H 'Content-Type: application/json' \
      --data-binary "{\"action\":\"add\",\"link\":\"$url\"}"
    echo ""
    ;;
  http*)
    f=$(mktemp)
    echo "Tải .torrent ..."
    curl -sL "$url" -o "$f"
    if ! grep -aq '4:info' "$f"; then
      echo "Không phải file .torrent hợp lệ (cần đăng nhập? link sai?) — nội dung nhận được:"
      head -c 300 "$f"
      echo ""
      rm -f "$f"
      exit 1
    fi
    echo "Thêm vào TorrServer ($TS_URL) ..."
    curl -s -F "file=@$f" -F "save=1" "$TS_URL/torrent/upload"
    echo ""
    rm -f "$f"
    ;;
  *)
    echo "Link không hiểu: phải bắt đầu bằng http:// hoặc magnet:"
    exit 1
    ;;
esac
