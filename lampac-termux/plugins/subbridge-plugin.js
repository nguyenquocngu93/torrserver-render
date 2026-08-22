(function () {
  'use strict';

  var BRIDGE_URL = 'http://127.0.0.1:8484';
  var btnEl = null;
  var capturedUrl = '';

  function log() {
    console.log.apply(console, ['[SubBridge]'].concat([].slice.call(arguments)));
  }

  function noty(msg) {
    try { Lampa.Noty.show(msg); } catch (e) { log(msg); }
  }

  // Scan performance entries for stream URLs
  function scanNetwork() {
    if (capturedUrl) return capturedUrl;
    try {
      var entries = performance.getEntriesByType('resource');
      for (var i = entries.length - 1; i >= 0; i--) {
        var name = entries[i].name;
        // Stream URLs contain /stream/ or .mp4 or .mkv with link param
        if (name.indexOf('/stream/') !== -1 && name.indexOf('link=') !== -1) {
          capturedUrl = name;
          log('Network found:', name.substring(0, 150));
          return capturedUrl;
        }
      }
    } catch (e) { log('Perf error:', e.message); }

    // Fallback: also check for any URL with .mp4/.mkv and link param
    try {
      var all = performance.getEntriesByType('resource');
      for (var j = all.length - 1; j >= 0; j--) {
        var n = all[j].name;
        if ((n.indexOf('.mp4') !== -1 || n.indexOf('.mkv') !== -1) && n.indexOf('link=') !== -1) {
          capturedUrl = n;
          log('Network fallback:', n.substring(0, 150));
          return capturedUrl;
        }
      }
    } catch (e) {}

    return null;
  }

  // Try playdata path reconstruction
  function tryPlaydata() {
    try {
      var pd = Lampa.Player.playdata && Lampa.Player.playdata();
      if (pd && pd.path) {
        log('playdata.path:', pd.path);
        // Store for later use
        window._sb_playdata = pd;
      }
    } catch (e) {}
  }

  function getVideoUrl() {
    // 1. Check captured URL
    if (capturedUrl) return capturedUrl;

    // 2. Scan performance
    var found = scanNetwork();
    if (found) return found;

    // 3. Video element
    try {
      var v = document.querySelector('video');
      if (v) {
        if (v.src && v.src.indexOf('http') === 0) { log('video.src'); return v.src; }
        if (v.currentSrc && v.currentSrc.indexOf('http') === 0) { log('currentSrc'); return v.currentSrc; }
      }
    } catch (e) {}

    // 4. Try all video/source elements
    try {
      var els = document.querySelectorAll('video, source');
      for (var i = 0; i < els.length; i++) {
        var s = els[i].src || els[i].getAttribute('src');
        if (s && s.indexOf('http') === 0) { log('element src'); return s; }
      }
    } catch (e) {}

    return null;
  }

  function openInMXPlayer() {
    tryPlaydata();
    var url = getVideoUrl();
    if (!url) {
      // Last resort: try to reconstruct from playdata
      if (window._sb_playdata && window._sb_playdata.path) {
        noty('No stream URL found. Path: ' + window._sb_playdata.path);
      } else {
        noty('No video URL. Play something first.');
      }
      return;
    }
    var payload = { video: url, title: 'Lampa' };
    log('Sending:', url.substring(0, 150));
    fetch(BRIDGE_URL + '/play', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
    .then(function (r) { return r.json(); })
    .then(function (r) { noty(r.status === 'ok' ? 'Sent to MXPlayer' : 'Error: ' + (r.error || '')); })
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
      + 'font-family:sans-serif;font-weight:600;';
    btnEl.onclick = function (e) { e.stopPropagation(); openInMXPlayer(); };
    document.body.appendChild(btnEl);
    log('Button created');
  }

  // Hook player start to scan network
  try {
    Lampa.Listener.follow('player', function (e) {
      if (e.type === 'start') {
        // Scan after delay to let network requests complete
        setTimeout(function () {
          tryPlaydata();
          var url = scanNetwork();
          if (url) createBtn();
        }, 500);
        setTimeout(function () {
          var url = scanNetwork();
          if (url) createBtn();
        }, 2000);
        setTimeout(function () {
          var url = scanNetwork();
          if (url) createBtn();
        }, 5000);
      }
    });
  } catch (e) {}

  // Also scan periodically
  setInterval(function () {
    if (!capturedUrl) scanNetwork();
    if (capturedUrl && !btnEl) createBtn();
    // Also check video element as backup
    var v = document.querySelector('video');
    if (v && v.src && v.src.indexOf('http') === 0 && !btnEl) createBtn();
  }, 2000);

  log('Plugin loaded v6.0');
  window.SubBridge = { open: openInMXPlayer, url: function () { return capturedUrl || scanNetwork(); } };
})();
