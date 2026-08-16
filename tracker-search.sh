#!/bin/sh
# ============================================================
#  tracker-search.sh — tìm torrent trên tracker bán riêng tư
#  (RuTracker.org + Toloka.to) và thêm thẳng vào TorrServer.
#
#  Vì TorrServer không tự đăng nhập được tracker (HTTP fetcher
#  của nó không gửi cookie), script này dùng curl để:
#    login  -> lưu cookie
#    search -> quét trang tracker.php, in kết quả đánh số
#    add    -> tải file .torrent bằng cookie, POST lên
#              TorrServer /torrent/upload (đã kiểm tra API)
#
#  Cách dùng:
#    sh tracker-search.sh login
#    sh tracker-search.sh search "<từ khóa>"
#    sh tracker-search.sh add <số thứ tự kết quả>
#    sh tracker-search.sh dl rutracker|toloka <topic-id>
#
#  Cấu hình bằng biến môi trường (có sẵn giá trị mặc định):
#    TS_URL             địa chỉ TorrServer (mặc định http://127.0.0.1:8090)
#    RUTRACKER_LOGIN/PASS, TOLOKA_LOGIN/PASS   tài khoản semi-private
#    RUTRACKER_BASES     danh sách mirror rutracker (cách nhau bằng space)
#    TOLOKA_BASE         địa chỉ toloka.to
#    TS_STATE_DIR        nơi lưu cookie/kết quả (mặc định ./private)
# ============================================================
set -u

# ------------------- CONFIG -------------------
TS_URL="${TS_URL:-http://127.0.0.1:8090}"

# Tài khoản semi-private (dùng chung cho cả 2 tracker).
# Đổi mật khẩu thì sửa ở đây, hoặc export biến trước khi chạy.
RUTRACKER_LOGIN="${RUTRACKER_LOGIN:-Saunhung}"
RUTRACKER_PASS="${RUTRACKER_PASS:-saunhung}"
TOLOKA_LOGIN="${TOLOKA_LOGIN:-Saunhung}"
TOLOKA_PASS="${TOLOKA_PASS:-saunhung}"

# rutracker.org đôi khi bị chặn theo vùng/ISP -> thử lần lượt các mirror.
RUTRACKER_BASES="${RUTRACKER_BASES:-https://rutracker.org https://rutracker.net https://rutracker.nl}"
TOLOKA_BASE="${TOLOKA_BASE:-https://toloka.to}"

UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STATE_DIR="${TS_STATE_DIR:-$SCRIPT_DIR/private}"
mkdir -p "$STATE_DIR"

RUTRACKER_JAR="$STATE_DIR/rutracker.cookies"
TOLOKA_JAR="$STATE_DIR/toloka.cookies"
RUTRACKER_BASE=""          # mirror đang dùng (set sau khi login OK)
LAST_RESULTS="$STATE_DIR/last-results.tsv"

command -v curl >/dev/null 2>&1 || { echo "Lỗi: thiếu lệnh 'curl'."; exit 1; }

# ------------------- AWK parse (kết quả dạng TSV: tracker<TAB>id<TAB>title<TAB>size<TAB>seed) -------------------
# Trang rutracker trả về windows-1251; gọi qua iconv trước khi parse.
parse_rutracker() {
  tr '\n' ' ' < "$1" | sed 's/<tr/\
<tr/g' | awk '
    /dl\.php\?t=[0-9]+/ && /viewtopic\.php\?t=[0-9]+/ {
      row = $0
      m = match(row, /viewtopic\.php\?t=[0-9]+/)
      if (!m) next
      id = substr(row, RSTART + 16, RLENGTH - 16)
      p = index(row, "tLink")
      q = index(substr(row, p), ">")
      rest = substr(row, p + q)
      e = index(rest, "</a>")
      title = substr(rest, 1, e - 1)
      gsub(/<[^>]*>/, "", title)
      gsub(/&amp;/, "\\&", title)
      gsub(/&lt;/, "<", title)
      gsub(/&gt;/, ">", title)
      gsub(/&quot;/, "\"", title)
      gsub(/&nbsp;/, " ", title)
      size = ""
      if (match(row, /tor-size[^>]*data-ts_text="[0-9]+"/)) {
        v = substr(row, RSTART, RLENGTH)
        q2 = index(v, "data-ts_text=\"")
        size = substr(v, q2 + 14)
        gsub(/[^0-9]/, "", size)
      }
      seed = cell(row, 7)
      printf "rutracker\t%s\t%s\t%s\t%s\n", id, title, size, seed
    }
    function cell(row, n,   i, j, rest) {
      rest = row
      for (i = 1; i <= n; i++) {
        if (!match(rest, /<td[^>]*>/)) return ""
        rest = substr(rest, RSTART + RLENGTH)
        j = index(rest, "</td>")
        if (!j) return ""
        if (i == n) { rest = substr(rest, 1, j - 1); break }
        rest = substr(rest, j + 5)
      }
      gsub(/<[^>]*>/, "", rest)
      gsub(/[^0-9]/, "", rest)
      return rest
    }
  '
}

parse_toloka() {
  tr '\n' ' ' < "$1" | sed 's/<tr/\
<tr/g' | awk '
    /dl\.php\?t=[0-9]+/ && /viewtopic\.php\?t=[0-9]+/ {
      row = $0
      m = match(row, /viewtopic\.php\?t=[0-9]+/)
      if (!m) next
      id = substr(row, RSTART + 16, RLENGTH - 16)
      title = cell(row, 3)
      size = cell(row, 7)
      seed = cell(row, 10)
      printf "toloka\t%s\t%s\t%s\t%s\n", id, title, size, seed
    }
    function cell(row, n,   i, j, rest) {
      rest = row
      for (i = 1; i <= n; i++) {
        if (!match(rest, /<td[^>]*>/)) return ""
        rest = substr(rest, RSTART + RLENGTH)
        j = index(rest, "</td>")
        if (!j) return ""
        if (i == n) { rest = substr(rest, 1, j - 1); break }
        rest = substr(rest, j + 5)
      }
      gsub(/<[^>]*>/, "", rest)
      gsub(/&amp;/, "\\&", rest)
      gsub(/&lt;/, "<", rest)
      gsub(/&gt;/, ">", rest)
      gsub(/&quot;/, "\"", rest)
      gsub(/&nbsp;/, " ", rest)
      gsub(/^[ \t]+|[ \t]+$/, "", rest)
      return rest
    }
  '
}

# ------------------- Đăng nhập -------------------
login_rutracker() {
  for base in $RUTRACKER_BASES; do
    rm -f "$RUTRACKER_JAR"
    if curl -s -L -c "$RUTRACKER_JAR" -b "$RUTRACKER_JAR" -A "$UA" \
        --data-urlencode "login_username=$RUTRACKER_LOGIN" \
        --data-urlencode "login_password=$RUTRACKER_PASS" \
        --data-urlencode "login=Login" \
        --data-urlencode "redirect=index.php" \
        -e "$base/forum/login.php" \
        "$base/forum/login.php" -o "$STATE_DIR/rutracker-login.html" \
      && grep -q 'id="logged-in-username"' "$STATE_DIR/rutracker-login.html"; then
      RUTRACKER_BASE="$base"
      echo "    rutracker: đăng nhập OK ($base)"
      return 0
    fi
    echo "    rutracker: $base thất bại, thử mirror khác..."
  done
  echo "    rutracker: ĐĂNG NHẬP THẤT BẠI — sai tài khoản? bị chặn IP? tracker yêu cầu captcha cho IP mới?"
  return 1
}

login_toloka() {
  rm -f "$TOLOKA_JAR"
  if curl -s -L -c "$TOLOKA_JAR" -b "$TOLOKA_JAR" -A "$UA" \
      --data-urlencode "username=$TOLOKA_LOGIN" \
      --data-urlencode "password=$TOLOKA_PASS" \
      --data-urlencode "autologin=on" \
      --data-urlencode "ssl=on" \
      --data-urlencode "redirect=" \
      --data-urlencode "login=Вхід" \
      -e "$TOLOKA_BASE/login.php" \
      "$TOLOKA_BASE/login.php" -o "$STATE_DIR/toloka-login.html" \
    && grep -q 'logout=true' "$STATE_DIR/toloka-login.html"; then
    echo "    toloka: đăng nhập OK ($TOLOKA_BASE)"
    return 0
  fi
  echo "    toloka: ĐĂNG NHẬP THẤT BẠI — sai tài khoản? bị chặn IP?"
  return 1
}

# ------------------- Tìm kiếm -------------------
search_rutracker() {
  q="$1"
  if [ -z "$RUTRACKER_BASE" ]; then
    login_rutracker || return 1
  fi
  # rutracker dùng ký tự đại diện % cho khoảng trắng/ký tự đặc biệt (tìm mờ theo kiểu LIKE)
  nm=$(printf '%s' "$q" | sed 's/[^[:alnum:]]/%/g')
  curl -s -b "$RUTRACKER_JAR" -A "$UA" \
    "$RUTRACKER_BASE/forum/tracker.php?nm=$nm" -o "$STATE_DIR/rutracker-search.html"

  # Session hết hạn -> đăng nhập lại, thử lần nữa
  if ! grep -q 'id="tor-tbl"' "$STATE_DIR/rutracker-search.html"; then
    login_rutracker || return 1
    curl -s -b "$RUTRACKER_JAR" -A "$UA" \
      "$RUTRACKER_BASE/forum/tracker.php?nm=$nm" -o "$STATE_DIR/rutracker-search.html"
  fi

  # windows-1251 -> UTF-8 để hiển thị tiêu đề tiếng Nga đúng
  if command -v iconv >/dev/null 2>&1; then
    iconv -f cp1251 -t utf-8 "$STATE_DIR/rutracker-search.html" 2>/dev/null \
      > "$STATE_DIR/rutracker-search-utf8.html" \
      || cp "$STATE_DIR/rutracker-search.html" "$STATE_DIR/rutracker-search-utf8.html"
  else
    cp "$STATE_DIR/rutracker-search.html" "$STATE_DIR/rutracker-search-utf8.html"
  fi

  parse_rutracker "$STATE_DIR/rutracker-search-utf8.html"
}

search_toloka() {
  q="$1"
  if [ ! -f "$TOLOKA_JAR" ]; then
    login_toloka || return 1
  fi
  curl -s -b "$TOLOKA_JAR" -A "$UA" -G "$TOLOKA_BASE/tracker.php" \
    --data-urlencode "o=1" --data-urlencode "s=2" --data-urlencode "nm=$q" \
    -o "$STATE_DIR/toloka-search.html"

  if ! grep -q 'logout=true' "$STATE_DIR/toloka-search.html"; then
    login_toloka || return 1
    curl -s -b "$TOLOKA_JAR" -A "$UA" -G "$TOLOKA_BASE/tracker.php" \
      --data-urlencode "o=1" --data-urlencode "s=2" --data-urlencode "nm=$q" \
      -o "$STATE_DIR/toloka-search.html"
  fi

  parse_toloka "$STATE_DIR/toloka-search.html"
}

search() {
  q="$1"
  echo "Đang tìm \"$q\" trên rutracker.org + toloka.to ..."
  { search_rutracker "$q"; search_toloka "$q"; } > "$STATE_DIR/search-raw.tsv"
  awk '{print}' "$STATE_DIR/search-raw.tsv" > "$LAST_RESULTS"
  n=$(wc -l < "$LAST_RESULTS" | tr -d ' ')
  if [ "$n" = "0" ]; then
    echo "Không tìm thấy kết quả nào (thử từ khóa tiếng Nga/Anh ngắn hơn)."
    return 0
  fi
  awk -F '\t' '
    function hum(b,   a, i) {
      a = b
      if (a !~ /^[0-9]+$/) return a
      i = 0
      while (a >= 1024 && i < 4) { a /= 1024; i++ }
      return sprintf("%.1f %sB", a, substr(" KMGTP", i + 1, 1))
    }
    { printf "%2d) [%s] %s   | %s | seed %s\n", NR, $1, $3, hum($4), $5 }
  ' "$LAST_RESULTS"
  echo ""
  echo "Thêm kết quả vào TorrServer:  sh $0 add <số>"
}

# ------------------- Thêm vào TorrServer -------------------
upload() {
  file="$1"
  title="${2:-}"
  echo "Thêm vào TorrServer ($TS_URL) ..."
  if [ -n "$title" ]; then
    curl -s -F "file=@$file" -F "title=$title" -F "save=1" "$TS_URL/torrent/upload"
  else
    curl -s -F "file=@$file" -F "save=1" "$TS_URL/torrent/upload"
  fi
  echo ""
}

dl() {
  tracker="$1"
  id="$2"
  title="${3:-}"
  case "$tracker" in
    rutracker)
      [ -n "$RUTRACKER_BASE" ] || login_rutracker || return 1
      url="$RUTRACKER_BASE/forum/dl.php?t=$id"
      jar="$RUTRACKER_JAR"
      ;;
    toloka)
      [ -f "$TOLOKA_JAR" ] || login_toloka || return 1
      url="$TOLOKA_BASE/dl.php?t=$id"
      jar="$TOLOKA_JAR"
      ;;
    *)
      echo "Tracker không biết: $tracker (chỉ hỗ trợ rutracker | toloka)"
      return 1
      ;;
  esac

  file="$STATE_DIR/$tracker-$id.torrent"
  curl -s -L -b "$jar" -A "$UA" "$url" -o "$file"

  # Session hết hạn -> đăng nhập lại và thử lần nữa
  if ! grep -aq '4:info' "$file"; then
    case "$tracker" in
      rutracker) login_rutracker || return 1 ;;
      toloka)    login_toloka || return 1 ;;
    esac
    curl -s -L -b "$jar" -A "$UA" "$url" -o "$file"
  fi

  # Kiểm tra nhanh: file .torrent (bencode) luôn chứa key "info"
  if ! grep -aq '4:info' "$file"; then
    echo "Không tải được .torrent cho $tracker #$id (cần đăng nhập? bị chặn? id sai?)"
    return 1
  fi

  size=$(wc -c < "$file" | tr -d ' ')
  echo "Đã tải .torrent ($size bytes): $file"
  upload "$file" "$title"
}

add() {
  n="$1"
  line=$(sed -n "${n}p" "$LAST_RESULTS" 2>/dev/null)
  if [ -z "$line" ]; then
    echo "Không có kết quả #$n — chạy 'sh $0 search \"...\"' trước."
    return 1
  fi
  tracker=$(printf '%s' "$line" | cut -f1)
  id=$(printf '%s' "$line" | cut -f2)
  title=$(printf '%s' "$line" | cut -f3)
  dl "$tracker" "$id" "$title"
}

# ------------------- Điều khiển -------------------
usage() {
  echo "Cách dùng:"
  echo "  sh $0 login                    đăng nhập cả 2 tracker"
  echo "  sh $0 search \"<từ khóa>\"      tìm kiếm rutracker + toloka"
  echo "  sh $0 add <số>                 thêm kết quả #<số> vào TorrServer"
  echo "  sh $0 dl <tracker> <topic-id>  thêm theo topic id (vd: dl rutracker 60558049)"
  echo ""
  echo "Biến môi trường: TS_URL, RUTRACKER_LOGIN/PASS, TOLOKA_LOGIN/PASS, RUTRACKER_BASES, TOLOKA_BASE"
  exit 1
}

# Chỉ chạy CLI khi gọi trực tiếp (sh tracker-search.sh ...), không chạy khi bị "source" vào shell khác.
if [ "$(basename -- "$0")" = "tracker-search.sh" ]; then
  cmd="${1:-}"
  case "$cmd" in
    login)      login_rutracker; login_toloka ;;
    search)     [ "$#" -ge 2 ] || usage; search "$2" ;;
    add)        [ "$#" -ge 2 ] || usage; add "$2" ;;
    dl)         [ "$#" -ge 3 ] || usage; dl "$2" "$3" ;;
    *)          usage ;;
  esac
fi
