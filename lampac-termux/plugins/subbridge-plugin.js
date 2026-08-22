(function () {
  'use strict';

  var BRIDGE_PORT = 8484;
  var BRIDGE_URL = 'http://127.0.0.1:' + BRIDGE_PORT;

  function log() {
    var args = ['[SubBridge]'].concat([].slice.call(arguments));
    console.log.apply(console, args);
  }

  function noty(msg) {
    try { Lampa.Noty.show(msg); } catch (e) { log(msg); }
  }

  function checkBridge(callback) {
    fetch(BRIDGE_URL + '/ping', { signal: AbortSignal.timeout(2000) })
      .then(function (r) { return r.json(); })
      .then(function (d) { log('Bridge OK:', d); callback(true); })
      .catch(function () { log('Bridge offline'); callback(false); });
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

  function sendToBridge(videoUrl, subUrl, title) {
    var payload = { video: videoUrl, title: title || 'Lampa' };
    if (subUrl) {
      payload.sub = subUrl;
      var clean = subUrl.split('?')[0].toLowerCase();
      payload.format = clean.endsWith('.ass') || clean.endsWith('.ssa') ? 'ass'
        : clean.endsWith('.vtt') ? 'vtt' : 'srt';
      payload.label = 'Vietnamese';
    }
    log('Send:', JSON.stringify(payload).slice(0, 200));

    fetch(BRIDGE_URL + '/play', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
      .then(function (r) { return r.json(); })
      .then(function (r) {
        log('Response:', r);
        if (r.status === 'ok') {
          noty('Opened MXPlayer' + (r.sub === 'attached' ? ' + subtitle' : ''));
        } else {
          noty('Bridge error: ' + (r.error || 'unknown'));
        }
      })
      .catch(function (e) {
        log('Send failed:', e);
        noty('Cannot connect to SubBridge APK');
      });
  }

  function openInMXPlayer() {
    var videoUrl = getVideoUrl();
    if (!videoUrl) {
      noty('No video URL found');
      return;
    }
    checkBridge(function (ok) {
      if (ok) {
        sendToBridge(videoUrl, getSubUrl(), 'Lampa');
      } else {
        noty('SubBridge APK not running! Open SubBridge app first.');
      }
    });
  }

  // Add to Lampa player menu
  function addPlayerMenu() {
    try {
      Lampa.PlayerMenu.add({
        title: 'Open in MXPlayer',
        subtitle: 'Send video + subtitle to MXPlayer via SubBridge',
        icon: '<svg viewBox="0 0 24 24" fill="white"><path d="M8 5v14l11-7z"/></svg>',
        action: openInMXPlayer
      });
      log('PlayerMenu item added');
    } catch (e) {
      log('PlayerMenu failed:', e.message);
    }
  }

  // Also add a floating button as backup
  function addFloatingButton() {
    try {
      Lampa.Listener.follow('player', function (e) {
        if (e.type === 'start' || e.type === 'ready') {
          setTimeout(function () {
            if (document.querySelector('#subbridge-btn')) return;
            var btn = document.createElement('div');
            btn.id = 'subbridge-btn';
            btn.textContent = 'MXPlayer';
            btn.style.cssText = 'position:fixed;bottom:100px;right:16px;z-index:99999;'
              + 'background:#2196F3;color:#fff;padding:10px 16px;border-radius:20px;'
              + 'font-size:14px;font-weight:bold;cursor:pointer;box-shadow:0 4px 12px rgba(0,0,0,0.4);'
              + 'font-family:sans-serif;';
            btn.onclick = openInMXPlayer;
            document.body.appendChild(btn);
            log('Floating button added');
          }, 1500);
        }
      });
    } catch (e) {
      log('Float button failed:', e.message);
    }
  }

  // Init
  log('Plugin loaded v2.0');
  if (window.Lampa) {
    addPlayerMenu();
    addFloatingButton();
  } else {
    document.addEventListener('lampa:ready', function () {
      addPlayerMenu();
      addFloatingButton();
    });
  }

  window.SubBridge = { send: sendToBridge, check: checkBridge, open: openInMXPlayer };
})();
