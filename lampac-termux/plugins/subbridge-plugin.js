(function () {
  'use strict';

  var BRIDGE_URL = 'http://127.0.0.1:8484';
  var btnEl = null;
  var currentVideoUrl = '';

  function log() {
    console.log.apply(console, ['[SubBridge]'].concat([].slice.call(arguments)));
  }

  function noty(msg) {
    try { Lampa.Noty.show(msg); } catch (e) { log(msg); }
  }

  // Hook player to capture item url
  function hookPlayer() {
    try {
      // Lampa logs "Player item url XXX" - intercept it
      var origLog = console.log;
      console.log = function () {
        var args = [].slice.call(arguments);
        var msg = args.join(' ');
        if (msg.indexOf('Player item url') !== -1) {
          var url = msg.replace('Player item url ', '').trim();
          if (url.indexOf('http') === 0) {
            currentVideoUrl = url;
            log('Captured video URL:', url.substring(0, 120));
          }
        }
        return origLog.apply(console, arguments);
      };
      log('Console interceptor active');
    } catch (e) { log('Hook error:', e.message); }

    // Also try direct player access
    try {
      Lampa.Listener.follow('player', function (e) {
        if (e.type === 'start') {
          setTimeout(function () {
            // Try to get URL from player internal state
            try {
              var pd = Lampa.Player.playdata && Lampa.Player.playdata();
              if (pd && pd.path) {
                log('playdata path:', pd.path);
              }
              // Try player component
              if (Lampa.Player.player && Lampa.Player.player()) {
                var p = Lampa.Player.player();
                log('player keys:', Object.keys(p));
                if (p.url) currentVideoUrl = p.url;
                if (p.card && p.card.url) currentVideoUrl = p.card.url;
              }
            } catch (e2) { log('direct access error:', e2.message); }
          }, 500);
        }
      });
    } catch (e) { log('Listener error:', e.message); }
  }

  function getVideoUrl() {
    if (currentVideoUrl) return currentVideoUrl;
    // Fallback: video element
    try {
      var v = document.querySelector('video');
      if (v && v.src && v.src.indexOf('http') === 0) return v.src;
    } catch (e) {}
    return null;
  }

  function getSubUrl() {
    try {
      var s = Lampa.Player.subtitles && Lampa.Player.subtitles();
      if (s && s.length) return s[0].url;
    } catch (e) {}
    return null;
  }

  function openInMXPlayer() {
    var videoUrl = getVideoUrl();
    if (!videoUrl) {
      noty('No video URL - play something first');
      return;
    }
    var subUrl = getSubUrl();
    var payload = { video: videoUrl, title: 'Lampa' };
    if (subUrl) {
      payload.sub = subUrl;
      var c = subUrl.split('?')[0].toLowerCase();
      payload.format = c.endsWith('.ass') || c.endsWith('.ssa') ? 'ass' : c.endsWith('.vtt') ? 'vtt' : 'srt';
      payload.label = 'Vietnamese';
    }
    log('Sending:', videoUrl.substring(0, 120));
    fetch(BRIDGE_URL + '/play', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
    .then(function (r) { return r.json(); })
    .then(function (r) {
      noty(r.status === 'ok' ? 'Sent to MXPlayer' : 'Error: ' + (r.error || ''));
    })
    .catch(function () { noty('SubBridge APK not running!'); });
  }

  function createBtn() {
    if (btnEl) return;
    btnEl = document.createElement('div');
    btnEl.id = 'subbridge-btn';
    btnEl.textContent = 'MXPlayer';
    btnEl.style.cssText = 'position:fixed;bottom:88px;right:16px;z-index:99999;'
      + 'background:rgba(33,150,243,0.85);color:#fff;padding:10px 20px;border-radius:20px;'
      + 'font-size:12px;cursor:pointer;box-shadow:0 2px 8px rgba(0,0,0,0.4);'
      + 'font-family:sans-serif;font-weight:600;backdrop-filter:blur(4px);';
    btnEl.onclick = function (e) { e.stopPropagation(); openInMXPlayer(); };
    document.body.appendChild(btnEl);
    log('Button created');
  }

  function detectVideo() {
    if (currentVideoUrl || (document.querySelector('video') && document.querySelector('video').src)) {
      createBtn();
    }
  }

  hookPlayer();

  // Show button when video detected
  setInterval(detectVideo, 2000);

  log('Plugin loaded v5.0');
  window.SubBridge = { open: openInMXPlayer };
})();
