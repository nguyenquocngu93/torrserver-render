# Lampac + TorrShelf Media Stack — Termux Setup

Media stack trên Termux: Lampac (browse phim) + TorrShelf (scrapers) + TorrServer APK (torrents).

## Architecture

```
Lampac (port 9118)          TorrShelf (port 8787)       TorrServer APK (port 8090)
├── Browse phim (TMDB)      ├── UHDMovies scraper       ├── Torrent streaming
├── Lampa UI                ├── 4KHDHub scraper         ├── Preload/cache
├── torrshelf plugin        ├── MoviesDrive scraper     └── HTTP Range
└── NO torrents             ├── HDHub4u scraper
                            └── /api/streams endpoint
```

## Cài đặt lần đầu

```bash
cd ~/torrserver-render
git pull

# 1. Cài Lampac
sh lampac-termux/setup.sh

# 2. Patch TorrShelf (thêm /api/streams endpoint)
sh lampac-termux/patch-torrshelf.sh ~/torr-shelf

# 3. Deploy Lampa plugins
sh lampac-termux/deploy-plugin.sh
```

## Sử dụng

```bash
lampac          # Khởi động
lampac-stop     # Dừng
lampac-status   # Kiểm tra
lampac-config   # Sửa config
```

Mở browser: `http://127.0.0.1:9118`

## Cài plugin Phim Việt Nam

Plugin tích hợp 4 nguồn: **KKPhim, OPhim, UHDMovie, 4KHDHub**

### Cách 1: Deploy tự động

```bash
sh lampac-termux/deploy-plugin.sh
```

### Cách 2: Thủ công

```bash
proot-distro login ubuntu -- bash -c '
mkdir -p /opt/lampac/plugins/override
# Copy plugin từ host
cat /home/*/torrserver-render/lampac-termux/plugins/vn-sources.js > /opt/lampac/plugins/override/vn-sources.js
echo "Plugin deployed!"
'
```

### Kích hoạt plugin

Chỉnh `init.conf`:

```bash
lampac-config
```

Thêm section `LampaWeb`:

```json
{
  "listen": { ... },
  "BaseModule": { ... },
  "LampaWeb": {
    "customPlugins": [
      { "url": "{localhost}/vn-sources.js", "status": 1 }
    ]
  }
}
```

Restart:
```bash
lampac-stop && lampac
```

### Sử dụng plugin

1. Mở Lampa: `http://127.0.0.1:9118`
2. Vào Settings → Source → Chọn **Phim Viet**
3. Hoặc vào menu sidebar → chọn nguồn
4. Search phim sẽ tìm trên cả 4 nguồn

## Cấu hình nguồn

Trong Settings của Lampa:
- **Phim Viet — Nguon mac dinh**: Chọn nguồn chính (KKPhim/OPhim/UHDMovie/4KHDHub)
- **Toggler từng nguồn**: Bật/tắt từng source riêng

## Fix GStreamer

Nếu gặp lỗi GStreamer khi start:

```bash
proot-distro login ubuntu -- bash -c '
rm -rf /opt/lampac/module/GStreamer
find /opt/lampac/runtimes -iname "*gstreamer*" -delete 2>/dev/null
find /opt/lampac/runtimes -iname "*gst*" -delete 2>/dev/null
find /opt/lampac/runtimes -iname "*libglib*" -delete 2>/dev/null
echo "GStreamer removed!"
'
lampac
```

## Built-in modules

Lampac đã có sẵn 70+ nguồn (Rezka, Filmix, Collaps, KinoPub...).
Bật trong `init.conf`:

```json
{
  "Rezka": { "enable": true },
  "Filmix": { "enable": true, "token": "YOUR_TOKEN" },
  "Collaps": { "enable": true },
  "KinoPub": { "enable": true, "token": "YOUR_TOKEN" }
}
```

## Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| `ERR_CONNECTION_REFUSED` | Lampac crash — check GStreamer, chạy `lampac` xem error |
| `libicu` error | `apt-get install libicu78` (Ubuntu 26.04) |
| `libglib` error | Xóa GStreamer hoặc cài `libglib2.0-0` |
| Plugin không hiện | Check `init.conf` có `LampaWeb.customPlugins` chưa |
| `dotnet` not found | Chạy lại `setup.sh` |
