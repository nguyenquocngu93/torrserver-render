/**
 * lampa-mxplayer-bridge.js — Bridge Lampa → MXPlayer with subtitles
 * 
 * Flow:
 * 1. User clicks play in Lampa
 * 2. Bridge intercepts → gets video URL + subtitle URLs
 * 3. Sends Intent to MXPlayer with video + subtitles
 * 4. MXPlayer plays video with external subtitles
 * 
 * MXPlayer Intent extras:
 *   - data: video URL
 *   - subs: ArrayList<Uri> of subtitle file URLs
 *   - subs_name: ArrayList<String> of subtitle display names
 * 
 * Deploy: /opt/lampac/plugins/override/lampa-mxplayer-bridge.js
 * Config: add to LampaWeb.customPlugins in init.conf
 */
(function(){
  'use strict';
  if(!window.Lampa) return;
  if(window._mxplayer_bridge) return;
  window._mxplayer_bridge = true;

  var BRIDGE_PORT = parseInt(localStorage.getItem('mx_bridge_port') || '8484');
  var BRIDGE_URL = 'http://127.0.0.1:' + BRIDGE_PORT;
  var USE_BRIDGE = localStorage.getItem('mx_use_bridge') !== 'false';

  /* ─── 1. Intercept player ──────────────────────────────── */
  function interceptPlayer(){
    if(!window.Lampa.Player) return;

    var origPlay = Lampa.Player.play;
    Lampa.Player.play = function(item){
      if(!item || !item.url){
        return origPlay.call(this, item);
      }

      /* Check if should use MXPlayer */
      if(!isMXPlayerEnabled()){
        return origPlay.call(this, item);
      }

      /* Gather subtitle info */
      var videoUrl = item.url;
      var subtitles = item.subtitles || [];
      var title = item.title || 'Video';

      /* Try to launch MXPlayer via bridge */
      launchMXPlayer(videoUrl, subtitles, title);
    };
  }

  /* ─── 2. Check if MXPlayer mode enabled ────────────────── */
  function isMXPlayerEnabled(){
    return localStorage.getItem('mx_player_mode') === 'true';
  }

  /* ─── 3. Launch MXPlayer via bridge server ──────────────── */
  function launchMXPlayer(videoUrl, subtitles, title){
    var payload = {
      video: videoUrl,
      title: title,
      subtitles: subtitles.map(function(s){
        return {
          url: s.url || s.file || '',
          label: s.label || s.language || 'Subtitle',
          format: s.format || detectFormat(s.url || s.file || '')
        };
      })
    };

    /* Method 1: Try bridge server (Node.js on Termux) */
    fetch(BRIDGE_URL + '/play', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(payload)
    })
    .then(function(r){ return r.json(); })
    .then(function(data){
      if(data.ok){
        Lampa.Noty.show('Đã gửi sang MXPlayer');
      } else {
        Lampa.Noty.show('Bridge error: ' + (data.error || 'unknown'));
      }
    })
    .catch(function(){
      /* Method 2: Try Android Intent directly (if in WebView) */
      launchViaIntent(videoUrl, subtitles, title);
    });
  }

  /* ─── 4. Launch via Android Intent (fallback) ───────────── */
  function launchViaIntent(videoUrl, subtitles, title){
    /* If running in Lampa Android app */
    if(window.Lampa && Lampa.Android && Lampa.Android.openPlayer){
      var intentData = {
        url: videoUrl,
        title: title,
        subtitles: subtitles
      };
      /* Custom intent with subtitle support */
      try {
        /* Try sending via custom scheme */
        window.location.href = 'lampa://play?' + encodeURIComponent(JSON.stringify(intentData));
      } catch(e){
        Lampa.Noty.show('Không thể mở MXPlayer. Cài bridge server.');
      }
    } else {
      /* Web mode - show instructions */
      showManualPlay(videoUrl, subtitles, title);
    }
  }

  /* ─── 5. Show manual play dialog ────────────────────────── */
  function showManualPlay(videoUrl, subtitles, title){
    var body = document.createElement('div');
    body.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.85);z-index:9999;display:flex;align-items:center;justify-content:center;';

    var dialog = document.createElement('div');
    dialog.style.cssText = 'background:#1a1a2e;border-radius:16px;padding:24px;max-width:500px;width:90%;max-height:80vh;overflow-y:auto;color:#fff;';

    var h = document.createElement('h3');
    h.style.cssText = 'margin:0 0 16px;color:#00d4ff;font-size:18px;';
    h.textContent = '📱 Mở MXPlayer';
    dialog.appendChild(h);

    var info = document.createElement('p');
    info.style.cssText = 'color:#aaa;margin:0 0 16px;font-size:13px;';
    info.textContent = title;
    dialog.appendChild(info);

    /* Video URL */
    var vidLabel = document.createElement('label');
    vidLabel.style.cssText = 'color:#888;font-size:11px;display:block;margin-bottom:4px;';
    vidLabel.textContent = 'Video URL:';
    dialog.appendChild(vidLabel);

    var vidInput = createCopyInput(videoUrl);
    dialog.appendChild(vidInput);

    /* Subtitle URLs */
    if(subtitles && subtitles.length){
      var subHeader = document.createElement('div');
      subHeader.style.cssText = 'margin:16px 0 8px;color:#00d4ff;font-size:14px;font-weight:600;';
      subHeader.textContent = '📋 Subtitle files:';
      dialog.appendChild(subHeader);

      subtitles.forEach(function(sub, i){
        if(!sub.url) return;

        var subLabel = document.createElement('label');
        subLabel.style.cssText = 'color:#888;font-size:11px;display:block;margin-bottom:4px;margin-top:8px;';
        subLabel.textContent = (sub.label || 'Sub ' + (i+1)) + ' (' + (sub.format || 'srt') + '):';
        dialog.appendChild(subLabel);

        var subInput = createCopyInput(sub.url);
        dialog.appendChild(subInput);
      });
    }

    /* Instructions */
    var instr = document.createElement('div');
    instr.style.cssText = 'margin:16px 0;padding:12px;background:#16213e;border-radius:8px;font-size:12px;color:#ccc;line-height:1.6;';
    instr.innerHTML = 
      '<b style="color:#00d4ff;">Hướng dẫn:</b><br>' +
      '1. Copy Video URL → Mở MXPlayer → Nhập URL<br>' +
      '2. Copy Subtitle URL → MXPlayer → Settings → Subtitle → Load<br>' +
      '3. Hoặc cài Bridge Server để tự động:<br>' +
      '<code style="color:#f39c12;">sh lampac-termux/setup-mxplayer-bridge.sh</code>';
    dialog.appendChild(instr);

    /* Close button */
    var close = document.createElement('div');
    close.style.cssText = 'padding:12px;margin-top:16px;background:#e74c3c;border-radius:8px;text-align:center;cursor:pointer;font-weight:600;';
    close.textContent = 'Đóng';
    close.onclick = function(){ body.remove(); };
    dialog.appendChild(close);

    body.appendChild(dialog);
    body.onclick = function(e){ if(e.target===body) body.remove(); };
    document.body.appendChild(body);
  }

  /* ─── 6. Create copy-able input ─────────────────────────── */
  function createCopyInput(value){
    var wrap = document.createElement('div');
    wrap.style.cssText = 'display:flex;gap:8px;margin-bottom:4px;';

    var input = document.createElement('input');
    input.type = 'text';
    input.value = value;
    input.readOnly = true;
    input.style.cssText = 'flex:1;padding:8px 12px;border-radius:6px;border:1px solid #333;background:#0f0f23;color:#00d4ff;font-size:12px;font-family:monospace;';

    var btn = document.createElement('div');
    btn.style.cssText = 'padding:8px 12px;background:#2ecc71;border-radius:6px;cursor:pointer;font-size:12px;font-weight:600;white-space:nowrap;';
    btn.textContent = 'Copy';
    btn.onclick = function(){
      input.select();
      document.execCommand('copy');
      btn.textContent = '✓';
      setTimeout(function(){ btn.textContent = 'Copy'; }, 1500);
    };

    wrap.appendChild(input);
    wrap.appendChild(btn);
    return wrap;
  }

  /* ─── 7. Detect subtitle format ─────────────────────────── */
  function detectFormat(url){
    if(!url) return 'srt';
    var lower = url.toLowerCase();
    if(lower.indexOf('.ass') > -1 || lower.indexOf('.ssa') > -1) return 'ass';
    if(lower.indexOf('.vtt') > -1) return 'vtt';
    if(lower.indexOf('.sub') > -1) return 'sub';
    return 'srt';
  }

  /* ─── 8. Add settings ───────────────────────────────────── */
  function addSettings(){
    if(!Lampa.SettingsApi) return;

    Lampa.SettingsApi.addParam({
      component: 'mxplayer',
      param: {
        name: 'mx_player_mode',
        type: 'toggle',
        default: false
      },
      field: { name: 'Mở bằng MXPlayer' },
      onChange: function(v){
        localStorage.setItem('mx_player_mode', v ? 'true' : 'false');
      }
    });

    Lampa.SettingsApi.addParam({
      component: 'mxplayer',
      param: {
        name: 'mx_bridge_port',
        type: 'input',
        default: '8484'
      },
      field: { name: 'Bridge Server Port' },
      onChange: function(v){
        localStorage.setItem('mx_bridge_port', v || '8484');
        BRIDGE_PORT = parseInt(v || '8484');
        BRIDGE_URL = 'http://127.0.0.1:' + BRIDGE_PORT;
      }
    });
  }

  /* ─── 9. Add MXPlayer button to detail page ─────────────── */
  function hookCardDetail(){
    Lampa.Listener.follow('full', function(e){
      if(e.type === 'complite' && e.data && e.data.title){
        setTimeout(function(){
          addMXPlayerButton(e.data);
        }, 500);
      }
    });
  }

  function addMXPlayerButton(card){
    var actions = document.querySelector('.full-start__actions, .detail__actions');
    if(!actions) return;
    if(actions.querySelector('.mxplayer-btn')) return;

    var btn = document.createElement('div');
    btn.className = 'selector mxplayer-btn';
    btn.style.cssText = 'padding:10px 16px;background:rgba(0,212,255,0.15);border-radius:8px;cursor:pointer;font-weight:600;color:#00d4ff;display:inline-block;margin:4px;border:1px solid rgba(0,212,255,0.3);font-size:13px;';
    btn.textContent = '📱 MXPlayer';

    btn.onclick = function(){
      /* Get stream URLs for this card */
      getStreamsForCard(card, function(streams){
        if(!streams || !streams.length){
          Lampa.Noty.show('Không tìm thấy stream');
          return;
        }

        var stream = streams[0];
        var subs = [];

        /* Extract subtitles from streams */
        streams.forEach(function(s){
          if(s.subtitles && s.subtitles.length){
            subs = subs.concat(s.subtitles);
          }
        });

        /* Also check for subtitle tracks */
        if(stream.subtitles){
          subs = subs.concat(stream.subtitles);
        }

        launchMXPlayer(stream.url, subs, card.title);
      });
    };

    actions.appendChild(btn);
  }

  function getStreamsForCard(card, cb){
    /* Try to get streams from Lampa's activity */
    var activity = Lampa.Activity.active();
    if(activity && activity.card && activity.card.streams){
      cb(activity.card.streams);
      return;
    }

    /* Try TorrShelf API */
    var torrshelf = localStorage.getItem('vn_torrshelf') || 'http://127.0.0.1:8787';
    fetch(torrshelf + '/api/streams?title=' + encodeURIComponent(card.title || '') + '&year=' + encodeURIComponent(card.year || ''))
      .then(function(r){ return r.json(); })
      .then(function(d){ cb(d.streams || []); })
      .catch(function(){ cb([]); });
  }

  /* ─── 10. Init ──────────────────────────────────────────── */
  function init(){
    interceptPlayer();
    hookCardDetail();
    addSettings();
    console.log('[MXPlayer Bridge] v1.0 active');
  }

  if(window.appready){
    setTimeout(init, 200);
  } else {
    Lampa.Listener.follow('app', function(e){
      if(e.type === 'ready') setTimeout(init, 200);
    });
  }
})();
