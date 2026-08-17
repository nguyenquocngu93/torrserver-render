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
#    sh jackett-setup.sh proot            Termux: chạy Jackett trong proot-distro Debian
#                                         (userspace Linux thật — hết lỗi ICU/glibc).
#                                         Cài distro + Jackett + cấu hình indexer.
#    sh jackett-setup.sh proot start|stop|status   điều khiển bản proot
#    sh jackett-setup.sh sonarr           Termux: cài Sonarr trong proot-distro Debian
#                                         (cùng container với Jackett). Sonarr = quản lý
#                                         phim bộ: theo dõi series, tự tìm nguồn qua
#                                         Jackett Torznab. Điều khiển từ app nzb360.
#    sh jackett-setup.sh sonarr start|stop|status   điều khiển Sonarr
#    sh jackett-setup.sh radarr            Termux: cài Radarr trong proot-distro Debian
#                                         (phim lẻ — Sonarr là phim bộ). nzb360
#                                         quản lý được cả hai.
#    sh jackett-setup.sh radarr start|stop|status   điều khiển Radarr
#    sh jackett-setup.sh start-all         Termux: khởi động LẠI toàn bộ bản proot
#                                         (Jackett + Sonarr + Radarr) sau khi Termux
#                                         bị đóng hẳn. API key KHÔNG đổi khi restart.
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
#    PROOT_DISTRO          distro dùng cho lệnh proot (mặc định debian)
#    JACKETT_GC_LIMIT       giới hạn heap .NET cho bản proot (mặc định
#                          0x20000000 = 512MB; máy RAM lớn muốn nhồi nhiều
#                          indexer thì tăng: JACKETT_GC_LIMIT=0x40000000)
#    SONARR_PORT            cổng web UI Sonarr (mặc định 8989)
#    SONARR_GC_LIMIT        giới hạn heap .NET cho Sonarr (mặc định 0x20000000)
#    RADARR_PORT            cổng web UI Radarr (mặc định 7878)
#    RADARR_GC_LIMIT        giới hạn heap .NET cho Radarr (mặc định 0x20000000)
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
    # QUAN TRỌNG (2 cấm kỵ với Termux/bionic):
    #  1) KHÔNG `export` vào shell — mọi lệnh bionic chạy sau đó (sleep/curl/
    #     sed/rm/pkg...) dò nhầm $PREFIX/glibc/lib/libc.so — file đó là GNU
    #     linker-script (text, magic "/* G" = 2f2a2047), không phải ELF →
    #     "CANNOT LINK EXECUTABLE ... bad ELF magic: 2f2a2047".
    #  2) KHÔNG đặt biến làm tiền tố trước `nohup` — chính nohup (bionic) sẽ
    #     load nhầm libc.so glibc → "CANNOT LINK EXECUTABLE nohup".
    # → Cách đúng: chạy qua `sh -c` — nohup/sh chạy với env SẠCH, chỉ tiến
    #   trình jackett (exec cuối) nhận LD_LIBRARY_PATH.
    # (KHÔNG dùng DOTNET_SYSTEM_GLOBALIZATION_INVARIANT: Jackett v0.24 chết vì
    #  CultureNotFoundException — 'en-US' is an invalid culture identifier.)
    if "$RUN" --configure "$JACKETT_DIR/jackett" >/dev/null 2>&1; then
      # BẮT BUỘC: Termux set LD_PRELOAD=$PREFIX/lib/libtermux-exec.so (bionic).
      # Glibc loader preload nó → nó đòi libc.so (bionic) → resolve ra linker-script
      # $PREFIX/glibc/lib/libc.so → "invalid ELF header". grun tự unset LD_PRELOAD,
      # nên chạy thẳng ta cũng phải unset.
      unset LD_PRELOAD
      if [ -n "${PREFIX:-}" ]; then
        # chống trường hợp shell ngoài đã bị bẩn LD_LIBRARY_PATH (chạy lại sau
        # lỗi cũ) — nohup/sh phải chạy với env sạch
        unset LD_LIBRARY_PATH
        nohup sh -c 'export LD_LIBRARY_PATH="$1"; shift; exe="$1"; shift; exec "$exe" "$@"' \
          sh "$PREFIX/glibc/lib" "$JACKETT_DIR/jackett" \
          --DataFolder "$JACKETT_DIR" --Port "$JACKETT_PORT" --NoUpdates $EXTRA \
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
    if [ -n "${PREFIX:-}" ] && grep -q "bad ELF magic\|CANNOT LINK" "$JACKETT_DIR/jackett.log" 2>/dev/null; then
      echo ""
      echo "    Lỗi linker bionic dò nhầm lib glibc → LD_LIBRARY_PATH đang bị set."
      echo "    Sửa: unset LD_LIBRARY_PATH && sh $0"
    elif [ -n "${PREFIX:-}" ] && grep -q "invalid ELF header\|libc.so" "$JACKETT_DIR/jackett.log" 2>/dev/null; then
      echo ""
      echo "    Lỗi ELF header → do LD_PRELOAD (bionic) còn sót. Thử:"
      echo "      export LD_PRELOAD= && sh $0"
    elif [ -n "${PREFIX:-}" ] && grep -q "ICU\|libicu" "$JACKETT_DIR/jackett.log" 2>/dev/null; then
      echo ""
      echo "    Vẫn thiếu ICU — native đã thử đủ cách, chuyển hẳn sang proot:"
      echo "      sh $0 proot"
      echo "    (Jackett chạy trong Debian thật — .NET tự tìm ICU, hết đau đầu.)"
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

# ------------------- Proot-distro (Termux: chạy Jackett trong Linux thật) -------------------
# Bản native chạy Jackett (.NET/glibc) trên Termux phải qua grun + LD_LIBRARY_PATH —
# mỏng manh: .NET dlopen ICU thất bại là FailFast "Couldn't find a valid ICU", còn
# linker bionic dễ dò nhầm lib glibc. Cách chắc ăn: chạy Jackett BÊN TRONG proot-distro
# (Debian) — userspace Linux thật, .NET tự tìm ICU của Debian qua ldconfig, không hack
# gì. Phần còn lại (TorrServer...) vẫn chạy native bình thường.
#   sh jackett-setup.sh proot              cài distro + Jackett + cấu hình indexer
#   sh jackett-setup.sh proot start        chỉ khởi động lại
#   sh jackett-setup.sh proot stop         tắt
#   sh jackett-setup.sh proot status       kiểm tra
# Cần ~1GB trống (rootfs ~500MB). Distro mặc định: debian (đổi: PROOT_DISTRO=ubuntu).
#
# proot-distro 5.6+ (bản viết lại bằng Python) đổi 2 thứ quan trọng:
#   - install: cần Docker image reference ("debian:stable"), KHÔNG còn nhận --no-color;
#     thêm -n để đặt tên container cố định (tránh phụ thuộc cách suy tên).
#   - rootfs:  $PREFIX/var/lib/proot-distro/containers/<tên>/rootfs
#     (bản cũ: installed-rootfs/<tên>)
# Script tự phát hiện version và dùng đúng cú pháp/đường dẫn cho cả 2 bản.
PROOT_DISTRO="${PROOT_DISTRO:-debian}"

# Phát hiện version + đường dẫn rootfs (gọi lại sau khi cài proot-distro vì
# lúc chạy đầu tiên lệnh này có thể chưa tồn tại).
proot_detect() {
  pd_major=0; pd_minor=0
  # chú ý: banner version của proot-distro in ra stderr, không được bỏ 2>&1
  _pd_ver=$(proot-distro 2>&1 | grep -oE "version '?[0-9]+\.[0-9]+" | head -1 | tr -dc '0-9.')
  case "$_pd_ver" in
    [0-9]*.[0-9]*)
      pd_major=${_pd_ver%%.*}
      pd_minor=${_pd_ver#*.}; pd_minor=${pd_minor%%.*}
      ;;
  esac
  PD_NEW=0
  if [ "$pd_major" -gt 5 ] || { [ "$pd_major" -eq 5 ] && [ "$pd_minor" -ge 6 ]; }; then
    PD_NEW=1
    PD_ROOTFS="${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/containers/$PROOT_DISTRO/rootfs"
  else
    PD_ROOTFS="${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/installed-rootfs/$PROOT_DISTRO"
  fi
  PROOT_HOST_DIR="$PD_ROOTFS/root/jackett"
}
proot_detect

proot_ensure_distro() {
  command -v proot-distro >/dev/null 2>&1 || {
    echo "==> Cài proot-distro..."
    pkg install -y proot-distro || { echo "    Lỗi cài proot-distro — kiểm tra mạng."; exit 1; }
    proot_detect
  }
  if [ ! -d "$PD_ROOTFS" ]; then
    echo "==> Cài distro $PROOT_DISTRO (tải rootfs ~500MB — chờ 2-5 phút)..."
    if [ "$PD_NEW" = "1" ]; then
      case "$PROOT_DISTRO" in
        debian) PD_IMAGE="debian:stable" ;;
        ubuntu) PD_IMAGE="ubuntu:24.04" ;;
        *) PD_IMAGE="$PROOT_DISTRO:latest" ;;
      esac
      echo "    (proot-distro 5.6+: proot-distro install -n $PROOT_DISTRO $PD_IMAGE)"
      proot-distro install -n "$PROOT_DISTRO" "$PD_IMAGE" \
        || { echo "    Lỗi cài distro — chạy lại 'sh $0 proot'."; exit 1; }
    else
      proot-distro --no-color install "$PROOT_DISTRO" \
        || { echo "    Lỗi cài distro — chạy lại 'sh $0 proot'."; exit 1; }
    fi
  fi
}

proot_setup_inside() {
  echo "==> Cài gói bên trong $PROOT_DISTRO (curl, ICU, ...)..."
  proot-distro login "$PROOT_DISTRO" -- bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -qq
    apt-get install -y -qq --no-install-recommends curl ca-certificates tar libicu-dev
  ' || { echo "    Lỗi cài gói bên trong distro."; exit 1; }
}

proot_install_jackett() {
  if proot-distro login "$PROOT_DISTRO" -- test -x /root/jackett/jackett; then
    echo "==> Jackett đã có sẵn trong $PROOT_DISTRO."
    return 0
  fi
  echo "==> Tải Jackett vào bên trong $PROOT_DISTRO..."
  proot-distro login "$PROOT_DISTRO" -- bash -c '
    set -e
    case "$(uname -m)" in
      x86_64|amd64) ASSET="Jackett.Binaries.LinuxAMDx64.tar.gz" ;;
      aarch64|arm64) ASSET="Jackett.Binaries.LinuxARM64.tar.gz" ;;
      armv7l|armv8l|arm) ASSET="Jackett.Binaries.LinuxARM32.tar.gz" ;;
      *) echo "Không hỗ trợ kiến trúc: $(uname -m)"; exit 1 ;;
    esac
    cd /tmp
    curl -sL -o jackett.tar.gz "https://github.com/Jackett/Jackett/releases/latest/download/$ASSET"
    mkdir -p /root/jackett
    tar xzf jackett.tar.gz -C /root/jackett --strip-components=1
    chmod +x /root/jackett/jackett
  ' || { echo "    Lỗi tải Jackett."; exit 1; }
}

proot_launch() {
  # dọn tiến trình cũ dùng chung cổng: jackett native + jackett trong proot
  pkill -f "jackett --DataFolder $JACKETT_DIR" 2>/dev/null || true
  pkill -f "proot-distro login $PROOT_DISTRO" 2>/dev/null || true
  sleep 1
  mkdir -p "$(dirname "$PROOT_HOST_DIR")"
  EXTRA=""
  [ "$JACKETT_EXTERNAL" = "1" ] && EXTRA=" --ListenPublic true"
  echo "==> Khởi động Jackett bên trong $PROOT_DISTRO (log: $PROOT_HOST_DIR/jackett.log)..."
  # QUAN TRỌNG: proot-distro phải là tiến trình nền từ phía HOST (nohup) — khi nó
  # thoát thì sandbox chết theo, nên không được chạy nền bên trong distro.
  #
  # Lỗi "GC heap initialization failed with error 0x8007000E" (E_OUTOFMEMORY):
  # .NET mặc định đo RAM theo /proc/meminfo rồi reserve heap rất lớn, server GC
  # lại tạo 1 heap/core → trên điện thoại reserve không nổi → CoreCLR chết ngay
  # lúc khởi động. Fix chuẩn: workstation GC (1 heap) + giới hạn heap cứng.
  # 512MB đủ cho Jackett; đổi qua JACKETT_GC_LIMIT (vd 0x40000000 = 1GB).
  nohup proot-distro login "$PROOT_DISTRO" -- env \
    DOTNET_gcServer=0 \
    DOTNET_GCHeapCount=1 \
    DOTNET_GCHeapHardLimit="${JACKETT_GC_LIMIT:-0x20000000}" \
    /root/jackett/jackett \
    --DataFolder /root/jackett --Port "$JACKETT_PORT" --NoUpdates $EXTRA \
    > "$PROOT_HOST_DIR/jackett.log" 2>&1 &
}

proot_wait_ready() {
  echo "    Chờ web UI cổng $JACKETT_PORT..."
  i=0
  while [ "$i" -lt 120 ]; do
    if curl -sf -o /dev/null "http://127.0.0.1:${JACKETT_PORT}/"; then
      echo "    Jackett sẵn sàng: http://localhost:${JACKETT_PORT}"
      return 0
    fi
    sleep 2
    i=$((i + 2))
  done
  echo "    Jackett không kịp mở cổng — 15 dòng log cuối:"
  tail -15 "$PROOT_HOST_DIR/jackett.log" 2>/dev/null | sed 's/^/      /'
  exit 1
}

# ------------------- Sonarr (Termux: chạy trong proot-distro, cùng container) -------------------
# Sonarr v4 là app .NET 6 — tarball KÈM SẴN runtime (self-contained, ~230MB giải nén),
# nhưng chạy native trên Termux sẽ dính đúng bệnh ICU/GC như Jackett → chạy trong
# Debian thật (proot). Tarball Sonarr có thư mục ngoài cùng là Sonarr/ → strip-components=1.
SONARR_PORT="${SONARR_PORT:-8989}"
SONARR_GC_LIMIT="${SONARR_GC_LIMIT:-0x20000000}"
SONARR_BIN="/root/sonarr/Sonarr"
SONARR_DATA="/root/sonarr-data"
SONARR_LOG_DIR="$PD_ROOTFS/root/sonarr"

sonarr_install_inside() {
  if proot-distro login "$PROOT_DISTRO" -- test -x "$SONARR_BIN"; then
    echo "==> Sonarr đã có sẵn trong $PROOT_DISTRO."
    return 0
  fi
  echo "==> Cài gói bên trong $PROOT_DISTRO..."
  proot-distro login "$PROOT_DISTRO" -- bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -qq
    apt-get install -y -qq --no-install-recommends curl ca-certificates tar libicu-dev
  ' || { echo "    Lỗi cài gói."; exit 1; }
  echo "==> Tải Sonarr vào bên trong $PROOT_DISTRO (~100MB)..."
  proot-distro login "$PROOT_DISTRO" -- bash -c '
    set -e
    case "$(uname -m)" in
      x86_64|amd64) ASSET="linux-x64" ;;
      aarch64|arm64) ASSET="linux-arm64" ;;
      *) echo "Không hỗ trợ kiến trúc: $(uname -m)"; exit 1 ;;
    esac
    VER=$(curl -sL https://api.github.com/repos/Sonarr/Sonarr/releases/latest | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -1)
    [ -z "$VER" ] && { echo "    Không lấy được version Sonarr."; exit 1; }
    cd /tmp
    curl -sL -o sonarr.tar.gz "https://github.com/Sonarr/Sonarr/releases/download/$VER/Sonarr.main.${VER#v}.$ASSET.tar.gz"
    mkdir -p /root/sonarr
    tar xzf sonarr.tar.gz -C /root/sonarr --strip-components=1
    chmod +x /root/sonarr/Sonarr
    echo "    Đã cài Sonarr $VER ($ASSET)"
  ' || { echo "    Lỗi tải Sonarr."; exit 1; }
}

sonarr_launch() {
  pkill -f "root/sonarr/Sonarr" 2>/dev/null || true
  sleep 1
  mkdir -p "$SONARR_LOG_DIR"
  echo "==> Khởi động Sonarr bên trong $PROOT_DISTRO (log: $SONARR_LOG_DIR/sonarr.log)..."
  # Cùng 3 biến GC đã fix lỗi 0x8007000E cho Jackett: workstation GC + giới hạn heap.
  nohup proot-distro login "$PROOT_DISTRO" -- env \
    DOTNET_gcServer=0 \
    DOTNET_GCHeapCount=1 \
    DOTNET_GCHeapHardLimit="$SONARR_GC_LIMIT" \
    "$SONARR_BIN" -data="$SONARR_DATA" \
    > "$SONARR_LOG_DIR/sonarr.log" 2>&1 &
}

sonarr_wait_ready() {
  echo "    Chờ web UI cổng $SONARR_PORT..."
  i=0
  while [ "$i" -lt 120 ]; do
    if curl -sf -o /dev/null "http://127.0.0.1:${SONARR_PORT}/ping"; then
      echo "    Sonarr sẵn sàng: http://localhost:${SONARR_PORT}"
      return 0
    fi
    sleep 2
    i=$((i + 2))
  done
  echo "    Sonarr không kịp mở cổng — 15 dòng log cuối:"
  tail -15 "$SONARR_LOG_DIR/sonarr.log" 2>/dev/null | sed 's/^/      /'
  exit 1
}

sonarr_show_info() {
  KEY=$(grep -oE '<ApiKey>[^<]+' "$PD_ROOTFS$SONARR_DATA/config.xml" 2>/dev/null | sed 's/<ApiKey>//')
  echo ""
  echo "======================================================="
  echo "  Sonarr:  http://localhost:${SONARR_PORT}"
  echo "  API key: ${KEY:-xem trong $SONARR_DATA/config.xml}"
  echo ""
  echo "  nzb360:  thêm Sonarr server -> http://localhost:${SONARR_PORT}"
  echo "           (cùng máy) hoặc http://<IP-máy>:${SONARR_PORT} (LAN)"
  echo ""
  echo "  Cần làm tiếp trong web UI:"
  echo "    1) Settings -> General -> đặt username/password (nếu muốn)"
  echo "    2) Settings -> Indexers -> add Jackett (Torznab) — thêm TỪNG indexer:"
  echo "       URL:      http://127.0.0.1:9117/api/v2.0/indexers/<id>/results/torznab"
  echo "       API Path: /api"
  echo "       API key:  <key Jackett — Dashboard web UI 9117>"
  echo "       <id> = rutracker, toloka, rutor, 1337x, thepiratebay"
  echo "    3) Download client: TorrServer KHÔNG hỗ trợ -> cần qBittorrent"
  echo "       (nói tôi, cài qBit trong proot luôn, 1 lệnh)"
  echo "======================================================="
}

# ------------------- Radarr (Termux: cùng proot-distro, phim lẻ) -------------------
# Radarr v6 = .NET 8, tarball tự kèm runtime (self-contained), cấu trúc giống Sonarr
# (thư mục ngoài cùng Radarr/). Chú ý: từ v6 asset đổi tên thành
# Radarr.master.<ver>.linux-core-<arch>.tar.gz.
RADARR_PORT="${RADARR_PORT:-7878}"
RADARR_GC_LIMIT="${RADARR_GC_LIMIT:-0x20000000}"
RADARR_BIN="/root/radarr/Radarr"
RADARR_DATA="/root/radarr-data"
RADARR_LOG_DIR="$PD_ROOTFS/root/radarr"

radarr_install_inside() {
  if proot-distro login "$PROOT_DISTRO" -- test -x "$RADARR_BIN"; then
    echo "==> Radarr đã có sẵn trong $PROOT_DISTRO."
    return 0
  fi
  echo "==> Cài gói bên trong $PROOT_DISTRO..."
  proot-distro login "$PROOT_DISTRO" -- bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -qq
    apt-get install -y -qq --no-install-recommends curl ca-certificates tar libicu-dev
  ' || { echo "    Lỗi cài gói."; exit 1; }
  echo "==> Tải Radarr vào bên trong $PROOT_DISTRO (~100MB)..."
  proot-distro login "$PROOT_DISTRO" -- bash -c '
    set -e
    case "$(uname -m)" in
      x86_64|amd64) ASSET="x64" ;;
      aarch64|arm64) ASSET="arm64" ;;
      *) echo "Không hỗ trợ kiến trúc: $(uname -m)"; exit 1 ;;
    esac
    VER=$(curl -sL https://api.github.com/repos/Radarr/Radarr/releases/latest | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -1)
    [ -z "$VER" ] && { echo "    Không lấy được version Radarr."; exit 1; }
    cd /tmp
    curl -sL -o radarr.tar.gz "https://github.com/Radarr/Radarr/releases/download/$VER/Radarr.master.${VER#v}.linux-core-$ASSET.tar.gz"
    mkdir -p /root/radarr
    tar xzf radarr.tar.gz -C /root/radarr --strip-components=1
    chmod +x /root/radarr/Radarr
    echo "    Đã cài Radarr $VER (linux-core-$ASSET)"
  ' || { echo "    Lỗi tải Radarr."; exit 1; }
}

radarr_launch() {
  pkill -f "root/radarr/Radarr" 2>/dev/null || true
  sleep 1
  mkdir -p "$RADARR_LOG_DIR"
  echo "==> Khởi động Radarr bên trong $PROOT_DISTRO (log: $RADARR_LOG_DIR/radarr.log)..."
  nohup proot-distro login "$PROOT_DISTRO" -- env \
    DOTNET_gcServer=0 \
    DOTNET_GCHeapCount=1 \
    DOTNET_GCHeapHardLimit="$RADARR_GC_LIMIT" \
    "$RADARR_BIN" -data="$RADARR_DATA" \
    > "$RADARR_LOG_DIR/radarr.log" 2>&1 &
}

radarr_wait_ready() {
  echo "    Chờ web UI cổng $RADARR_PORT..."
  i=0
  while [ "$i" -lt 120 ]; do
    if curl -sf -o /dev/null "http://127.0.0.1:${RADARR_PORT}/ping"; then
      echo "    Radarr sẵn sàng: http://localhost:${RADARR_PORT}"
      return 0
    fi
    sleep 2
    i=$((i + 2))
  done
  echo "    Radarr không kịp mở cổng — 15 dòng log cuối:"
  tail -15 "$RADARR_LOG_DIR/radarr.log" 2>/dev/null | sed 's/^/      /'
  exit 1
}

radarr_show_info() {
  KEY=$(grep -oE '<ApiKey>[^<]+' "$PD_ROOTFS$RADARR_DATA/config.xml" 2>/dev/null | sed 's/<ApiKey>//')
  echo ""
  echo "======================================================="
  echo "  Radarr:  http://localhost:${RADARR_PORT}"
  echo "  API key: ${KEY:-xem trong $RADARR_DATA/config.xml}"
  echo ""
  echo "  nzb360:  thêm Radarr server -> http://localhost:${RADARR_PORT}"
  echo "           (cùng máy) hoặc http://<IP-máy>:${RADARR_PORT} (LAN)"
  echo ""
  echo "  Cần làm tiếp trong web UI (giống Sonarr):"
  echo "    1) Settings -> Indexers -> add Jackett Torznab:"
  echo "       http://127.0.0.1:9117/api/v2.0/indexers/all/results/torznab/?apikey=<key-jackett>"
  echo "    2) Settings -> Indexers -> add Jackett (Torznab) — thêm TỪNG indexer:"
  echo "       URL:      http://127.0.0.1:9117/api/v2.0/indexers/<id>/results/torznab"
  echo "       API Path: /api"
  echo "       API key:  <key Jackett — Dashboard web UI 9117>"
  echo "       <id> = rutracker, toloka, rutor, 1337x, thepiratebay"
  echo "    3) Download client: TorrServer KHÔNG hỗ trợ -> cần qBittorrent"
  echo "       (nói tôi, cài qBit trong proot luôn, 1 lệnh)"
  echo "======================================================="
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
  echo "  Torznab (Sonarr/Radarr) — thêm TỪNG indexer (Sonarr chặn endpoint all):"
  configured_ids=$(curl -s -b "$COOKIE_JAR" "$API/indexers?configured=true&apikey=$API_KEY" \
    | grep -oE '"id":"[^"]+"' | sed 's/"id":"//; s/"$//')
  for id in $configured_ids; do
    echo "    $id -> http://<IP>:${JACKETT_PORT}/api/v2.0/indexers/$id/results/torznab"
  done
  echo "    (mỗi indexer: URL như trên, API Path: /api, API key: $API_KEY)"
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
  proot)
    shift
    action="${1:-setup}"
    case "$action" in
      stop)
        pkill -f "proot-distro login $PROOT_DISTRO" 2>/dev/null || true
        echo "Jackett (proot) đã tắt."
        ;;
      status)
        if curl -sf -o /dev/null "http://127.0.0.1:${JACKETT_PORT}/"; then
          echo "Jackett đang chạy: http://localhost:${JACKETT_PORT}"
        else
          echo "Jackett KHÔNG chạy (chạy: sh $0 proot start)."
        fi
        ;;
      start)
        proot_launch
        proot_wait_ready
        ;;
      *)
        proot_ensure_distro
        proot_setup_inside
        proot_install_jackett
        proot_launch
        proot_wait_ready
        JACKETT_DIR="$PROOT_HOST_DIR"
        configure_all
        ;;
    esac
    ;;
  sonarr)
    shift
    action="${1:-setup}"
    case "$action" in
      stop)
        pkill -f "root/sonarr/Sonarr" 2>/dev/null || true
        echo "Sonarr (proot) đã tắt."
        ;;
      status)
        if curl -sf -o /dev/null "http://127.0.0.1:${SONARR_PORT}/ping"; then
          echo "Sonarr đang chạy: http://localhost:${SONARR_PORT}"
        else
          echo "Sonarr KHÔNG chạy (chạy: sh $0 sonarr start)."
        fi
        ;;
      start)
        sonarr_launch
        sonarr_wait_ready
        ;;
      *)
        proot_ensure_distro
        sonarr_install_inside
        sonarr_launch
        sonarr_wait_ready
        sonarr_show_info
        ;;
    esac
    ;;
  radarr)
    shift
    action="${1:-setup}"
    case "$action" in
      stop)
        pkill -f "root/radarr/Radarr" 2>/dev/null || true
        echo "Radarr (proot) đã tắt."
        ;;
      status)
        if curl -sf -o /dev/null "http://127.0.0.1:${RADARR_PORT}/ping"; then
          echo "Radarr đang chạy: http://localhost:${RADARR_PORT}"
        else
          echo "Radarr KHÔNG chạy (chạy: sh $0 radarr start)."
        fi
        ;;
      start)
        radarr_launch
        radarr_wait_ready
        ;;
      *)
        proot_ensure_distro
        radarr_install_inside
        radarr_launch
        radarr_wait_ready
        radarr_show_info
        ;;
    esac
    ;;
  start-all)
    # Termux bị đóng hẳn → khởi động lại toàn bộ bản proot đã cài.
    # API key KHÔNG đổi khi restart (lưu trong file config trên ổ).
    command -v proot-distro >/dev/null 2>&1 || { echo "Chưa có proot-distro — chạy 'sh $0 proot' trước."; exit 1; }
    echo "==> Khởi động lại toàn bộ (Jackett + Sonarr + Radarr)..."
    [ -x "$PD_ROOTFS/root/jackett/jackett" ] && { proot_launch; proot_wait_ready; }
    [ -x "$PD_ROOTFS/root/sonarr/Sonarr" ] && { sonarr_launch; sonarr_wait_ready; }
    [ -x "$PD_ROOTFS/root/radarr/Radarr" ] && { radarr_launch; radarr_wait_ready; }
    echo "==> Xong. API key giữ nguyên — nzb360/web UI dùng lại như cũ."
    ;;
  *)
    install_jackett
    start_jackett
    configure_all
    [ "${TUNE:-0}" = "1" ] && { echo ""; tune; }
    ;;
esac
