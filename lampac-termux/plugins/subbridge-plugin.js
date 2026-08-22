(function () {
  'use strict';

  var BRIDGE_URL = 'http://127.0.0.1:8484';
  var btnEl = null;
  var lastVideoUrl = '';

  function log() {
    console.log.apply(console, ['[SubBridge]'].concat([].slice.call(arguments)));
  }

  function noty(msg) {
    try { Lampa.Noty.show(msg); } catch (e) { log(msg); }
  }

  function getVideoUrl() {
    // Try many sources
    try {
      var v = document.querySelector('video');
      if (v && v.src && v.src.indexOf('http') === 0) { log('Found: video.src'); return v.src; }
    } catch (e) {}

    try {
      var pd = Lampa.Player.playdata && Lampa.Player.playdata();
      if (pd) {
        if (pd.url) { log('Found: playdata.url'); return pd.url; }
        if (pd.src) { log('Found: playdata.src'); return pd.src; }
        if (pd.stream && pd.stream.url) { log('Found: playdata.stream.url'); return pd.stream.url; }
        if (pd.data && pd.data.url) { log('Found: playdata.data.url'); return pd.data.url; }
        // Check for torrent stream URL
        if (pd.torrent && pd.torrent.url) { log('Found: playdata.torrent.url'); return pd.torrent.url; }
        log('playdata keys:', Object.keys(pd));
      }
    } catch (e) { log('playdata error:', e.message); }

    // Try Lampa.Activity
    try {
      var act = Lampa.Activity.active && Lampa.Activity.active();
      if (act) {
        if (act.url) { log('Found: activity.url'); return act.url; }
        if (act.data && act.data.url) { log('Found: activity.data.url'); return act.data.url; }
        log('activity keys:', Object.keys(act));
      }
    } catch (e) {}

    // Try source from card
    try {
      if (Lampa.Player.source) { log('Found: Player.source'); return Lampa.Player.source; }
    } catch (e) {}

    // Last resort: scan all video elements
    try {
      var videos = document.querySelectorAll('video, source, iframe');
      for (var i = 0; i < videos.length; i++) {
        var src = videos[i].src || videos[i].getAttribute('src');
        if (src && src.indexOf('http') === 0) { log('Found: element src', i); return src; }
      }
    } catch (e) {}

    log('No video URL found. playdata:', JSON.stringify(
      (function(){ try { return Lampa.Player.playdata(); } catch(e) { return null; } })(),
      null, 2
    ).substring(0, 500));
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
      noty('Cannot detect video URL. Check console [SubBridge]');
      return;
    }
    lastVideoUrl = videoUrl;
    var subUrl = getSubUrl();
    var payload = { video: videoUrl, title: 'Lampa' };
    if (subUrl) {
      payload.sub = subUrl;
      var c = subUrl.split('?')[0].toLowerCase();
      payload.format = c.endsWith('.ass') || c.endsWith('.ssa') ? 'ass' : c.endsWith('.vtt') ? 'vtt' : 'srt';
      payload.label = 'Vietnamese';
    }
    log('Sending:', JSON.stringify(payload).substring(0, 300));
    fetch(BRIDGE_URL + '/play', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
    .then(function (r) { return r.json(); })
    .then(function (r) {
      log('Response:', r);
      noty(r.status === 'ok' ? 'Sent to MXPlayer' : 'Error: ' + (r.error || ''));
    })
    .catch(function (e) {
      log('Error:', e);
      noty('SubBridge APK not running! Open it first.');
    });
  }

  function createBtn() {
    if (btnEl) return;
    btnEl = document.createElement('div');
    btnEl.id = 'subbridge-btn';
    btnEl.textContent = 'MXPlayer';
    btnEl.style.cssText = 'position:fixed;bottom:88px;right:16px;z-index:99999;'
      + 'background:rgba(33,150,243,0.85);color:#fff;padding:10px 20px;border-radius:20px;'
      + 'font-size:12px;cursor:pointer;box-shadow:0 2px 8px rgba(0,0,0,0.4);'
      + 'font-family:sans-serif;font-weight:600;backdrop-filter:blur(4px);'
      + 'transition:transform 0.2s;';
    btnEl.onmousedown = function () { btnEl.style.transform = 'scale(0.9)'; };
    btnEl.onmouseup = btnEl.onmouseleave = function () { btnEl.style.transform = 'scale(1)'; };
    btnEl.onclick = function (e) { e.stopPropagation(); openInMXPlayer(); };
    document.body.appendChild(btnEl);
    log('Button created');
  }

  function removeBtn() {
    if (btnEl) { btnEl.remove(); btnEl = null; }
  }

  // Detect: show when video element exists with src
  function detectVideo() {
    var video = document.querySelector('video');
    if (video && video.src && video.src.indexOf('http') === 0) {
      createBtn();
    } else {
      removeBtn();
    }
  }

  // Hook player events
  try {
    Lampa.Listener.follow('player', function (e) {
      if (e.type === 'start' || e.type === 'ready') {
        setTimeout(detectVideo, 1000);
        setTimeout(detectVideo, 2000);
        setTimeout(detectVideo, 4000);
      }
      if (e.type === 'destroy') removeBtn();
    });
  } catch (e) { log('Listener error:', e.message); }

  // Video element events
  setInterval(function () {
    var video = document.querySelector('video');
    if (video && video.src && video.src.indexOf('http') === 0) {
      if (!btnEl) {
        video.addEventListener('playing', createBtn);
        createBtn();
      }
    }
  }, 2000);

  log('Plugin loaded v4.1');
  window.SubBridge = { open: openInMXPlayer };
})();
