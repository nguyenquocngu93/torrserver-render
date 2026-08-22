/**
 * mxplayer-bridge/server.js
 * 
 * Bridge Server: Lampa → MXPlayer with subtitles
 * 
 * Runs on Termux, receives POST /play from Lampa plugin,
 * launches MXPlayer via termux-am with video + subtitle URLs.
 * 
 * Usage:
 *   node server.js [port]
 *   Default port: 8484
 */

const http = require('http');
const { exec } = require('child_process');
const url = require('url');

const PORT = parseInt(process.argv[2] || '8484');

/* ─── MXPlayer package name ──────────────────────────────── */
const MX_PLAYER_PKG = 'com.mxtech.videoplayer.ad';
const MX_PLAYER_PRO = 'com.mxtech.videoplayer.pro';

/* ─── Try both MXPlayer variants ─────────────────────────── */
function getMXPlayerCmd(){
  return new Promise((resolve) => {
    /* Check if MXPlayer Pro exists */
    exec('pm list packages | grep com.mxtech.videoplayer.pro', (err, stdout) => {
      if(stdout && stdout.trim()){
        resolve(MX_PLAYER_PRO);
      } else {
        resolve(MX_PLAYER_PKG);
      }
    });
  });
}

/* ─── Launch MXPlayer with video + subtitles ──────────────── */
async function launchMXPlayer(videoUrl, subtitles, title){
  const pkg = await getMXPlayerCmd();
  
  /* Build intent command using termux-am */
  /* MXPlayer supports these intent extras for subtitles:
   *   -d <video_url>           : data URI
   *   -n <pkg>/<activity>      : component
   *   --es "subs" <uri>        : subtitle URI (may need array)
   *   --eu "subs" <uri>        : subtitle URI as Uri
   *   --es "subs_name" <name>  : subtitle display name
   */
  
  let cmd = `termux-am start -n ${pkg}/.ActivityVideoPlayer -a android.intent.action.VIEW -t "video/*" -d "${videoUrl}"`;
  
  /* Add title */
  if(title){
    cmd += ` --es "title" "${title.replace(/"/g, '\\"')}"`;
  }
  
  /* Add subtitles */
  if(subtitles && subtitles.length){
    subtitles.forEach((sub, i) => {
      if(sub.url){
        cmd += ` --eu "subs${i}" "${sub.url}"`;
        cmd += ` --es "subs_name${i}" "${sub.label || 'Subtitle ' + (i+1)}"`;
      }
    });
    
    /* MXPlayer expects subs as IntentCompat.getStringArrayListExtra
       For multiple subs, we use the key "subs" with index */
    if(subtitles.length === 1 && subtitles[0].url){
      /* Single subtitle - simpler format */
      cmd = `termux-am start -n ${pkg}/.ActivityVideoPlayer -a android.intent.action.VIEW -t "video/*" -d "${videoUrl}" --eu "subs" "${subtitles[0].url}" --es "subs_name" "${subtitles[0].label || 'Subtitle'}"`;
    }
  }
  
  return new Promise((resolve, reject) => {
    exec(cmd, { timeout: 10000 }, (err, stdout, stderr) => {
      if(err){
        /* Try fallback: open in browser */
        console.log('[Bridge] MXPlayer launch failed, trying browser fallback');
        console.log('[Bridge] Error:', err.message);
        
        /* Fallback: just open URL */
        exec(`termux-open-url "${videoUrl}"`, (e2) => {
          if(e2) reject(e2);
          else resolve({ ok: true, method: 'browser', cmd });
        });
      } else {
        resolve({ ok: true, method: 'mxplayer', cmd, output: stdout });
      }
    });
  });
}

/* ─── HTTP Server ─────────────────────────────────────────── */
const server = http.createServer(async (req, res) => {
  /* CORS headers */
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  
  if(req.method === 'OPTIONS'){
    res.writeHead(200);
    res.end();
    return;
  }
  
  const parsed = url.parse(req.url, true);
  
  /* GET /health */
  if(parsed.pathname === '/health' && req.method === 'GET'){
    const pkg = await getMXPlayerCmd();
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({
      ok: true,
      mxplayer: pkg,
      port: PORT,
      version: '1.0.0'
    }));
    return;
  }
  
  /* GET /status */
  if(parsed.pathname === '/status' && req.method === 'GET'){
    exec('pm list packages | grep com.mxtech', (err, stdout) => {
      const installed = (stdout || '').trim().split('\n').filter(l => l);
      res.writeHead(200, {'Content-Type': 'application/json'});
      res.end(JSON.stringify({
        ok: true,
        installed: installed,
        termux_am: true
      }));
    });
    return;
  }
  
  /* POST /play */
  if(parsed.pathname === '/play' && req.method === 'POST'){
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', async () => {
      try {
        const data = JSON.parse(body);
        
        if(!data.video){
          res.writeHead(400, {'Content-Type': 'application/json'});
          res.end(JSON.stringify({ ok: false, error: 'Missing video URL' }));
          return;
        }
        
        console.log(`[Bridge] Playing: ${data.title || data.video}`);
        console.log(`[Bridge] Subtitles: ${(data.subtitles || []).length}`);
        
        const result = await launchMXPlayer(
          data.video,
          data.subtitles || [],
          data.title || ''
        );
        
        console.log(`[Bridge] Result:`, result);
        
        res.writeHead(200, {'Content-Type': 'application/json'});
        res.end(JSON.stringify(result));
      } catch(e) {
        console.error('[Bridge] Parse error:', e.message);
        res.writeHead(500, {'Content-Type': 'application/json'});
        res.end(JSON.stringify({ ok: false, error: e.message }));
      }
    });
    return;
  }
  
  /* GET / - info page */
  if(parsed.pathname === '/'){
    res.writeHead(200, {'Content-Type': 'text/html'});
    res.end(`
      <!DOCTYPE html>
      <html>
      <head><title>MXPlayer Bridge</title></head>
      <body style="background:#1a1a2e;color:#fff;font-family:monospace;padding:40px;">
        <h1 style="color:#00d4ff;">🌉 MXPlayer Bridge Server</h1>
        <p>Bridge giữa Lampa Web UI và MXPlayer trên Android</p>
        <h2>Endpoints:</h2>
        <ul>
          <li><code>GET /health</code> - Kiểm tra sức khỏe</li>
          <li><code>GET /status</code> - Trạng thái MXPlayer</li>
          <li><code>POST /play</code> - Phát video với subtitle</li>
        </ul>
        <h2>POST /play body:</h2>
        <pre style="background:#0f0f23;padding:16px;border-radius:8px;color:#00d4ff;">
{
  "video": "http://...",
  "title": "Movie Name",
  "subtitles": [
    {"url": "http://.../*.srt", "label": "Vietnamese"},
    {"url": "http://.../*.ass", "label": "English"}
  ]
}
        </pre>
        <h2>Sử dụng với Lampa:</h2>
        <p>Plugin <code>lampa-mxplayer-bridge.js</code> sẽ tự động gửi yêu cầu đến đây.</p>
      </body>
      </html>
    `);
    return;
  }
  
  res.writeHead(404, {'Content-Type': 'application/json'});
  res.end(JSON.stringify({ ok: false, error: 'Not found' }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[MXPlayer Bridge] Server running on port ${PORT}`);
  console.log(`[MXPlayer Bridge] Health: http://127.0.0.1:${PORT}/health`);
  console.log(`[MXPlayer Bridge] Play: POST http://127.0.0.1:${PORT}/play`);
  console.log('');
  console.log('Waiting for Lampa requests...');
});

server.on('error', (err) => {
  if(err.code === 'EADDRINUSE'){
    console.error(`[MXPlayer Bridge] Port ${PORT} already in use!`);
    console.error(`[MXPlayer Bridge] Kill existing: kill $(lsof -t -i:${PORT})`);
  } else {
    console.error('[MXPlayer Bridge] Error:', err.message);
  }
});
