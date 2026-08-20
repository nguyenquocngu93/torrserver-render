# Lampac NextGen — Termux Installer

Chạy Lampac NextGen trên điện thoại Android qua Termux.

## Cài đặt

```bash
cd ~/torrserver-render
git pull
cd lampac-termux
sh setup.sh
```

## Sử dụng

```bash
# Khởi động
lampac

# Kiểm tra trạng thái
lampac-status

# Sửa config (bật/tắt providers)
lampac-config

# Dừng
lampac-stop
```

Sau khi khởi động, mở trình duyệt:
```
http://127.0.0.1:9118
```

## Config providers

Vào `lampac-config` (nano editor), tìm section providers và bật:

```json
{
  "Rezka": { "enable": true, "host": "https://rezka.ag" },
  "Filmix": { "enable": true, "host": "https://filmix.biz" },
  "Collaps": { "enable": true }
}
```

## Tích hợp với TorrServer

Lampac có TorrServer built-in. Nếu muốn dùng chung TorrServer đã cài trên Termux:

```bash
# Trong init.conf, đổi TorrServer port:
{
  "TorrServer": {
    "enable": true,
    "port": 8091
  }
}
```

## Yêu cầu

- Termux (từ F-Droid, KHÔNG phải Google Play)
- ~500MB bộ nhớ trống (Ubuntu proot + .NET)
- Kết nối internet

## Troubleshooting

```bash
# Nếu dotnet lỗi
proot-distro login ubuntu -- bash -c 'apt update && apt install -y aspnetcore-runtime-10'

# Xem log lỗi
proot-distro login ubuntu -- bash -c 'cd /opt/lampac && dotnet Core.dll 2>&1 | head -50'

# Cài lại từ đầu
proot-distro remove ubuntu
sh setup.sh
```

## Architecture

```
Termux
  └─ proot-distro (Ubuntu)
       └─ dotnet Core.dll (Lampac)
            ├─ Lampa Web UI (port 9118)
            ├─ TorrServer (built-in)
            ├─ JacRed (Jackett aggregator)
            └─ 70+ VOD providers
```
