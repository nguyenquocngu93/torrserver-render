#!/bin/bash
# ============================================================
#  patch-torrshelf.sh — Patch TorrShelf to add /api/streams
# ============================================================
#  Usage:  sh patch-torrshelf.sh [torrshelf-path]
#
#  This replaces server.mjs in your TorrShelf installation with
#  the patched version that includes /api/streams endpoint.
#  The endpoint enables Lampa plugin to call TorrShelf providers.
# ============================================================

set -e

TORRSHELF_DIR="${1:-$HOME/torr-shelf}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHED_FILE="$SCRIPT_DIR/server.mjs.patched"

echo ""
echo "  Patching TorrShelf server.mjs"
echo "  ============================="
echo ""

# Check patched file exists
if [ ! -f "$PATCHED_FILE" ]; then
  echo "ERROR: $PATCHED_FILE not found"
  echo "Make sure server.mjs.patched is in the same directory as this script"
  exit 1
fi

# Check TorrShelf directory
if [ ! -d "$TORRSHELF_DIR" ]; then
  echo "ERROR: TorrShelf not found at $TORRSHELF_DIR"
  echo ""
  echo "Usage: sh $0 /path/to/torr-shelf"
  exit 1
fi

if [ ! -f "$TORRSHELF_DIR/server.mjs" ]; then
  echo "ERROR: server.mjs not found in $TORRSHELF_DIR"
  exit 1
fi

# Backup original
echo "[1/3] Backing up original server.mjs..."
cp "$TORRSHELF_DIR/server.mjs" "$TORRSHELF_DIR/server.mjs.bak"
echo "  -> server.mjs.bak"

# Copy patched version
echo "[2/3] Applying patch..."
cp "$PATCHED_FILE" "$TORRSHELF_DIR/server.mjs"
echo "  -> server.mjs (patched)"

# Verify
echo "[3/3] Verifying..."
if grep -q "handleStreamsApi" "$TORRSHELF_DIR/server.mjs"; then
  echo ""
  echo -e "  \033[0;32m✓ Patch applied successfully!\033[0m"
  echo ""
  echo "  New endpoint: GET /api/streams"
  echo "  Parameters: title, year, type, season, episode, max"
  echo ""
  echo "  Example:"
  echo "    http://127.0.0.1:8787/api/streams?title=Avengers&type=movie&year=2019"
  echo ""
  echo "  Restart TorrShelf to apply:"
  echo "    pkill -f 'node server.mjs'"
  echo "    cd $TORRSHELF_DIR && npm start"
  echo ""
else
  echo ""
  echo -e "  \033[0;31m✗ Patch failed — handleStreamsApi not found\033[0m"
  echo "  Restoring backup..."
  cp "$TORRSHELF_DIR/server.mjs.bak" "$TORRSHELF_DIR/server.mjs"
  exit 1
fi
