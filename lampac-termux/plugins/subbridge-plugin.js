(function () {
  'use strict';

  var BRIDGE_URL = 'http://127.0.0.1:8484';

  function log() {
    console.log.apply(console, ['[SubBridge]'].concat([].slice.call(arguments)));
  }

  function noty(msg) {
    try { Lampa.Noty.show(msg); } catch (e) { log(msg); }
  }

  function getVideoUrl() {
    try {
      var v = document.querySelector('video');
      if (v && v.src) return v.src;
    } catch (e) {}
    try {
      var pd = Lampa.Player.playdata && Lampa.Player.playdata();
      if (pd && pd.url) return pd.url;
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
    if (!videoUrl) { noty('No video URL'); return; }
    var subUrl = getSubUrl();
    var payload = { video: videoUrl, title: 'Lampa' };
    if (subUrl) {
      payload.sub = subUrl;
      var c = subUrl.split('?')[0].toLowerCase();
      payload.format = c.endsWith('.ass') || c.endsWith('.ssa') ? 'ass' : c.endsWith('.vtt') ? 'vtt' : 'srt';
      payload.label = 'Vietnamese';
    }
    fetch(BRIDGE_URL + '/play', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
    .then(function (r) { return r.json(); })
    .then(function (r) {
      log('Response:', r);
      noty(r.status === 'ok' ? 'Opened MXPlayer' + (r.sub === 'attached' ? ' + sub' : '') : 'Error: ' + (r.error || ''));
    })
    .catch(function () { noty('SubBridge not running!'); });
  }

  // Inject button into player controls
  function injectButton() {
    if (document.querySelector('#subbridge-btn')) return;

    // Find player control bar
    var selectors = [
      '.player__controls',
      '.player-controls',
      '.player .bottom',
      '.player'
    ];
    var target = null;
    for (var i = 0; i < selectors.length; i++) {
      target = document.querySelector(selectors[i]);
      if (target) break;
    }

    var btn = document.createElement('div');
    btn.id = 'subbridge-btn';
    btn.textContent = 'MXPlayer';
    btn.style.cssText = 'display:inline-block;background:#2196F3;color:#fff;padding:8px 14px;'
      + 'border-radius:16px;font-size:13px;cursor:pointer;margin-left:8px;'
      + 'font-family:sans-serif;font-weight:bold;vertical-align:middle;';
    btn.onclick = function (e) { e.stopPropagation(); openInMXPlayer(); };

    if (target) {
      target.appendChild(btn);
      log('Button injected into', target.className || target.tagName);
    } else {
      // Fallback: floating button
      btn.style.cssText = 'position:fixed;bottom:100px;right:16px;z-index:99999;'
        + 'background:#2196F3;color:#fff;padding:12px 18px;border-radius:24px;'
        + 'font-size:14px;cursor:pointer;box-shadow:0 4px 12px rgba(0,0,0,0.5);'
        + 'font-family:sans-serif;font-weight:bold;';
      document.body.appendChild(btn);
      log('Floating button (no player controls found)');
    }
  }

  // Watch for player opening
  function watchPlayer() {
    Lampa.Listener.follow('player', function (e) {
      if (e.type === 'start' || e.type === 'ready' || e.type === 'render') {
        setTimeout(injectButton, 1000);
        setTimeout(injectButton, 3000);
      }
    });
    log('Player watcher registered');
  }

  // Also use MutationObserver as backup
  function watchDOM() {
    var observer = new MutationObserver(function () {
      if (!document.querySelector('#subbridge-btn')) {
        var player = document.querySelector('.player, .player__controls, .video-player');
        if (player) injectButton();
      }
    });
    observer.observe(document.body, { childList: true, subtree: true });
    log('DOM observer active');
  }

  log('Plugin loaded v3.0');
  watchPlayer();
  watchDOM();
  // Try immediate inject
  setTimeout(injectButton, 2000);

  window.SubBridge = { open: openInMXPlayer };
})();
