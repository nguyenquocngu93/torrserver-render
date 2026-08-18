#!/bin/sh
# TorrUI - Startup script for Termux
# Usage: sh start.sh [port]

set -e

PORT="${1:-3000}"
TORRSERVER_URL="${TORRSERVER_URL:-http://127.0.0.1:8090}"

cd "$(dirname "$0")"

echo "TorrUI - NZB360-style UI for TorrServer"
echo "=========================================="
echo ""

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
  echo "Installing dependencies..."
  npm install
  echo ""
fi

# Check TorrServer connection
echo "Checking TorrServer at $TORRSERVER_URL ..."
if curl -sf "$TORRSERVER_URL/echo" > /dev/null 2>&1; then
  echo "TorrServer OK"
else
  echo "Warning: Cannot reach TorrServer"
  echo "  Make sure TorrServer is running at $TORRSERVER_URL"
  echo ""
fi

echo ""
echo "Starting TorrUI on port $PORT ..."
echo "  Local: http://127.0.0.1:$PORT"
echo ""

PORT=$PORT TORRSERVER_URL=$TORRSERVER_URL node server.js
