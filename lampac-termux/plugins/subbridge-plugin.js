(function () {
  'use strict';

  // ============================
  // SubBridge Plugin v1.0
  // Gửi subtitle từ Lampa → MXPlayer qua SubBridge APK
  // ============================

  var BRIDGE_PORT = 8484;
  var BRIDGE_URL = 'http://127.0.0.1:' + BRIDGE_PORT;

  function log() {
    var args = ['[SubBridge]'].concat(Array.prototype.slice.call(arguments));
    console.log.apply(console, args);
  }

  function noty(msg) {
    try { Lampa.Noty.show(msg); } catch (e) { log(msg); }
  }

  // Check if SubBridge APK is running
  function checkBridge(callback) {
    $.ajax({
      url: BRIDGE_URL + '/ping',
      type: 'GET',
      timeout: 2000,
      success: function (data) {
        log('Bridge connected:', data);
        callback(true);
      },
      error: function () {
        log('Bridge not reachable');
        callback(false);
      }
    });
  }

  // Get video URL from player
  function getVideoUrl() {
    try {
      var video = document.querySelector('video');
      if (video && video.src) return video.src;
    } catch (e) {}

    try {
      var pd = Lampa.Player.playdata();
      if (pd && pd.url) return pd.url;
    } catch (e) {}

    return null;
  }

  // Get subtitle URL from plugin tracks
  function getSubUrl() {
    try {
      var subs = Lampa.Player.subtitles && Lampa.Player.subtitles();
      if (subs && subs.length > 0) {
        return subs[0].url;
      }
    } catch (e) {}

    // Check SubSense tracks
    try {
      if (window.SubSensePlugin && window.SubSensePlugin.lastTracks) {
        var tracks = window.SubSensePlugin.lastTracks;
        if (tracks.length > 0) return tracks[0].url;
      }
    } catch (e) {}

    return null;
  }

  // Send to SubBridge
  function sendToBridge(videoUrl, subUrl, title) {
    var payload = {
      video: videoUrl,
      title: title || 'Lampa'
    };

    if (subUrl) {
      // Detect format
      var clean = subUrl.split('?')[0].toLowerCase();
      payload.sub = subUrl;
      if (clean.endsWith('.srt')) payload.format = 'srt';
      else if (clean.endsWith('.ass') || clean.endsWith('.ssa')) payload.format = 'ass';
      else if (clean.endsWith('.vtt')) payload.format = 'vtt';
      else payload.format = 'srt'; // default

      payload.label = 'Vietnamese';
    }

    log('Sending to bridge:', JSON.stringify(payload).substring(0, 200));

    $.ajax({
      url: BRIDGE_URL + '/play',
      type: 'POST',
      contentType: 'application/json',
      data: JSON.stringify(payload),
      timeout: 10000,
      success: function (resp) {
        log('Bridge response:', resp);
        try {
          var r = typeof resp === 'string' ? JSON.parse(resp) : resp;
          if (r.status === 'ok') {
            noty('✓ Đã mở MXPlayer' + (r.sub === 'attached' ? ' + phụ đề' : ''));
          } else if (r.error) {
            noty('✗ Bridge: ' + r.error);
          }
        } catch (e) {
          noty('✓ Đã gửi sang MXPlayer');
        }
      },
      error: function (xhr, status) {
        log('Bridge send failed:', status);
        noty('✗ Không kết nối được SubBridge APK');
      }
    });
  }

  // Hook into Lampa player
  function addMXPlayerButton() {
    try {
      // Add button to player controls
      Lampa.Listener.follow('player', function (e) {
        if (e.type === 'render') {
          // Add MXPlayer button after player renders
          setTimeout(function () {
            var player = document.querySelector('.player');
            if (!player) return;

            // Check if button already exists
            if (document.querySelector('.subbridge-btn')) return;

            var btn = document.createElement('div');
            btn.className = 'subbridge-btn';
            btn.style.cssText = 'position:fixed;bottom:80px;right:20px;z-index:9999;' +
              'background:rgba(33,150,243,0.9);color:white;padding:10px 16px;' +
              'border-radius:8px;font-size:13px;cursor:pointer;' +
              'box-shadow:0 2px 8px rgba(0,0,0,0.3);';
            btn.textContent = '📱 MXPlayer';

            btn.onclick = function () {
              var videoUrl = getVideoUrl();
              if (!videoUrl) {
                noty('✗ Không tìm thấy video URL');
                return;
              }

              checkBridge(function (connected) {
                if (connected) {
                  sendToBridge(videoUrl, getSubUrl(), 'Lampa');
                } else {
                  noty('✗ SubBridge APK chưa chạy!\nMở app SubBridge trên điện thoại.');
                }
              });
            };

            document.body.appendChild(btn);
            log('MXPlayer button added');
          }, 2000);
        }
      });

      log('Player hook registered');
    } catch (e) {
      log('Player hook failed:', e.message);
    }
  }

  // Hook SubSense to capture subtitle tracks
  function hookSubSense() {
    try {
      // Intercept Lampa.Player.subtitles to capture tracks
      var origSubs = Lampa.Player.subtitles;
      if (typeof origSubs === 'function') {
        Lampa.Player.subtitles = function (tracks) {
          if (tracks && tracks.length > 0) {
            log('Captured', tracks.length, 'subtitle tracks');
            // Store for bridge
            if (window.SubSensePlugin) {
              window.SubSensePlugin.lastTracks = tracks;
            }
          }
          return origSubs.apply(this, arguments);
        };
        log('Subtitles hook installed');
      }
    } catch (e) {
      log('SubSense hook failed:', e.message);
    }
  }

  // Settings entry
  function addSettings() {
    try {
      Lampa.Settings.add({
        component: 'subbridge_settings',
        name: 'SubBridge MXPlayer',
        icon: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>',
        fields: [
          {
            name: 'bridge_port',
            type: 'input',
            default: '8484',
            title: 'Bridge Port',
            description: 'SubBridge APK server port'
          },
          {
            name: 'auto_bridge',
            type: 'trigger',
            default: false,
            title: 'Auto Open MXPlayer',
            description: 'Tự động mở MXPlayer khi play'
          }
        ],
        onRender: function (settings) {
          log('Settings rendered');
        }
      });
    } catch (e) {
      log('Settings add failed:', e.message);
    }
  }

  // Auto-play through MXPlayer
  function autoPlay() {
    try {
      var settings = Lampa.Settings;
      if (settings && settings.get && settings.get('subbridge_auto_bridge')) {
        Lampa.Listener.follow('player', function (e) {
          if (e.type === 'ready') {
            setTimeout(function () {
              var videoUrl = getVideoUrl();
              if (videoUrl) {
                checkBridge(function (connected) {
                  if (connected) {
                    sendToBridge(videoUrl, getSubUrl(), 'Lampa');
                  }
                });
              }
            }, 1500);
          }
        });
      }
    } catch (e) {}
  }

  // Init
  log('Plugin loaded v1.0');

  // Wait for Lampa ready
  if (window.Lampa) {
    hookSubSense();
    addMXPlayerButton();
    addSettings();
    autoPlay();
  } else {
    document.addEventListener('lampa:ready', function () {
      hookSubSense();
      addMXPlayerButton();
      addSettings();
      autoPlay();
    });
  }

  // Expose API
  window.SubBridge = {
    send: sendToBridge,
    check: checkBridge,
    getVideoUrl: getVideoUrl,
    getSubUrl: getSubUrl
  };

})();
