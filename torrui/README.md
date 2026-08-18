# TorrUI

Giao diện web kiểu NZB360 cho TorrServer - Stream torrent trực tiếp không cần tải về.

## ✨ Tính năng

- 🎬 **Stream trực tiếp** - Xem phim ngay lập tức qua TorrServer
- 📱 **Mobile-first** - Giao diện tối ưu cho điện thoại
- 🔍 **Tìm kiếm** - Tìm torrent trong danh sách đã lưu
- 📁 **Quản lý file** - Chọn file cụ thể để phát
- ⚡ **Nhanh chóng** - Không cần tải file về, stream ngay

## 🚀 Cài đặt trên Termux

### Yêu cầu
- Termux đã cài đặt
- Node.js (`pkg install nodejs`)
- TorrServer đang chạy trên `127.0.0.1:8090`

### Bước 1: Clone hoặc copy thư mục `torrui` vào Termux

```bash
cd ~/torrui
```

### Bước 2: Cài dependencies

```bash
npm install
```

### Bước 3: Chạy

```bash
sh start.sh
```

Hoặc với port tùy chỉnh:

```bash
sh start.sh 3000
```

### Bước 4: Mở trình duyệt

Truy cập: `http://127.0.0.1:3000`

## 📱 Sử dụng

### Thêm torrent
1. Nhấn **☰** → **➕ Thêm torrent**
2. Dán magnet link vào ô
3. Nhấn **Thêm & Lưu**

### Phát phim
1. Vào **📋 Danh sách**
2. Nhấn nút **▶** trên torrent muốn xem
3. Chọn file nếu có nhiều file
4. Enjoy!

### Tìm kiếm
1. Vào **🔍 Tìm kiếm**
2. Nhập tên phim
3. Xem kết quả

## ⚙️ Cài đặt

### Thay đổi port

```bash
PORT=8080 sh start.sh
```

### Kết nối TorrServer khác

```bash
TORRSERVER_URL=http://192.168.1.100:8090 sh start.sh
```

## 🔧 Troubleshooting

### "Không kết nối được TorrServer"
- Đảm bảo TorrServer đang chạy: `curl http://127.0.0.1:8090/echo`
- Kiểm tra port: TorrServer mặc định dùng port 8090

### "Lỗi khi thêm torrent"
- Magnet link phải bắt đầu bằng `magnet:?xt=urn:btih:...`
- Hoặc nhập hash của torrent

### Video không phát
- Trình duyệt phải hỗ trợ HTML5 video
- Thử dùng Chrome hoặc Firefox

## 📁 Cấu trúc

```
torrui/
├── server.js          # Backend Node.js proxy
├── package.json       # Dependencies
├── start.sh          # Script khởi động
├── public/
│   ├── index.html    # Trang chính
│   ├── style.css     # Styles (dark theme)
│   ├── app.js        # Frontend logic
│   └── manifest.json # PWA manifest
└── README.md         # Tài liệu
```

## 🛠️ Tech Stack

- **Backend**: Node.js + Express
- **Frontend**: Vanilla HTML/CSS/JS
- **Theme**: NZB360-inspired dark theme
- **API**: TorrServer REST API

## 📝 License

MIT
