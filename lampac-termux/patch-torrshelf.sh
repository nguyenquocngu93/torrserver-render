#!/bin/bash
# patch-torrshelf.sh — Patch TorrShelf to work with Lampac
# Adds /api/streams endpoint for Lampa plugin integration
# Usage: sh lampac-termux/patch-torrshelf.sh [torrshelf-path]

set -e

TORRSHELF_PATH="${1:-$HOME/torr-shelf}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Patch TorrShelf for Lampac ==="
echo "TorrShelf path: $TORRSHELF_PATH"
echo ""

# ─── Check TorrShelf exists ────────────────────────────────
if [ ! -d "$TORRSHELF_PATH" ]; then
  echo "ERROR: TorrShelf not found at $TORRSHELF_PATH"
  echo ""
  echo "Please clone TorrShelf first:"
  echo "  git clone https://github.com/your-repo/torr-shelf.git ~/torr-shelf"
  echo ""
  echo "Or specify the path:"
  echo "  sh lampac-termux/patch-torrshelf.sh /path/to/torr-shelf"
  exit 1
fi

echo "[1/3] Creating API server wrapper..."
proot-distro login ubuntu -- bash -c "
  mkdir -p /opt/torrshelf

  # Create a simple API proxy server for TorrShelf
  cat > /opt/torrshelf/server.py << 'PYEOF'
#!/usr/bin/env python3
\"\"\"
TorrShelf API Server for Lampac integration
Proxies requests to TorrShelf scrapers and formats results for Lampa
\"\"\"

import http.server
import json
import urllib.request
import urllib.parse
import os
import sys
import traceback

TORRSHELF_URL = os.environ.get('TORRSHELF_URL', 'http://127.0.0.1:8787')
PORT = int(os.environ.get('TORRSHELF_API_PORT', '8788'))

# Source configurations
SOURCES = {
    'kkphim': {
        'name': 'KKPhim',
        'base': 'https://khophim.co',
        'search': '/ajax/movie/search?keyword={query}',
        'detail': '/ajax/movie/{id}',
        'stream': '/ajax/episode/sources?id={id}'
    },
    'ophim': {
        'name': 'OPhim',
        'base': 'https://ophim.me',
        'search': '/ajax/movie/search?keyword={query}',
        'detail': '/ajax/movie/{id}',
        'stream': '/ajax/episode/sources?id={id}'
    },
    'uhdmovie': {
        'name': 'UHDMovie',
        'base': 'https://uhdmovie.dev',
        'search': '/ajax/movie/search?keyword={query}',
        'detail': '/ajax/movie/{id}',
        'stream': '/ajax/episode/sources?id={id}'
    },
    'khd4k': {
        'name': '4KHDHub',
        'base': 'https://4khdhub.com',
        'search': '/ajax/movie/search?keyword={query}',
        'detail': '/ajax/movie/{id}',
        'stream': '/ajax/episode/sources?id={id}'
    }
}


def fetch_url(url, timeout=15):
    \"\"\"Fetch URL with error handling\"\"\"
    try:
        req = urllib.request.Request(url, headers={
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': url.split('/')[0] + '//' + url.split('/')[2] + '/'
        })
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read().decode('utf-8', errors='replace')
    except Exception as e:
        print(f'Error fetching {url}: {e}', file=sys.stderr)
        return None


def parse_search_html(html, source_id):
    \"\"\"Parse search results HTML\"\"\"
    import re
    results = []
    
    # Extract items from HTML
    items = re.findall(r'<div[^>]*class=\"[^\"]*flw-item[^\"]*\"[^>]*>(.*?)</div>\s*</div>', html, re.DOTALL)
    
    for item in items:
        # Extract link
        link_match = re.search(r'href=\"([^\"]+)\"', item)
        # Extract title
        title_match = re.search(r'class=\"film-name[^\"]*\"[^>]*>\s*<a[^>]*>([^<]+)</a>', item, re.DOTALL)
        # Extract poster
        poster_match = re.search(r'<img[^>]*(?:data-src|src)=\"([^\"]+)\"', item)
        # Extract quality
        qual_match = re.search(r'class=\"[^\"]*quality[^\"]*\"[^>]*>([^<]+)<', item)
        
        if link_match and title_match:
            href = link_match.group(1)
            if not href.startswith('http'):
                href = SOURCES[source_id]['base'] + href
            slug = href.rstrip('/').split('/')[-1]
            
            results.append({
                'id': slug,
                'title': title_match.group(1).strip(),
                'poster': poster_match.group(1) if poster_match else '',
                'quality': qual_match.group(1).strip() if qual_match else '',
                'year': '',
                'source': source_id,
                'sourceName': SOURCES[source_id]['name'],
                'url': href
            })
    
    return results


def search_source(source_id, query):
    \"\"\"Search a specific source\"\"\"
    if source_id not in SOURCES:
        return []
    
    src = SOURCES[source_id]
    search_url = src['base'] + src['search'].replace('{query}', urllib.parse.quote(query))
    
    html = fetch_url(search_url)
    if html:
        return parse_search_html(html, source_id)
    return []


def get_streams(movie_id, source_id):
    \"\"\"Get stream URLs for a movie\"\"\"
    streams = []
    
    if source_id not in SOURCES:
        return streams
    
    src = SOURCES[source_id]
    
    # Try to get episode sources
    detail_url = src['base'] + src['stream'].replace('{id}', urllib.parse.quote(movie_id))
    html = fetch_url(detail_url)
    
    if html:
        try:
            data = json.loads(html)
            if 'links' in data:
                for link in data['links']:
                    streams.append({
                        'title': link.get('title', ''),
                        'url': link.get('url', ''),
                        'quality': link.get('quality', ''),
                        'type': link.get('type', 'movie')
                    })
        except json.JSONDecodeError:
            pass
    
    return streams


class APIHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        
        try:
            if parsed.path == '/api/search':
                keyword = params.get('keyword', [''])[0]
                source = params.get('source', [''])[0]
                
                if not keyword:
                    self.send_json({'error': 'keyword required'}, 400)
                    return
                
                results = []
                if source:
                    results = search_source(source, keyword)
                else:
                    for sid in SOURCES:
                        results.extend(search_source(sid, keyword))
                
                self.send_json(results)
            
            elif parsed.path == '/api/streams':
                movie_id = params.get('id', [''])[0]
                source = params.get('source', ['kkphim'])[0]
                
                if not movie_id:
                    self.send_json({'error': 'id required'}, 400)
                    return
                
                streams = get_streams(movie_id, source)
                self.send_json(streams)
            
            elif parsed.path == '/api/sources':
                self.send_json(list(SOURCES.keys()))
            
            elif parsed.path == '/api/health':
                self.send_json({'status': 'ok', 'sources': list(SOURCES.keys())})
            
            else:
                self.send_json({'error': 'Not found'}, 404)
        
        except Exception as e:
            traceback.print_exc()
            self.send_json({'error': str(e)}, 500)
    
    def send_json(self, data, code=200):
        response = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Length', str(len(response)))
        self.end_headers()
        self.wfile.write(response)
    
    def log_message(self, format, *args):
        # Suppress default logging
        pass


def main():
    print(f'TorrShelf API Server starting on port {PORT}...')
    print(f'Sources: {list(SOURCES.keys())}')
    
    server = http.server.HTTPServer(('0.0.0.0', PORT), APIHandler)
    print(f'API Server running at http://127.0.0.1:{PORT}')
    print('Press Ctrl+C to stop')
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('Stopping...')
        server.shutdown()


if __name__ == '__main__':
    main()
PYEOF

  chmod +x /opt/torrshelf/server.py
  echo 'API server wrapper created'
"

echo "[2/3] Creating TorrShelf management scripts..."

# Create TorrShelf start/stop in proot
proot-distro login ubuntu -- bash -c '
  # start-torrshelf.sh
  cat > /opt/torrshelf/start.sh << "TSEOF"
#!/bin/bash
cd /opt/torrshelf

# Kill existing
pkill -f "python3.*server.py" 2>/dev/null || true

echo "Starting TorrShelf API Server..."
echo "API: http://127.0.0.1:8788"
echo "Press Ctrl+C to stop"
echo ""

python3 server.py
TSEOF
  chmod +x /opt/torrshelf/start.sh

  # Stop script
  cat > /opt/torrshelf/stop.sh << "TSSTOPEOF"
#!/bin/bash
pkill -f "python3.*server.py" 2>/dev/null && echo "TorrShelf API stopped" || echo "TorrShelf API not running"
TSSTOPEOF
  chmod +x /opt/torrshelf/stop.sh

  echo "TorrShelf scripts created"
'

echo "[3/3] Creating Termux wrapper commands..."

# Create Termux commands for TorrShelf
cat > ~/torrshelf 2>/dev/null << 'TSCMD' || true
#!/bin/bash
proot-distro login ubuntu -- bash -c 'cd /opt/torrshelf && sh start.sh'
TSCMD
chmod +x ~/torrshelf 2>/dev/null || true

cat > ~/torrshelf-stop 2>/dev/null << 'TSSTOPCMD' || true
#!/bin/bash
proot-distro login ubuntu -- bash -c 'sh /opt/torrshelf/stop.sh'
TSSTOPCMD
chmod +x ~/torrshelf-stop 2>/dev/null || true

cat > ~/torrshelf-status 2>/dev/null << 'TSSTATUSCMD' || true
#!/bin/bash
proot-distro login ubuntu -- bash -c '
  if pgrep -f "python3.*server.py" >/dev/null; then
    PID=$(pgrep -f "python3.*server.py")
    echo "✅ TorrShelf API is running (PID: $PID)"
    echo "   API: http://127.0.0.1:8788"
    echo ""
    echo "Sources:"
    curl -s http://127.0.0.1:8788/api/sources 2>/dev/null || echo "  (cannot connect)"
  else
    echo "❌ TorrShelf API is not running"
  fi
'
TSSTATUSCMD
chmod +x ~/torrshelf-status 2>/dev/null || true

# Update PATH
if ! grep -q 'export PATH="$HOME:$PATH"' ~/.bashrc 2>/dev/null; then
  echo 'export PATH="$HOME:$PATH"' >> ~/.bashrc 2>/dev/null || true
fi

echo ""
echo "=== TorrShelf Patch Complete ==="
echo ""
echo "Commands available:"
echo "  torrshelf          — Start TorrShelf API server"
echo "  torrshelf-stop     — Stop TorrShelf API"
echo "  torrshelf-status   — Check status"
echo ""
echo "API endpoints:"
echo "  GET /api/search?keyword=<query>&source=<source_id>"
echo "  GET /api/streams?id=<movie_id>&source=<source_id>"
echo "  GET /api/sources"
echo "  GET /api/health"
echo ""
echo "To use with Lampac plugin:"
echo "  The plugin auto-connects to http://127.0.0.1:8788"
echo ""
echo "Start both services:"
echo "  torrshelf   # Start API server first"
echo "  lampac      # Then start Lampac"
