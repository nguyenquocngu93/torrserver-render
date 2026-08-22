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

  // Method 1: Hook XMLHttpRequest
  function hookXHR() {
    var origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
      if (typeof url === 'string' && url.indexOf('/stream/') !== -1) {
        capturedUrl = url;
        log('XHR captured:', url.substring(0, 120));
      }
      return origOpen.apply(this, arguments);
    };
    log('XHR hook active');
  }

  // Method 2: Hook fetch
  function hookFetch() {
    if (!window.fetch) return;
    var origFetch = window.fetch;
    window.fetch = function (input) {
      var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      if (url.indexOf('/stream/') !== -1) {
        capturedUrl = url;
        log('Fetch captured:', url.substring(0, 120));
      }
      return origFetch.apply(this, arguments);
    };
    log('Fetch hook active');
  }

  // Method 3: Hook console with better matching
  function hookConsole() {
    var orig = console.log;
    console.log = function () {
      try {
        for (var i = 0; i < arguments.length; i++) {
          var arg = String(arguments[i]);
          if (arg.indexOf('item url') !== -1 && arg.indexOf('http') !== -1) {
            var m = arg.match(/(https?:\/\/[^\s]+)/);
            if (m) {
              capturedUrl = m[1];
              log('Console captured:', capturedUrl.substring(0, 120));
            }
          }
        }
      } catch (e) {}
      return orig.apply(console, arguments);
    };
    // Also try info and warn
    var origInfo = console.info;
    console.info = function () {
      try {
        for (var i = 0; i < arguments.length; i++) {
          var arg = String(arguments[i]);
          if (arg.indexOf('item url') !== -1 || arg.indexOf('/stream/') !== -1) {
            var m = arg.match(/(https?:\/\/[^\s]+)/);
            if (m) { capturedUrl = m[1]; log('Info captured:', capturedUrl.substring(0, 120)); }
          }
        }
      } catch (e) {}
      return origInfo.apply(console, arguments);
    };
    log('Console hook active');
  }

  // Method 4: Watch video element src changes
  function hookVideo() {
    var check = function () {
      var v = document.querySelector('video');
      if (v && v.src && v.src.indexOf('http') === 0 && v.src.indexOf(capturedUrl) === -1) {
        capturedUrl = v.src;
        log('Video src captured:', capturedUrl.substring(0, 120));
      }
    };
    setInterval(check, 1000);
    // Also watch for src attribute changes
    var observer = new MutationObserver(function (mutations) {
      mutations.forEach(function (m) {
        if (m.attributeName === 'src') check();
      });
    });
    var attachTo = function (el) {
      observer.observe(el, { attributes: true, attributeFilter: ['src'] });
    };
    var tryAttach = function () {
      var v = document.querySelector('video');
      if (v) attachTo(v);
    };
    tryAttach();
    setInterval(tryAttach, 2000);
    log('Video hook active');
  }

  function getVideoUrl() {
    // Priority: captured from hooks > video element
    if (capturedUrl) return capturedUrl;
    try {
      var v = document.querySelector('video');
      if (v && v.src && v.src.indexOf('http') === 0) return v.src;
    } catch (e) {}
    return null;
  }

  function openInMXPlayer() {
    var url = getVideoUrl();
    if (!url) { noty('No video URL yet - play a video first'); return; }
    var payload = { video: url, title: 'Lampa' };
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
  }

  // Show button when video is playing
  setInterval(function () {
    var v = document.querySelector('video');
    if ((capturedUrl || (v && v.src && v.src.indexOf('http') === 0)) && !btnEl) {
      createBtn();
      log('Button shown');
    }
  }, 1500);

  // Init all hooks
  hookXHR();
  hookFetch();
  hookConsole();
  hookVideo();
  log('Plugin loaded v5.1');
  window.SubBridge = { open: openInMXPlayer, url: function () { return capturedUrl; } };
})();
