#!/bin/bash
# TorrUI - Startup script for Termux
# Usage: sh start.sh [port]

set -e

PORT="${1:-3000}"
TORRSERVER_URL="${TORRSERVER_URL:-http://127.0.0.1:8090}"

cd "$(dirname "$0")"

echo "🎬 TorrUI - NZB360-style UI for TorrServer"
echo "=========================================="
echo ""

# Check if node is installed
if ! command -v node &> /dev/null; then
  echo "❌ Node.js chưa được cài đặt"
  echo "   Chạy: pkg install nodejs"
  exit 1
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
  echo "📦 Đang cài đặt dependencies..."
  npm install
  echo ""
fi

# Check TorrServer connection
echo "🔍 Kiểm tra TorrServer tại $TORRSERVER_URL ..."
if curl -sf "$TORRSERVER_URL/echo" > /dev/null 2>&1; then
  echo "✅ TorrServer đang chạy"
else
  echo "⚠️  Không kết nối được TorrServer"
  echo "   Đảm bảo TorrServer đang chạy trên $TORRSERVER_URL"
  echo ""
fi

echo ""
echo "🚀 Khởi động TorrUI trên port $PORT ..."
echo "   Truy cập: http://127.0.0.1:$PORT"
echo "   Hoặc từ thiết bị khác: http://$(hostname -I 2>/dev/null | awk '{print $1}'):$PORT"
echo ""

PORT=$PORT TORRSERVER_URL=$TORRSERVER_URL node server.js
