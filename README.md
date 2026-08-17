# torrserver-render

Bộ công cụ **tìm + tải + xem torrent** chạy trên VPS, Termux (Android) hoặc sandbox cloud:

| Thành phần | Vai trò | Cổng |
|---|---|---|
| **TorrServer** | Stream torrent — xem được ngay trong lúc tải, không cần file hoàn chỉnh | 8090 |
| **Jackett** | Tổng hợp indexer (rutracker, toloka, rutor, 1337x, TPB...) — tìm nguồn qua 1 web UI / API Torznab | 9117 |
| **Sonarr** | Quản lý **phim bộ**: theo dõi series, tự tìm nguồn qua Jackett | 8989 |
| **Radarr** | Quản lý **phim lẻ** (cùng họ với Sonarr) | 7878 |
| **tracker-search.sh** | Tìm trực tiếp trên rutracker + toloka bằng CLI, thêm thẳng vào TorrServer | — |

**Combo đề xuất (hiệu quả nhất):**
- **Điện thoại (Termux)** = máy tìm + quản lý: Jackett + Sonarr/Radarr (trong proot Debian), điều khiển bằng app **nzb360**.
- **VPS / máy 140** = máy kéo: TorrServer (seed box) — IP datacenter không sao vì traffic torrent là peer-to-peer, không bị Cloudflare chặn.

---

## 1. Cài trên VPS (Oracle Cloud / Ubuntu) — máy kéo

```bash
curl -sL -o install-torrserver.sh https://raw.githubusercontent.com/nguyenquocngu93/torrserver-render/jackett-integration/install-torrserver.sh
sudo sh install-torrserver.sh
```

Script tự làm: tải TorrServer + systemd service + BBR + tắt uTP + cache theo RAM + trackers RU (`bt.t-ru.org`) + mở port trong ufw/firewalld. Cổng peer cố định **45000** (TCP+UDP).

**BẮT BUỘC mở Oracle Cloud Security List:**
```
Networking → VCN → Security Lists → <list đang gắn với subnet của instance> → Add Ingress Rule
  - TCP 8090        (web UI TorrServer)
  - TCP + UDP 45000 (traffic torrent + DHT — thiếu UDP là không có DHT)
  - TCP 9117        (nếu cài Jackett trên VPS)
```

**Kiểm tra:** `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8090` → `200`

> ⚠️ **Mẹo sống còn:** Oracle free tier hay bảo trì qua đêm → máy reboot và **đổi public IP** (IP không reserved). Web UI "tự nhiên không vào" → check lại IP trong Oracle Console trước, rồi mới đổ lỗi firewall.

---

## 2. Cài trên Termux (Android) — máy tìm + quản lý

```bash
pkg install -y git curl
git clone https://github.com/nguyenquocngu93/torrserver-render.git
cd torrserver-render
sh termux-setup.sh        # TorrServer native (JACKETT=0 để bỏ Jackett)
```

**Jackett/Sonarr/Radarr = app .NET — KHÔNG chạy native trên Termux** (dính lỗi ICU/ELF/GC). Chạy trong **proot-distro Debian** (Linux thật, đã chứng minh chạy ổn):

```bash
sh jackett-setup.sh proot      # Jackett (tự cài distro + Jackett + cấu hình 5 indexer)
sh jackett-setup.sh sonarr     # Sonarr (phim bộ)
sh jackett-setup.sh radarr     # Radarr (phim lẻ)
```

Cần ~1GB trống. Sau khi cài, giữ máy không ngủ:
```bash
termux-wake-lock        # pkg install termux-api
```

---

## 3. jackett-setup.sh — bảng lệnh

| Lệnh | Chức năng |
|---|---|
| `sh jackett-setup.sh` | Cài + chạy + cấu hình indexer (bản native — Linux/VPS) |
| `sh jackett-setup.sh configure` | Cấu hình lại indexer (Jackett đang chạy) |
| `sh jackett-setup.sh start` | Chỉ khởi động lại, không đụng cấu hình |
| `sh jackett-setup.sh stop` | Tắt |
| `sh jackett-setup.sh speedtest [từ khóa]` | Đo tốc độ search từng indexer, tìm nguồn chậm |
| `sh jackett-setup.sh disable <id>...` | Tắt tạm indexer (vd: `disable rutracker 1337x`) |
| `sh jackett-setup.sh tune [id...]` | **Tự tắt nguồn lỗi/chậm** — dùng cho VPS bị timeout Cloudflare |
| `sh jackett-setup.sh proot [start\|stop\|status]` | Jackett trong proot Debian (Termux) |
| `sh jackett-setup.sh sonarr [start\|stop\|status]` | Sonarr trong proot Debian |
| `sh jackett-setup.sh radarr [start\|stop\|status]` | Radarr trong proot Debian |

**Biến môi trường quan trọng:**
- `JACKETT_PORT`, `SONARR_PORT` (8989), `RADARR_PORT` (7878)
- `RUTRACKER_LOGIN/PASS`, `TOLOKA_LOGIN/PASS` — tài khoản semi-private (mặc định `Saunhung`/`saunhung`)
- `RUTRACKER_COOKIES`, `TOLOKA_COOKIES` — dán cookie trình duyệt để qua Cloudflare
- `FLARESOLVERR_URL` — URL FlareSolverr để tự qua Cloudflare
- `JACKETT_GC_LIMIT`, `SONARR_GC_LIMIT`, `RADARR_GC_LIMIT` — giới hạn heap .NET (mặc định 512MB, máy RAM lớn tăng `0x40000000`)
- `TS_URL` — địa chỉ TorrServer cho `jackett-add.sh` / `tracker-search.sh`

---

## 4. Tìm nguồn → ném vào TorrServer

**Từ Jackett web UI** (`http://localhost:9117`): search → copy magnet hoặc link `.torrent` → thêm thẳng:

```bash
sh jackett-add.sh 'http://localhost:9117/dl/toloka/xxx.torrent'   # link tải từ Jackett
sh jackett-add.sh 'magnet:?xt=urn:btih:...'                      # magnet bất kỳ
TS_URL=http://<IP-máy-kéo>:8090 sh jackett-add.sh '<link>'        # đẩy lên VPS từ xa
```

**Từ CLI tracker bán riêng tư** (rutracker + toloka, không cần Jackett):

```bash
sh tracker-search.sh login
sh tracker-search.sh search "tên phim"
sh tracker-search.sh add 3          # thêm kết quả #3 vào TorrServer
sh tracker-search.sh dl rutracker 60558049
```

---

## 5. nzb360 (app Android) — điều khiển từ điện thoại

nzb360 quản lý được Sonarr + Radarr + Jackett + qBittorrent trong 1 app. Thêm server:

| App | URL | API key |
|---|---|---|
| Sonarr | `http://localhost:8989` | in ra lúc cài (`sh jackett-setup.sh sonarr`) |
| Radarr | `http://localhost:7878` | in ra lúc cài (`sh jackett-setup.sh radarr`) |

Còn thiếu bước cuối cho tự động hóa hoàn chỉnh: **qBittorrent** (download client). TorrServer **không** phải download client chuẩn nên Sonarr/Radarr chưa tự tải được — chúng chỉ tự tìm nguồn qua Jackett. Cài qBit thì combo thành: **nzb360 thêm phim → Sonarr/Radarr tìm trên Jackett → qBit tải → xem qua TorrServer**.

---

## 6. Sandbox cloud (render/Freebuff) — không bắt buộc

- `run.sh` — TorrServer + tunnel cloudflared trycloudflare (in link công khai)
- `jackett.sh` — Jackett + tunnel cloudflared trycloudflare
- `Dockerfile` — image TorrServer tối giản (`ghcr.io/yourok/torrserver`)

---

## 7. Troubleshooting — các lỗi đã gặp và cách xử lý

| Lỗi | Nguyên nhân | Fix |
|---|---|---|
| Jackett "Couldn't find a valid ICU" trên Termux native | .NET không tìm ra ICU glibc qua ld cache | **Dùng proot** (`sh jackett-setup.sh proot`) — bỏ hẳn native |
| `bad ELF magic: 2f2a2047` (`CANNOT LINK EXECUTABLE`) | LD_LIBRARY_PATH dính vào lệnh bionic | Đã fix trong script: biến chỉ áp cho tiến trình Jackett qua `sh -c` |
| `GC heap initialization failed with error 0x8007000E` | .NET server GC reserve heap quá lớn trên điện thoại | Đã fix: `DOTNET_gcServer=0` + giới hạn heap (512MB) |
| Search Jackett timeout 100s / "Challenge detected" | rutracker/toloka/1337x sau Cloudflare chặn IP datacenter | `sh jackett-setup.sh tune` (tự tắt nguồn chậm), hoặc FlareSolverr, hoặc cookie trình duyệt |
| "Lỗi hash" khi lấy magnet từ torrentgalaxy/toloka | Tracker không trả hash/magnet cho kết quả đó | Dùng **file .torrent** thay vì magnet (`jackett-add.sh` xử lý được) |
| Web UI 140 không vào được | Máy reboot qua đêm → **đổi IP** hoặc service chết | Check IP mới trong Oracle Console → `systemctl enable --now torrserver` |
| Torrent tải chậm dù nhiều seed | Peer port không mở / random | Cổng cố định 45000 + mở TCP/UDP trong security list |
| proot-distro in danh sách image rồi thoát | Bản 5.6+ đổi cú pháp install | Đã fix: script tự phát hiện version, dùng `install -n debian debian:stable` |

---

## 8. Cập nhật script mới nhất

```bash
curl -sL -o jackett-setup.sh https://raw.githubusercontent.com/nguyenquocngu93/torrserver-render/jackett-integration/jackett-setup.sh
curl -sL -o install-torrserver.sh https://raw.githubusercontent.com/nguyenquocngu93/torrserver-render/jackett-integration/install-torrserver.sh
```
