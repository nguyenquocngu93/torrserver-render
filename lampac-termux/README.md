# Lampac Termux + SubBridge

## 📱 SubBridge APK — Gửi phụ đề từ Lampa → MXPlayer

Bridge APK nhận video + subtitle từ plugin Lampa, tự động mở MXPlayer với phụ đề đính kèm.

### Flow
```
Lampa (browser) → SubBridge APK (port 8484) → MXPlayer
     ↓                    ↓                       ↓
Click Play        POST /play {video, sub}    Mở video + phụ đề
     ↓                    ↓                       ↓
SubSense plugin   Download sub → local file   Phát với sub
```

### Cài đặt nhanh

```bash
cd ~/torrserver-render
git pull

# Cài tất cả (build APK + deploy plugin)
sh lampac-termux/install-subbridge.sh
```

### Cài đặt thủ công

#### 1. Build APK
```bash
cd ~/torrserver-render/lampac-termux
sh build-bridge-apk.sh
```

#### 2. Cài APK
```bash
termux-open build-bridge/apk/SubBridge.apk
```

#### 3. Deploy plugin
```bash
sh lampac-termux/deploy-plugin.sh
```

### Cách sử dụng

1. **Mở SubBridge app** trên điện thoại
2. **Mở Lampa** trong browser: `http://127.0.0.1:9118`
3. **Settings** → **SubBridge MXPlayer** → Bật
4. **Chơi phim** → Nút 📱 MXPlayer hiện ở góc
5. **Click** → MXPlayer mở với video + phụ đề

### Hỗ trợ phụ đề

- ✅ SRT (`.srt`)
- ✅ ASS/SSA (`.ass`, `.ssa`)
- ✅ VTT (`.vtt`)
- ✅ ZIP (giải nén tự động)

### Yêu cầu

- Android 5.0+ (API 21)
- MXPlayer (Free hoặc Pro)
- Termux + termux-api (tùy chọn)
- JDK 17 (tự cài khi build)

### Troubleshooting

**APK không build được:**
```bash
pkg install aapt2 dx apksigner openjdk-17
```

**Plugin không hiện nút MXPlayer:**
- Mở DevTools (F12) → Console → check `[SubBridge]` logs
- Đảm bảo SubBridge app đang chạy
- Clear cache browser

**MXPlayer không nhận sub:**
- Đảm bảo MXPlayer có quyền truy cập storage
- Thử cài MXPlayer Pro (miễn phí trên一些 trang web)

### Files

```
lampac-termux/
├── mxplayer-bridge-app/     # Android app source
│   ├── AndroidManifest.xml
│   ├── src/com/lampac/bridge/
│   │   └── MainActivity.java
│   └── res/
├── plugins/
│   └── subbridge-plugin.js  # Lampa plugin
├── build-bridge-apk.sh      # Build script
├── install-subbridge.sh     # Full installer
├── fix-plugins.sh           # Fix existing plugins
└── README.md
```

### API

SubBridge APK chạy HTTP server trên `http://127.0.0.1:8484`

**Ping:**
```
GET /ping
→ {"status":"ok","app":"SubBridge","version":"1.0"}
```

**Play:**
```
POST /play
Content-Type: application/json

{
  "video": "http://...",
  "sub": "http://...",
  "format": "srt",
  "label": "Vietnamese",
  "title": "Phim hay"
}
→ {"status":"ok","player":"mxpro","sub":"attached"}
```

---

## 🔧 Lampac Setup

### Setup nhanh
```bash
sh lampac-termux/full-setup.sh
```

### Chạy TorrShelf
```bash
cd ~/torr-shelf && npm start &
```

### Chạy Lampac
```bash
lampac
```

### Web UI
```
http://127.0.0.1:9118
```

### Commands
```bash
sh lampac-termux/start.sh    # Start Lampac
sh lampac-termux/stop.sh     # Stop Lampac
sh lampac-termux/status.sh   # Check status
sh lampac-termux/config.sh   # Edit config
```
