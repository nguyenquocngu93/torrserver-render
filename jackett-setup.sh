#!/bin/sh
# ============================================================
#  jackett-setup.sh — cài Jackett + cấu hình sẵn indexer
#  (RuTracker.org, Toloka.to, Rutor, 1337x, The Pirate Bay)
#
#  Dùng:
#    sh jackett-setup.sh                  cài + chạy + cấu hình indexer
#    sh jackett-setup.sh configure        cấu hình lại (Jackett đang chạy)
#    sh jackett-setup.sh start            chỉ khởi động Jackett (không đụng cấu hình)
#    sh jackett-setup.sh speedtest [từ]   đo tốc độ search từng indexer, tìm nguồn chậm
#    sh jackett-setup.sh disable <id>...  tắt tạm indexer (bật lại = chạy lại setup)
#    sh jackett-setup.sh tune [id...]     TỰ tắt nguồn lỗi/chậm — hay dùng nhất trên VPS:
#                                         đo từng nguồn, tắt nguồn HTTP lỗi / 0 kết quả /
#                                         chậm quá MAX_SECONDS (mặc định 30). Truyền thêm
#                                         id để tắt trước, vd:  sh jackett-setup.sh tune rutracker
#    ví dụ:  sh jackett-setup.sh disable rutracker 1337x
#
#  Biến môi trường (có sẵn giá trị mặc định):
#    JACKETT_PORT        cổng web UI (mặc định 9117)
#    JACKETT_DIR         thư mục dữ liệu/config (mặc định /opt/jackett khi
#                        chạy root, ngược lại $HOME/.jackett)
#    RUTRACKER_LOGIN/PASS  tài khoản rutracker (mặc định Saunhung/saunhung)
#    TOLOKA_LOGIN/PASS     tài khoản toloka   (mặc định Saunhung/saunhung)
#    RUTRACKER_COOKIES     cookie đã đăng nhập rutracker → qua mặt Cloudflare
#    TOLOKA_COOKIES        cookie đã đăng nhập toloka
#    FLARESOLVERR_URL      URL FlareSolverr, vd http://127.0.0.1:8191 → tự
#                          qua mặt Cloudflare (chạy FlareSolverr trước)
#    JACKETT_EXTERNAL=1    cho phép truy cập từ ngoài (VPS: mở port 9117)
#    JACKETT_PASSWORD      đặt mật khẩu admin cho web UI
#    JACKETT_SELFTEST=1    tự test tìm kiếm rutracker sau khi cấu hình
#    TUNE=1                sau khi cấu hình xong, tự chạy tune (tắt nguồn chậm)
#    SKIP_INDEXERS         bỏ qua cấu hình các indexer, cách nhau space
#                          ví dụ: SKIP_INDEXERS="rutracker 1337x" sh jackett-setup.sh
#
#  VẤN ĐỀ CLOUDFLARE CỦA rutracker:
#  rutracker.org đứng sau Cloudflare — từ IP datacenter/VPS Jackett thường
#  bị chặn ("Challenge detected but FlareSolverr is not configured").
#  Cách xử lý, chọn 1 trong 2:
#    a) FlareSolverr (tự động, chạy 24/7):
#         docker run -d --name flaresolverr -p 8191:8191 \
#           ghcr.io/flaresolverr/flaresolverr:latest
#         FLARESOLVERR_URL=http://127.0.0.1:8191 sh jackett-setup.sh
#    b) Cookie trình duyệt (không cần Docker, nhưng hết hạn phải dán lại):
#         đăng nhập rutracker.org bằng trình duyệt → DevTools (F12) →
#         Application → Cookies → copy toàn bộ cookies dạng
#         "name=value; name2=value2" rồi:
#         RUTRACKER_COOKIES='bb_session=...; bb_lastvisit=...' sh jackett-setup.sh
# ============================================================
set -u

# ------------------- CONFIG -------------------
JACKETT_PORT="${JACKETT_PORT:-9117}"
if [ "$(id -u)" = "0" ] 2>/dev/null && [ -z "${JACKETT_DIR:-}" ]; then
  JACKETT_DIR="/opt/jackett"
else
  JACKETT_DIR="${JACKETT_DIR:-$HOME/.jackett}"
fi

RUTRACKER_LOGIN="${RUTRACKER_LOGIN:-Saunhung}"
RUTRACKER_PASS="${RUTRACKER_PASS:-saunhung}"
TOLOKA_LOGIN="${TOLOKA_LOGIN:-Saunhung}"
TOLOKA_PASS="${TOLOKA_PASS:-saunhung}"
RUTRACKER_COOKIES="${RUTRACKER_COOKIES:-}"
TOLOKA_COOKIES="${TOLOKA_COOKIES:-}"
FLARESOLVERR_URL="${FLARESOLVERR_URL:-}"
JACKETT_EXTERNAL="${JACKETT_EXTERNAL:-0}"
JACKETT_PASSWORD="${JACKETT_PASSWORD:-}"
JACKETT_SELFTEST="${JACKETT_SELFTEST:-0}"
SKIP_INDEXERS="${SKIP_INDEXERS:-}"

API="http://127.0.0.1:${JACKETT_PORT}/api/v2.0"
TMP="${TMPDIR:-/tmp}/jackett-setup-$$"
COOKIE_JAR="$TMP/cookies.txt"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

command -v curl >/dev/null 2>&1 || { echo "Lỗi: thiếu 'curl'."; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "Lỗi: thiếu 'tar'."; exit 1; }

# Mở khóa web UI: lấy session cookie (bắt buộc với API indexers/config)
bootstrap_session() {
  curl -sL -c "$COOKIE_JAR" -o /dev/null "http://127.0.0.1:${JACKETT_PORT}/"
}

# ------------------- Cài binary -------------------
install_jackett() {
  [ -x "$JACKETT_DIR/jackett" ] && return 0
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|amd64) ASSET="Jackett.Binaries.LinuxAMDx64.tar.gz" ;;
    aarch64|arm64) ASSET="Jackett.Binaries.LinuxARM64.tar.gz" ;;
    armv7l|armv8l|arm) ASSET="Jackett.Binaries.LinuxARM32.tar.gz" ;;
    *) echo "Không hỗ trợ kiến trúc: $ARCH"; exit 1 ;;
  esac
  echo "==> Tải Jackett ($ASSET)..."
  mkdir -p "$JACKETT_DIR"
  curl -sL -o "$TMP/jackett.tar.gz" \
    "https://github.com/Jackett/Jackett/releases/latest/download/$ASSET" \
  || { echo "    Tải thất bại — kiểm tra mạng."; exit 1; }
  tar xzf "$TMP/jackett.tar.gz" -C "$JACKETT_DIR" --strip-components=1 \
  || { echo "    Giải nén thất bại."; exit 1; }
  chmod +x "$JACKETT_DIR/jackett" 2>/dev/null || true
  echo "    Đã cài vào $JACKETT_DIR"
}

# ------------------- Chạy -------------------
# Khởi động Jackett theo cách phù hợp.
# Termux: Jackett là binary .NET/glibc. KHÔNG chạy qua `grun` trực tiếp
# (nó exec qua ld.so làm .NET tìm nhầm jackett.dll trong $PREFIX/glibc/lib).
# Đúng cách: `grun --configure` = patchelf interpreter+rpath, rồi chạy thẳng.
launch_jackett() {
  mkdir -p "$JACKETT_DIR"
  pkill -f "jackett --DataFolder $JACKETT_DIR" 2>/dev/null || true
  RUN=$(command -v grun 2>/dev/null || command -v glibc-runner 2>/dev/null || true)
  if [ -n "$RUN" ]; then
    echo "    Termux: patch ELF bằng grun --configure (cần patchelf)..."
    # VÌ SAO "THIẾU ICU" DÙ ĐÃ CÀI libicu-glibc:
    # Chạy thẳng binary đã patch (không qua grun) → LD_LIBRARY_PATH không có
    # $PREFIX/glibc/lib → dlopen("libicuuc.so.78") của .NET không tìm ra ICU
    # (lib glibc KHÔNG nằm trong ld cache của Termux — cache chỉ có lib bionic).
    # → Bắt buộc cấp LD_LIBRARY_PATH cho tiến trình jackett.
    # QUAN TRỌNG: đặt biến làm TIỀN TỐ trước lệnh nohup (chỉ áp cho jackett),
    # TUYỆT ĐỐI không `export` — export sẽ làm mọi lệnh bionic chạy sau đó
    # (sleep/curl/sed/rm/pkg...) dò nhầm $PREFIX/glibc/lib/libc.so — file đó là
    # GNU linker-script (text, magic "/* G" = 2f2a2047), không phải ELF →
    # "CANNOT LINK EXECUTABLE ... bad ELF magic: 2f2a2047".
    # (KHÔNG dùng DOTNET_SYSTEM_GLOBALIZATION_INVARIANT: Jackett v0.24 chết vì
    #  CultureNotFoundException — 'en-US' is an invalid culture identifier.)
    if "$RUN" --configure "$JACKETT_DIR/jackett" >/dev/null 2>&1; then
      # BẮT BUỘC: Termux set LD_PRELOAD=$PREFIX/lib/libtermux-exec.so (bionic).
      # Glibc loader preload nó → nó đòi libc.so (bionic) → resolve ra linker-script
      # $PREFIX/glibc/lib/libc.so → "invalid ELF header". grun tự unset LD_PRELOAD,
      # nên chạy thẳng ta cũng phải unset.
      unset LD_PRELOAD
      if [ -n "${PREFIX:-}" ]; then
        LD_LIBRARY_PATH="$PREFIX/glibc/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" nohup \
          "$JACKETT_DIR/jackett" --DataFolder "$JACKETT_DIR" --Port "$JACKETT_PORT" --NoUpdates $EXTRA \
          > "$JACKETT_DIR/jackett.log" 2>&1 &
      else
        nohup "$JACKETT_DIR/jackett" --DataFolder "$JACKETT_DIR" --Port "$JACKETT_PORT" --NoUpdates $EXTRA \
          > "$JACKETT_DIR/jackett.log" 2>&1 &
      fi
    else
      echo "    ⚠️  grun --configure thất bại — cài patchelf rồi chạy lại:"
      echo "       pkg install -y patchelf && sh $0"
      nohup "$RUN" "$JACKETT_DIR/jackett" --DataFolder "$JACKETT_DIR" --Port "$JACKETT_PORT" --NoUpdates $EXTRA \
        > "$JACKETT_DIR/jackett.log" 2>&1 &
    fi
  else
    nohup "$JACKETT_DIR/jackett" --DataFolder "$JACKETT_DIR" --Port "$JACKETT_PORT" --NoUpdates $EXTRA \
      > "$JACKETT_DIR/jackett.log" 2>&1 &
  fi
}

start_jackett() {
  if curl -sf -o /dev/null "http://127.0.0.1:${JACKETT_PORT}/"; then
    echo "==> Jackett đã đang chạy ở cổng $JACKETT_PORT"
    return 0
  fi

  # Termux: Jackett là binary .NET/glibc → bắt buộc có glibc-runner (lệnh grun)
  if [ -n "${PREFIX:-}" ] && ! command -v grun >/dev/null 2>&1 && ! command -v glibc-runner >/dev/null 2>&1; then
    echo "    ⚠️  Đang chạy trong Termux nhưng thiếu glibc-runner (Jackett là binary .NET/glibc)."
    echo "       Cài termux-glibc trước:"
    echo "       pkg install -y glibc-repo"
    echo "       pkg update -y"
    echo "       pkg install -y glibc-runner"
    echo "       Rồi chạy lại: sh $0"
    exit 1
  fi

  EXTRA=""
  [ "$JACKETT_EXTERNAL" = "1" ] && EXTRA=" --ListenPublic true"

  if [ -d /run/systemd/system ] && [ "$(id -u)" = "0" ] 2>/dev/null; then
    echo "==> Tạo systemd service jackett (cổng $JACKETT_PORT)"
    cat > /etc/systemd/system/jackett.service <<EOF
[Unit]
Description=Jackett
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${JACKETT_DIR}/jackett --DataFolder ${JACKETT_DIR} --Port ${JACKETT_PORT}${EXTRA}
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable jackett >/dev/null 2>&1 || true
    systemctl restart jackett
    [ "$JACKETT_EXTERNAL" = "1" ] && {
      command -v ufw >/dev/null 2>&1 && ufw allow "${JACKETT_PORT}/tcp" >/dev/null 2>&1 || true
      command -v firewall-cmd >/dev/null 2>&1 && { firewall-cmd --permanent --add-port=${JACKETT_PORT}/tcp >/dev/null 2>&1 || true; firewall-cmd --reload >/dev/null 2>&1 || true; }
    }
  else
    echo "==> Chạy Jackett nền (nohup) — log: $JACKETT_DIR/jackett.log"
    launch_jackett
  fi

  # Chờ web UI sẵn sàng. Trên Termux nếu thiếu ICU bản glibc → tự cài rồi
  # khởi động lại 1 lần (không bắt người dùng gõ tay nữa).
  icu_tried=0
  while :; do
    ready=0
    i=0
    while [ "$i" -lt 90 ]; do
      if curl -sf -o /dev/null "http://127.0.0.1:${JACKETT_PORT}/"; then
        ready=1
        break
      fi
      sleep 1
      i=$((i + 1))
    done
    [ "$ready" -eq 1 ] && break

    if [ -n "${PREFIX:-}" ] && [ "$icu_tried" -eq 0 ] \
      && grep -q "ICU\|libicu" "$JACKETT_DIR/jackett.log" 2>/dev/null; then
      icu_tried=1
      echo ""
      echo "    ⚠️  Thiếu ICU bản glibc — đang tự cài libicu-glibc openssl-glibc..."
      pkg install -y libicu-glibc openssl-glibc 2>/dev/null \
        && echo "    Đã cài xong — khởi động lại Jackett..." \
        || echo "    pkg install thất bại — tự cài tay: pkg install -y libicu-glibc openssl-glibc"
      launch_jackett
      continue
    fi

    echo "    Jackett không kịp mở cổng $JACKETT_PORT — 15 dòng log cuối:"
    tail -15 "$JACKETT_DIR/jackett.log" 2>/dev/null | sed 's/^/      /'
    if [ -n "${PREFIX:-}" ] && grep -q "invalid ELF header\|libc.so" "$JACKETT_DIR/jackett.log" 2>/dev/null; then
      echo ""
      echo "    Lỗi ELF header → do LD_PRELOAD (bionic) còn sót. Thử:"
      echo "      export LD_PRELOAD= && sh $0"
    elif [ -n "${PREFIX:-}" ] && grep -q "ICU\|libicu" "$JACKETT_DIR/jackett.log" 2>/dev/null; then
      echo ""
      echo "    Vẫn thiếu ICU — cài tay rồi chạy lại:"
      echo "      pkg install -y libicu-glibc openssl-glibc && sh $0"
    else
      echo ""
      echo "    (Linux thường thiếu libicu: apt install -y libicu74 / dnf install -y libicu)"
    fi
    exit 1
  done
  echo "    Jackett sẵn sàng: http://localhost:${JACKETT_PORT}"
}

# ------------------- API key -------------------
get_api_key() {
  KEY=""
  i=0
  while [ "$i" -lt 30 ]; do
    if [ -f "$JACKETT_DIR/ServerConfig.json" ]; then
      KEY=$(grep -oiE '"api_?key"[[:space:]]*:[[:space:]]*"[^"]+"' "$JACKETT_DIR/ServerConfig.json" | head -1 | sed -E 's/.*:[[:space:]]*"//; s/"$//')
      [ -n "$KEY" ] && break
    fi
    sleep 1
    i=$((i + 1))
  done
  if [ -z "$KEY" ]; then
    echo "    Không đọc được API key trong $JACKETT_DIR/ServerConfig.json"
    exit 1
  fi
  echo "$KEY"
}

# ------------------- Server config -------------------
set_flaresolverr() {
  url="$1"
  echo "==> Cấu hình FlareSolverr: $url"
  curl -s -b "$COOKIE_JAR" "$API/server/config?apikey=$API_KEY" -o "$TMP/server-config.json" || true
  if ! grep -q '"flaresolverrurl"' "$TMP/server-config.json" 2>/dev/null; then
    sed -i 's|"proxy_type"|"flaresolverrurl":"'"$url"'","flaresolverr_maxtimeout":60000,"proxy_type"|' "$TMP/server-config.json"
  else
    sed -i 's|"flaresolverrurl":[^,]*|"flaresolverrurl":"'"$url"'"|' "$TMP/server-config.json"
    sed -i 's|"flaresolverr_maxtimeout":[^,]*|"flaresolverr_maxtimeout":60000|' "$TMP/server-config.json"
  fi
  # POST toàn bộ config (đổi flaresolverr làm Jackett tự restart webhost)
  curl -s -b "$COOKIE_JAR" -X POST -H 'Content-Type: application/json' \
    --data-binary "@$TMP/server-config.json" "$API/server/config?apikey=$API_KEY" -o /dev/null
  sleep 3
  i=0
  while [ "$i" -lt 60 ]; do
    curl -sf -o /dev/null "http://127.0.0.1:${JACKETT_PORT}/" && break
    sleep 1
    i=$((i + 1))
  done
  # sau restart cookie cũ có thể hết hạn → lấy lại
  bootstrap_session
  if grep -q "$url" "$JACKETT_DIR/ServerConfig.json" 2>/dev/null; then
    echo "    Đã lưu (Jackett tự restart nếu cần)."
  else
    echo "    ⚠️  Chưa ghi được FlareSolverrUrl — dán thủ công: Dashboard → Admin → FlareSolverr API URL."
  fi
}

set_admin_password() {
  echo "==> Đặt mật khẩu admin cho web UI"
  printf '"%s"' "$JACKETT_PASSWORD" > "$TMP/admin-pass.json"
  curl -s -b "$COOKIE_JAR" -X POST -H 'Content-Type: application/json' \
    --data-binary "@$TMP/admin-pass.json" "$API/server/AdminPassword?apikey=$API_KEY" -o /dev/null
  echo "    OK"
}

# ------------------- Cấu hình indexer -------------------
# Lấy danh sách field id trong config của indexer (mỗi dòng một id)
config_field_ids() {
  grep -oE '"id":"[^"]+"' "$1" | sed 's/"id":"//; s/"$//' | sort -u
}

configure_indexer() {
  id="$1"; login="$2"; pass="$3"; cookies="${4:-}"
  for s in $SKIP_INDEXERS; do
    [ "$s" = "$id" ] && { echo ""; echo "==> BỎ QUA indexer: $id (SKIP_INDEXERS)"; return 0; }
  done
  echo ""
  echo "==> Cấu hình indexer: $id"

  if ! curl -s -b "$COOKIE_JAR" "$API/indexers?apikey=$API_KEY" | grep -q "\"id\":\"$id\""; then
    echo "    BỎ QUA: Jackett này không có indexer '$id' (bản cũ? đổi tên?)."
    return 0
  fi

  curl -s -b "$COOKIE_JAR" "$API/indexers/$id/Config?apikey=$API_KEY" -o "$TMP/config-$id.json"
  if [ ! -s "$TMP/config-$id.json" ]; then
    echo "    Không lấy được config fields — bỏ qua."
    return 0
  fi

  # Xây payload: chỉ gửi các field có thật trong config
  ids=$(config_field_ids "$TMP/config-$id.json")
  n=0
  : > "$TMP/payload-$id.json"
  printf '[' > "$TMP/payload-$id.json"
  for f in $ids; do
    v=""
    case "$f" in
      username|login|user)    v="$login" ;;
      password|pass)          v="$pass" ;;
      cookie)                 v="$cookies" ;;
    esac
    [ -z "$v" ] && continue
    # escape JSON
    ev=$(printf '%s' "$v" | sed 's/\\/\\\\/g; s/"/\\"/g')
    [ "$n" -gt 0 ] && printf ',' >> "$TMP/payload-$id.json"
    printf '{"id":"%s","value":"%s"}' "$f" "$ev" >> "$TMP/payload-$id.json"
    n=$((n + 1))
  done
  printf ']\n' >> "$TMP/payload-$id.json"

  if [ "$n" -eq 0 ]; then
    # Indexer công khai: gửi lại nguyên config mặc định để đánh dấu "configured"
    code=$(curl -s -b "$COOKIE_JAR" -o "$TMP/resp-$id.txt" -w '%{http_code}' -X POST \
      -H 'Content-Type: application/json' --data-binary "@$TMP/config-$id.json" \
      "$API/indexers/$id/Config?apikey=$API_KEY")
    echo "    Indexer công khai (không cần tài khoản) — HTTP $code"
  else
    code=$(curl -s -b "$COOKIE_JAR" -o "$TMP/resp-$id.txt" -w '%{http_code}' -X POST \
      -H 'Content-Type: application/json' --data-binary "@$TMP/payload-$id.json" \
      "$API/indexers/$id/Config?apikey=$API_KEY")
    if [ "$code" = "204" ] || [ "$code" = "200" ]; then
      echo "    Lưu config OK (HTTP $code)"
    else
      echo "    Lưu config LỖI (HTTP $code):"
      head -c 400 "$TMP/resp-$id.txt" | sed 's/^/      /'
      echo ""
    fi
  fi

  # Test indexer
  tcode=$(curl -s -b "$COOKIE_JAR" -o "$TMP/test-$id.txt" -w '%{http_code}' -X POST \
    "$API/indexers/$id/Test?apikey=$API_KEY")
  if [ "$tcode" = "204" ]; then
    echo "    TEST OK ✅ — indexer hoạt động"
  else
    echo "    TEST LỖI (HTTP $tcode):"
    head -c 400 "$TMP/test-$id.txt" | sed 's/^/      /'
    echo ""
    if grep -q 'Challenge\|FlareSolverr' "$TMP/test-$id.txt" 2>/dev/null && [ -z "$FLARESOLVERR_URL" ]; then
      echo ""
      echo "    ⚠️  $id bị Cloudflare chặn từ IP datacenter (đúng như thông báo lỗi)."
      echo "       Fix bằng 1 trong 2 cách (chi tiết ở đầu file này):"
      echo "       1) chạy FlareSolverr rồi:  FLARESOLVERR_URL=http://127.0.0.1:8191 sh $0"
      echo "       2) dán cookie trình duyệt:  RUTRACKER_COOKIES='bb_session=...; bb_lastvisit=...' sh $0"
    fi
  fi
}

# ------------------- Self-test tìm kiếm rutracker -------------------
selftest_rutracker() {
  echo ""
  echo "==> Self-test: tìm 'test' trên rutracker"
  curl -s -b "$COOKIE_JAR" "$API/indexers/rutracker/results?apikey=$API_KEY&Query=test" \
    -o "$TMP/search-rutracker.json"
  items=$(grep -oE '"Title":"' "$TMP/search-rutracker.json" | wc -l | tr -d ' ')
  if [ "${items:-0}" -gt 0 ]; then
    echo "    TÌM THẤY $items kết quả ✅ — rutracker hoạt động!"
  else
    echo "    Không có kết quả (0 item) — thường do Cloudflare/đăng nhập. Phản hồi:"
    head -c 400 "$TMP/search-rutracker.json" | sed 's/^/      /'
    echo ""
  fi
}

# ------------------- Tắt tạm indexer -------------------
disable_indexers() {
  echo "==> Tắt tạm indexer: $*"
  for id in "$@"; do
    code=$(curl -s -b "$COOKIE_JAR" -o /dev/null -w '%{http_code}' -X DELETE \
      "$API/indexers/$id?apikey=$API_KEY")
    if [ "$code" = "204" ] || [ "$code" = "200" ]; then
      echo "    $id → đã tắt ✅ (không còn trong tìm kiếm tổng)"
    else
      echo "    $id → HTTP $code (id sai? xem danh sách: curl .../api/v2.0/indexers)"
    fi
  done
  echo "  Bật lại: chạy lại 'sh $0' (cấu hình lại indexer)."
}

# ------------------- Đo tốc độ từng indexer -------------------
speedtest() {
  q="${1:-matrix}"
  echo "==> Đo tốc độ search '${q}' trên từng indexer đã cấu hình..."
  echo ""
  ids=$(curl -s -b "$COOKIE_JAR" "$API/indexers?configured=true&apikey=$API_KEY" \
    | grep -oE '"id":"[^"]+"' | sed 's/"id":"//; s/"$//')
  [ -z "$ids" ] && ids="__none__"
  rows=""
  for id in $ids; do
    [ "$id" = "__none__" ] && break
    out=$(curl -s -b "$COOKIE_JAR" -o "$TMP/sp-$id.json" -w '%{http_code} %{time_total}' \
      "$API/indexers/$id/results?apikey=$API_KEY&Query=$q")
    code=${out% *}; t=${out#* }
    items=$(grep -oE '"Title":"' "$TMP/sp-$id.json" 2>/dev/null | wc -l | tr -d ' ')
    st="ok"
    [ "$code" != "200" ] && st="HTTP $code"
    [ "$items" = "0" ] && st="$st (0 kết quả)"
    rows="$rows$id\t$t\t$items\t$st\n"
  done
  out=$(curl -s -b "$COOKIE_JAR" -o "$TMP/sp-all.json" -w '%{http_code} %{time_total}' \
    "$API/indexers/all/results?apikey=$API_KEY&Query=$q")
  code=${out% *}; t=${out#* }
  items=$(grep -oE '"Title":"' "$TMP/sp-all.json" 2>/dev/null | wc -l | tr -d ' ')
  rows="${rows}TỔNG(all)\t$t\t$items\t\n"
  printf '%b' "$rows" | sort -t"$(printf '\t')" -k2 -n | awk -F"$(printf '\t')" '
    { printf "  %-14s %6ss  %5s kết quả  %s\n", $1, $2, $3, $4 }
  '
  echo ""
  echo "  → Jackett search song song tất cả nguồn; nguồn chậm nhất quyết định"
  echo "    thời gian trả kết quả (TỔNG). Nguồn nào chậm/0 kết quả thì tắt:"
  echo "    sh $0 disable <id>"
  echo "  (Lần chạy lại với cùng từ khóa có thể nhanh hơn do Jackett cache.)"
}

# ------------------- Tự tinh chỉnh: tắt nguồn lỗi/chậm -------------------
# Jackett search song song nhưng PHẢI chờ nguồn chậm nhất — từ IP datacenter
# (VPS), rutracker/1337x đứng sau Cloudflare thường treo tới 100s (timeout mặc
# định của Jackett, không chỉnh được) → search nào cũng timeout. Cách duy nhất
# hiệu quả: tắt mấy nguồn đó đi. Lệnh này tự đo + tự tắt, chỉ giữ nguồn nhanh.
tune() {
  MAX="${MAX_SECONDS:-30}"
  echo "==> Tune: tự tắt nguồn lỗi/chậm (quá ${MAX}s) trên máy này..."
  if [ "$#" -ge 1 ]; then
    echo "    Tắt trước theo yêu cầu: $*"
    disable_indexers "$@"
  fi
  ids=$(curl -s -b "$COOKIE_JAR" "$API/indexers?configured=true&apikey=$API_KEY" \
    | grep -oE '"id":"[^"]+"' | sed 's/"id":"//; s/"$//')
  [ -z "$ids" ] && ids="__none__"
  echo ""
  echo "    Đo từng nguồn (từ khóa 'matrix')..."
  drop=""
  keep=""
  for id in $ids; do
    [ "$id" = "__none__" ] && { echo "    Không có indexer nào được cấu hình — chạy 'sh $0' trước."; return 0; }
    printf '    - %-14s ' "$id"
    # --max-time 115: Jackett tự có timeout ~100s/nguồn; đề phòng treo thì cắt sớm
    out=$(curl -s --max-time 115 -b "$COOKIE_JAR" -o "$TMP/tu-$id.json" -w '%{http_code} %{time_total}' \
      "$API/indexers/$id/results?apikey=$API_KEY&Query=matrix")
    code=${out% *}; t=${out#* }
    items=$(grep -oE '"Title":"' "$TMP/tu-$id.json" 2>/dev/null | wc -l | tr -d ' ')
    bad=""
    [ "$code" != "200" ] && bad="HTTP $code"
    if [ -z "$bad" ] && [ "${items:-0}" -eq 0 ]; then bad="0 kết quả"; fi
    if [ -z "$bad" ]; then
      slow=$(awk -v t="$t" -v m="$MAX" 'BEGIN{print (t+0 > m+0) ? 1 : 0}')
      [ "$slow" = "1" ] && bad="chậm ${t}s (>${MAX}s)"
    fi
    printf '%ss / %s kết quả\n' "$t" "$items"
    if [ -n "$bad" ]; then
      disable_indexers "$id"
      drop="$drop $id($bad)"
    else
      keep="$keep $id"
    fi
  done
  echo ""
  echo "    GIỮ LẠI (nhanh, có kết quả):$keep"
  echo "    ĐÃ TẮT (lỗi/chậm):$drop"
  echo "  Từ giờ search tổng chỉ còn nguồn nhanh — hết timeout."
  echo "  Muốn thử lại nguồn đã tắt: chạy lại 'sh $0' (cấu hình lại hết indexer)."
  echo ""
  echo "==> Kiểm chứng lại sau khi tắt:"
  speedtest "${TUNE_QUERY:-matrix}"
}

# ------------------- Điều khiển -------------------
configure_all() {
  bootstrap_session
  API_KEY=$(get_api_key)
  echo "API key: $API_KEY"

  [ -n "$FLARESOLVERR_URL" ] && set_flaresolverr "$FLARESOLVERR_URL"
  [ -n "$JACKETT_PASSWORD" ] && set_admin_password

  configure_indexer "rutracker"      "$RUTRACKER_LOGIN" "$RUTRACKER_PASS" "$RUTRACKER_COOKIES"
  configure_indexer "toloka"         "$TOLOKA_LOGIN"    "$TOLOKA_PASS"    "$TOLOKA_COOKIES"
  configure_indexer "rutor"          "" "" ""
  configure_indexer "1337x"          "" "" ""
  configure_indexer "thepiratebay"   "" "" ""

  [ "$JACKETT_SELFTEST" = "1" ] && selftest_rutracker

  echo ""
  echo "======================================================="
  echo "  Jackett:          http://localhost:${JACKETT_PORT}"
  echo "  API key:          $API_KEY"
  echo "  Torznab (Sonarr/Radarr):"
  echo "    http://<IP>:${JACKETT_PORT}/api/v2.0/indexers/all/results/torznab/?apikey=$API_KEY"
  echo ""
  echo "  Cách xài: search trên web UI → copy magnet hoặc tải .torrent"
  echo "  rồi thêm vào TorrServer:  sh jackett-add.sh '<link>'"
  echo "  (Thêm indexer RU khác trong UI: kinozal, nnm-club, ...)"
  echo "======================================================="
}

case "${1:-}" in
  configure)
    start_jackett
    configure_all
    ;;
  start)
    start_jackett
    ;;
  stop)
    pkill -f "jackett --DataFolder $JACKETT_DIR" 2>/dev/null || true
    echo "Jackett đã tắt (nếu đang chạy)."
    ;;
  disable)
    shift
    [ "$#" -ge 1 ] || { echo "Cách dùng: sh $0 disable <id> [id...]  (vd: disable rutracker 1337x)"; exit 1; }
    start_jackett
    bootstrap_session
    API_KEY=$(get_api_key)
    disable_indexers "$@"
    ;;
  speedtest)
    start_jackett
    bootstrap_session
    API_KEY=$(get_api_key)
    speedtest "${2:-matrix}"
    ;;
  tune)
    shift
    start_jackett
    bootstrap_session
    API_KEY=$(get_api_key)
    tune "$@"
    ;;
  *)
    install_jackett
    start_jackett
    configure_all
    [ "${TUNE:-0}" = "1" ] && { echo ""; tune; }
    ;;
esac
