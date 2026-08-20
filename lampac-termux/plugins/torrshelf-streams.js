/**
 * TorrShelf Streams Plugin for Lampa
 * Adds UHDMovies, 4KHDHub, MoviesDrive, HDHub4u, Vadapav as stream sources.
 * Calls TorrShelf backend API at http://127.0.0.1:8787/api/streams
 *
 * Prerequisites:
 * - TorrShelf running on port 8787 (npm start in torr-shelf/)
 * - /api/streams endpoint added to TorrShelf (see torrshelf-api-patch.mjs)
 *
 * Install: copy to /opt/lampac/plugins/override/torrshelf-streams.js
 * Config: add to LampaWeb.customPlugins in init.conf
 */
(function () {
  'use strict';
  if (window._torrshelf_plugin) return;
  window._torrshelf_plugin = true;

  var TORRSHELF_URL = 'http://127.0.0.1:8787';
  var PLUGIN_NAME = 'TorrShelf';

  /* ============================================================
     SETTINGS
     ============================================================ */
  function loadCfg() {
    try { return JSON.parse(localStorage.getItem('torrshelf_cfg') || '{}'); }
    catch (e) { return {}; }
  }
  function saveCfg(o) {
    try {
      var c = loadCfg();
      Object.keys(o).forEach(function (k) { c[k] = o[k]; });
      localStorage.setItem('torrshelf_cfg', JSON.stringify(c));
    } catch (e) {}
  }
  function getApiUrl() {
    return loadCfg().api_url || TORRSHELF_URL;
  }

  /* ============================================================
     NETWORK
     ============================================================ */
  var network = new Lampa.Reguest();
  network.timeout(30000);

  function fetchStreams(params, callback) {
    var baseUrl = getApiUrl();
    var url = baseUrl + '/api/streams?' +
      'title=' + encodeURIComponent(params.title || '') +
      '&year=' + encodeURIComponent(params.year || '') +
      '&type=' + encodeURIComponent(params.type || 'movie') +
      '&season=' + encodeURIComponent(params.season || 0) +
      '&episode=' + encodeURIComponent(params.episode || 0) +
      '&max=' + encodeURIComponent(params.max || 12);

    network.silent(url, function (data) {
      if (typeof data === 'string') {
        try { data = JSON.parse(data); } catch (e) { data = {}; }
      }
      callback(null, data.streams || []);
    }, function (a, b) {
      callback(a || b || 'Connection failed');
    });
  }

  /* ============================================================
     INJECT STREAMS INTO LAMPA CARD
     ============================================================ */
  function injectStreams(card) {
    if (!card || !card.title) return;

    var params = {
      title: card.title || card.original_title || '',
      year: card.year || '',
      type: card.type || 'movie',
      season: card.season || 0,
      episode: card.episode || 0,
      max: 12
    };

    // Also try original_title if available
    if (card.original_title && card.original_title !== card.title) {
      params.title = card.original_title;
    }

    Lampa.Noty.show('TorrShelf: Finding streams...');

    fetchStreams(params, function (err, streams) {
      if (err || !streams.length) {
        console.log('[TorrShelf] No streams:', err || 'empty');
        return;
      }

      console.log('[TorrShelf] Found', streams.length, 'streams');

      // Add streams to Lampa's activity
      var activity = Lampa.Activity.active();
      if (activity && activity.card) {
        // Store streams on card for player to use
        activity.card.streams = streams;

        // Trigger UI update
        if (activity.activity && activity.activity.toggle) {
          activity.activity.toggle();
        }
      }
    });
  }

  /* ============================================================
     HOOK INTO LAMPA CARD DETAIL
     ============================================================ */
  function hookCardDetail() {
    Lampa.Listener.follow('full', function (e) {
      if (e.type === 'complite' && e.data) {
        var card = e.data;
        // Add TorrShelf button to detail page
        if (card.title) {
          // Small delay to let the UI render
          setTimeout(function () {
            addTorrShelfButton(card);
          }, 500);
        }
      }
    });
  }

  function addTorrShelfButton(card) {
    // Find the action buttons container
    var actions = $('.full-start__actions, .detail__actions, [class*="action"]').first();
    if (!actions.length) return;

    // Check if button already exists
    if (actions.find('.torrshelf-btn').length) return;

    var btn = $('<div class="torrshelf-btn selector" style="' +
      'padding:10px 20px;background:rgba(255,255,255,0.1);border-radius:8px;' +
      'cursor:pointer;font-weight:600;color:#fff;display:inline-block;margin:5px;' +
      'border:1px solid rgba(255,255,255,0.2);">' +
      '🔍 TorrShelf</div>');

    btn.on('hover:enter click', function () {
      showTorrShelfSelect(card);
    });

    actions.append(btn);
  }

  function showTorrShelfSelect(card) {
    var items = [
      { title: '🔍 Search all providers', action: 'search' },
      { title: '🎬 UHDMovies', action: 'uhdmovies' },
      { title: '📺 4KHDHub', action: '4khdhub' },
      { title: '🎞 MoviesDrive', action: 'moviesdrive' },
      { title: '📀 HDHub4u', action: 'hdhub4u' },
      { title: '📦 Vadapav', action: 'vadapav' }
    ];

    Lampa.Select.show({
      title: 'TorrShelf — ' + (card.title || 'Search'),
      items: items.map(function (item) {
        return { title: item.title, value: item.action };
      }),
      onSelect: function (selected) {
        searchTorrShelf(card, selected.value);
      },
      onBack: function () {
        Lampa.Controller.toggle('content');
      }
    });
  }

  function searchTorrShelf(card, provider) {
    var params = {
      title: card.original_title || card.title || '',
      year: card.year || '',
      type: card.type || 'movie',
      season: card.season || 0,
      episode: card.episode || 0,
      max: 12
    };

    Lampa.Loading.start();

    fetchStreams(params, function (err, streams) {
      Lampa.Loading.stop();

      if (err) {
        Lampa.Noty.show('TorrShelf error: ' + err);
        return;
      }

      if (!streams.length) {
        Lampa.Noty.show('No streams found on TorrShelf');
        return;
      }

      // Filter by provider if specific one selected
      if (provider !== 'search') {
        streams = streams.filter(function (s) {
          return s.name && s.name.toLowerCase().indexOf(provider.toLowerCase()) > -1;
        });
      }

      if (!streams.length) {
        Lampa.Noty.show('No streams from ' + provider);
        return;
      }

      // Show stream selection
      showStreamSelect(card, streams);
    });
  }

  function showStreamSelect(card, streams) {
    var items = streams.map(function (stream) {
      var info = (stream.title || '').split('\n');
      var title = info[0] || stream.name || 'Stream';
      var meta = info.slice(1).join(' · ') || '';
      return {
        title: title + (meta ? '\n' + meta : ''),
        value: stream
      };
    });

    Lampa.Select.show({
      title: 'TorrShelf Streams — ' + (card.title || ''),
      items: items,
      onSelect: function (selected) {
        playStream(card, selected.value);
      },
      onBack: function () {
        Lampa.Controller.toggle('content');
      }
    });
  }

  function playStream(card, stream) {
    if (!stream.url) {
      Lampa.Noty.show('No URL for this stream');
      return;
    }

    // Create playlist for episodes
    var playlist = [{
      title: (card.title || 'Video') + ' — ' + (stream.name || ''),
      url: stream.url,
      headers: stream.headers || {}
    }];

    // If series and has more episodes, could expand here
    Lampa.Player.play(playlist[0]);
    Lampa.Player.playlist(playlist);

    Lampa.Noty.show('Playing via ' + (stream.name || 'TorrShelf'));
  }

  /* ============================================================
     SETTINGS
     ============================================================ */
  function addSettings() {
    if (!Lampa.SettingsApi) return;

    Lampa.SettingsApi.addParam({
      component: 'torrshelf',
      param: {
        name: 'torrshelf_api_url',
        type: 'input',
        default: TORRSHELF_URL
      },
      field: { name: 'TorrShelf API URL' },
      onChange: function (v) {
        saveCfg({ api_url: v });
      }
    });
  }

  /* ============================================================
     INIT
     ============================================================ */
  function init() {
    hookCardDetail();
    addSettings();
    console.log('[TorrShelf Plugin] v1.0 OK');
  }

  if (window.appready) {
    setTimeout(init, 200);
  } else {
    Lampa.Listener.follow('app', function (e) {
      if (e.type === 'ready') setTimeout(init, 200);
    });
  }
})();
