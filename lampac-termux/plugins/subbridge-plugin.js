(function () {
  'use strict';

  var BRIDGE = 'http://127.0.0.1:8484';
  var btn = null;
  var capturedUrl = '';
  var capturedTitle = '';

  function log() {
    var args = ['[SubBridge]'];
    for (var i = 0; i < arguments.length; i++) args.push(arguments[i]);
    console.log.apply(console, args);
  }

  function noty(msg) {
    try { Lampa.Noty.show(msg); } catch (e) { log(msg); }
  }

  // ===== METHOD 1: Hook Lampa.Log.push (the internal logger) =====
  function hookLampaLog() {
    // Lampa's console panel uses Lampa.Log.push(category, message)
    // We see logs like "Player item url http://..."
    var hooked = false;

    // Try Lampa.Log.push
    if (Lampa.Log && typeof Lampa.Log.push === 'function') {
      var origPush = Lampa.Log.push;
      Lampa.Log.push = function () {
        var args = [].slice.call(arguments);
        processLogArgs(args);
        return origPush.apply(this, arguments);
      };
      hooked = true;
      log('Hooked Lampa.Log.push');
    }

    // Try Lampa.Console
    if (Lampa.Console && typeof Lampa.Console.log === 'function') {
      var origConsole = Lampa.Console.log;
      Lampa.Console.log = function () {
        var args = [].slice.call(arguments);
        processLogArgs(args);
        return origConsole.apply(this, arguments);
      };
      hooked = true;
      log('Hooked Lampa.Console.log');
    }

    // Try Lampa.Log as a function
    if (typeof Lampa.Log === 'function') {
      var origLogFn = Lampa.Log;
      Lampa.Log = function () {
        var args = [].slice.call(arguments);
        processLogArgs(args);
        return origLogFn.apply(this, arguments);
      };
      hooked = true;
      log('Hooked Lampa.Log function');
    }

    // Scan Lampa.Log object methods
    if (Lampa.Log && typeof Lampa.Log === 'object') {
      for (var key in Lampa.Log) {
        if (typeof Lampa.Log[key] === 'function' && !Lampa.Log[key]._sbHooked) {
          (function (k) {
            var orig = Lampa.Log[k];
            Lampa.Log[k] = function () {
              var args = [].slice.call(arguments);
              processLogArgs(args);
              return orig.apply(this, arguments);
            };
            Lampa.Log[k]._sbHooked = true;
          })(key);
          hooked = true;
        }
      }
    }

    if (!hooked) {
      log('Could not find Lampa.Log - trying alternatives');
    }
  }

  // ===== METHOD 2: Hook console.log as fallback =====
  function hookConsole() {
    if (console.log._sbHooked) return;
    var orig = console.log;
    console.log = function () {
      var args = [].slice.call(arguments);
      processLogArgs(args);
      return orig.apply(this, arguments);
    };
    console.log._sbHooked = true;
    log('Hooked console.log');
  }

  // ===== METHOD 3: Hook video element src setter =====
  function hookVideoSrc() {
    try {
      var vid = document.querySelector('video');
      if (vid && !vid._sbHooked) {
        var desc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
        if (desc && desc.set) {
          Object.defineProperty(vid, 'src', {
            set: function (val) {
              if (val && val.indexOf('http') === 0) {
                captureUrl(val, 'video.src setter');
              }
              desc.set.call(this, val);
            },
            get: desc.get
          });
          vid._sbHooked = true;
          log('Hooked video.src');
        }
      }
    } catch (e) {
      log('video hook error:', e.message);
    }
  }

  // ===== METHOD 4: Hook Object.defineProperty on HTMLVideoElement =====
  function hookVideoProto() {
    try {
      var desc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
      if (desc && desc.set && !HTMLMediaElement.prototype._sbSrcHooked) {
        var origSet = desc.set;
        var origGet = desc.get;
        Object.defineProperty(HTMLMediaElement.prototype, 'src', {
          set: function (val) {
            if (val && typeof val === 'string' && val.indexOf('http') === 0) {
              captureUrl(val, 'HTMLMediaElement.src');
            }
            return origSet.call(this, val);
          },
          get: function () {
            return origGet.call(this);
          }
        });
        HTMLMediaElement.prototype._sbSrcHooked = true;
        log('Hooked HTMLMediaElement.prototype.src');
      }
    } catch (e) {
      log('proto hook error:', e.message);
    }
  }

  // ===== Process log arguments to find URL =====
  function processLogArgs(args) {
    for (var i = 0; i < args.length; i++) {
      var arg = String(args[i]);

      // Pattern 1: "Player item url http://..."
      if (arg.indexOf('item url') !== -1) {
        var match = arg.match(/(https?:\/\/[^\s"']+)/);
        if (match) {
          captureUrl(match[1], 'Lampa.Log item url');
          return;
        }
      }

      // Pattern 2: Direct URL with stream pattern
      if ((arg.indexOf('/stream/') !== -1 || arg.indexOf('.mp4') !== -1 || arg.indexOf('.mkv') !== -1) &&
          arg.indexOf('link=') !== -1) {
        var urlMatch = arg.match(/(https?:\/\/[^\s"']+)/);
        if (urlMatch) {
          captureUrl(urlMatch[1], 'Lampa.Log stream url');
          return;
        }
      }

      // Pattern 3: "Player play data" - extract title
      if (arg.indexOf('play data') !== -1 || arg.indexOf('playdata') !== -1) {
        try {
          var jsonMatch = arg.match(/\{.*\}/);
          if (jsonMatch) {
            var data = JSON.parse(jsonMatch[0]);
            capturedTitle = data.title || data.fname || data.path_human || '';
          }
        } catch (e) {}
      }
    }
  }

  // ===== Capture URL =====
  function captureUrl(url, source) {
    if (!url || url === capturedUrl) return;
    capturedUrl = url;
    log('Captured [' + source + ']:', url.substring(0, 120));
    showBtn();
  }

  // ===== Scan performance entries =====
  function scanPerf() {
    try {
      var entries = performance.getEntriesByType('resource');
      for (var i = entries.length - 1; i >= 0; i--) {
        var n = entries[i].name;
        if ((n.indexOf('/stream/') !== -1 || n.indexOf('.mp4') !== -1 || n.indexOf('.mkv') !== -1) &&
            n.indexOf('link=') !== -1) {
          captureUrl(n, 'performance');
          return;
        }
      }
    } catch (e) {}
  }

  // ===== Lampa Listener =====
  function hookListener() {
    try {
      Lampa.Listener.follow('player', function (e) {
        log('Player event:', e.type);

        if (e.type === 'start' || e.type === 'play' || e.type === 'render') {
          // Try playdata
          try {
            var pd = Lampa.Player.playdata && Lampa.Player.playdata();
            if (pd) {
              capturedTitle = pd.title || pd.fname || pd.path_human || '';
              log('playdata title:', capturedTitle);
            }
          } catch (er) {}

          // Scan after delay
          setTimeout(scanPerf, 500);
          setTimeout(scanPerf, 1500);
          setTimeout(scanPerf, 3000);
        }
      });
      log('Hooked Lampa.Listener player');
    } catch (e) {
      log('Listener error:', e.message);
    }

    // Also follow any 'player' events on Storage
    try {
      if (Lampa.Storage && typeof Lampa.Storage.listener === 'function') {
        Lampa.Storage.listener.follow('player', function (e) {
          log('Storage player event:', e.type);
          setTimeout(scanPerf, 1000);
        });
      }
    } catch (e) {}
  }

  // ===== Show floating button =====
  function showBtn() {
    if (btn) return;
    btn = document.createElement('div');
    btn.id = 'subbridge-btn';
    btn.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="white" style="vertical-align:middle;margin-right:4px"><path d="M8 5v14l11-7z"/></svg>MXPlayer';
    btn.style.cssText = 'position:fixed;bottom:100px;right:16px;z-index:99999;'
      + 'background:linear-gradient(135deg,#1565c0,#0d47a1);color:#fff;'
      + 'padding:10px 18px;border-radius:24px;'
      + 'font-size:13px;cursor:pointer;box-shadow:0 3px 12px rgba(0,0,0,0.5);'
      + 'font-family:sans-serif;font-weight:600;'
      + 'display:flex;align-items:center;gap:4px;'
      + 'transition:transform 0.15s,opacity 0.15s;';
    btn.onmouseover = function () { btn.style.transform = 'scale(1.08)'; };
    btn.onmouseout = function () { btn.style.transform = 'scale(1)'; };
    btn.onclick = function (e) {
      e.preventDefault();
      e.stopPropagation();
      sendToMX();
    };
    document.body.appendChild(btn);
    log('Button shown');
  }

  // ===== Send to SubBridge APK =====
  function sendToMX() {
    var url = capturedUrl;
    if (!url) {
      // Try scanning right now
      scanPerf();
      url = capturedUrl;
    }
    if (!url) {
      noty('No video URL captured yet. Click a video first, then cancel the player popup.');
      return;
    }

    var payload = JSON.stringify({
      video: url,
      title: capturedTitle || 'Lampa'
    });

    log('Sending to SubBridge:', url.substring(0, 100));
    noty('Opening MXPlayer...');

    fetch(BRIDGE + '/play', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: payload
    })
    .then(function (r) { return r.json(); })
    .then(function (r) {
      if (r.status === 'ok') {
        noty('Opened in ' + (r.player || 'MXPlayer'));
      } else {
        noty('Error: ' + (r.error || 'unknown'));
      }
    })
    .catch(function (err) {
      noty('SubBridge APK not running! Start the app first.');
      log('Bridge error:', err.message);
    });
  }

  // ===== Always show button + periodic scan =====
  function init() {
    // Hook all interception methods
    hookLampaLog();
    hookConsole();
    hookListener();

    // Hook video proto early
    hookVideoProto();

    // Show button immediately (will be useful once URL is captured)
    setTimeout(showBtn, 1000);

    // Periodic scan for URL
    setInterval(function () {
      scanPerf();
      hookVideoSrc(); // Re-hook in case video element was recreated
    }, 2000);
  }

  // Run
  if (window.Lampa) {
    init();
  } else {
    document.addEventListener('DOMContentLoaded', function () {
      setTimeout(init, 2000);
    });
  }

  log('Plugin loaded v6.0');
  window.SubBridge = {
    open: sendToMX,
    url: function () { return capturedUrl; },
    hook: function () {
      log('Manual hook scan...');
      scanPerf();
      hookLampaLog();
      hookVideoProto();
      log('Current URL:', capturedUrl || '(none)');
    }
  };
})();
