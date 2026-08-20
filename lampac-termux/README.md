# Lampac + TorrShelf Media Stack — Termux Setup

Media stack trên Termux: Lampac (browse phim) + TorrShelf (scrapers) + 4 nguồn Việt Nam.

## Architecture

```
Lampac (port 9118)          TorrShelf (port 8787)         Nguồn Việt
├── Browse phim (TMDB)      ├── UHDMovies scraper         ├── khophim.co
├── Lampa UI                ├── 4KHDHub scraper           ├── ophim.me
├── vn-sources.js plugin    ├── MoviesDrive scraper       ├── uhdmovie.dev
├── no-apk-force.js         └── /api/streams endpoint     └── 4khdhub.com
└── torrshelf-streams.js
```

## Quick Start (Recommended)

```bash
cd ~/torrserver-render
git pull

# Full setup (installs everything)
sh lampac-termux/full-setup.sh
```

Then:
```bash
# Start both services
cd ~/torr-shelf && npm start &    # TorrShelf
lampac                            # Lampac

# Open browser
# http://127.0.0.1:9118
```

## Step-by-Step Setup

### 1. Install Lampac
```bash
sh lampac-termux/setup.sh
```

### 2. Patch TorrShelf
```bash
sh lampac-termux/patch-torrshelf.sh ~/torr-shelf
```

### 3. Deploy Plugins
```bash
sh lampac-termux/deploy-plugin.sh
```

### 4. Configure init.conf
Add to `/opt/lampac/init.conf`:
```json
{
  "LampaWeb": {
    "customPlugins": [
      {"url": "{localhost}/no-apk-force.js", "status": 1},
      {"url": "{localhost}/vn-sources.js", "status": 1},
      {"url": "{localhost}/torrshelf-streams.js", "status": 1}
    ]
  },
  "BaseModule": {
    "SkipModules": ["TorrServer"]
  }
}
```

### 5. Start Services
```bash
# Start TorrShelf
cd ~/torr-shelf && npm start

# Start Lampac (new terminal)
lampac
```

## Plugins

### vn-sources.js — Vietnamese Sources
- Adds 4 sources: KKPhim, OPhim, UHDMovie, 4KHDHub
- Works via TorrShelf API or direct scraping
- Access: Settings → Source → Phim Việt

### torrshelf-streams.js — TorrShelf Integration
- Adds "TorrShelf" button to movie detail pages
- Calls TorrShelf API for streams
- Works with UHDMovies, 4KHDHub, MoviesDrive, HDHub4u, Vadapav

### no-apk-force.js — Bypass APK Requirement
- Removes "Install APK" modal
- Forces web mode
- Enables all features in browser

## Management Commands

```bash
lampac          # Start Lampac
lampac-stop     # Stop Lampac
lampac-status   # Check status
```

## API Endpoints

TorrShelf (port 8787):
- `GET /api/streams?title=...&year=...&type=movie` — Get stream URLs
- `GET /api/sources` — List available sources

## Built-in Modules

Lampac has 70+ sources (Rezka, Filmix, Collaps, KinoPub...).
Enable in `init.conf`:
```json
{
  "Rezka": { "enable": true },
  "Filmix": { "enable": true, "token": "YOUR_TOKEN" }
}
```

## Fix GStreamer Errors

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

## Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| `ERR_CONNECTION_REFUSED` | Chạy `sh lampac-termux/start.sh` |
| `libicu` error | `apt-get install libicu78` (Ubuntu 26.04) |
| `libglib` error | Xóa GStreamer (xem trên) |
| Plugin không hiện | Check `init.conf` có `LampaWeb.customPlugins` |
| Không tìm thấy nguồn Việt | Kiểm tra TorrShelf: `curl http://127.0.0.1:8787/api/sources` |
| Stream không phát | Thử nguồn khác hoặc check TorrShelf logs |
| APK modal hiện | Plugin no-apk-force.js chưa load |
