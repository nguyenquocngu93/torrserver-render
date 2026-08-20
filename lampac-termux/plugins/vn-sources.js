/**
 * Vietnamese Sources Plugin for Lampa
 * Sources: KKPhim, OPhim, UHDMovie, 4KHDHub
 * Based on kkphim-parser-lampa.js v2.0
 *
 * Install: copy to /opt/lampac/plugins/override/vn-sources.js
 * Config: add "vn-sources" to LampaWeb.initPlugins or load via lampainit.js
 */
(function () {
  'use strict';
  if (window._vn_sources_plugin) return;
  window._vn_sources_plugin = true;

  /* ============================================================
     CONFIG — All 4 sources
     ============================================================ */
  var SOURCES = {
    kkphim: {
      name: 'KKPhim',
      api: 'https://phimapi.com/',
      img: 'https://phimimg.com/',
      enabled: true
    },
    ophim: {
      name: 'OPhim',
      api: 'https://ophim1.com/',
      img: 'https://img.ophim.live/uploads/movies/',
      enabled: true
    },
    uhdmovie: {
      name: 'UHDMovie',
      api: 'https://uhdmovie.to/',
      img: 'https://uhdmovie.to/uploads/movies/',
      enabled: true
    },
    fourkhdhub: {
      name: '4KHDHub',
      api: 'https://4khdhub.com/',
      img: 'https://4khdhub.com/uploads/movies/',
      enabled: true
    }
  };

  var SOURCE_NAME = 'vn_sources';
  var SOURCE_TITLE = 'Phim Viet';

  /* ============================================================
     STORAGE
     ============================================================ */
  function loadCfg() {
    try { return JSON.parse(localStorage.getItem('vn_sources_cfg') || '{}'); }
    catch (e) { return {}; }
  }
  function saveCfg(o) {
    try {
      var c = loadCfg();
      Object.keys(o).forEach(function (k) { c[k] = o[k]; });
      localStorage.setItem('vn_sources_cfg', JSON.stringify(c));
    } catch (e) {}
  }
  function isEnabled(key) {
    var c = loadCfg();
    if (c['src_' + key] === undefined) return SOURCES[key] ? SOURCES[key].enabled : false;
    return c['src_' + key] === true;
  }
  function getActiveSource() {
    return loadCfg().active_source || 'kkphim';
  }

  /* ============================================================
     NETWORK
     ============================================================ */
  var network = new Lampa.Reguest();
  network.timeout(15000);

  function getJSON(url, onOk, onErr) {
    network.silent(url, function (data) {
      if (typeof data === 'string') {
        try { onOk(JSON.parse(data)); } catch (e) { onOk(null); }
      } else {
        onOk(data);
      }
    }, function (a, b) {
      if (onErr) onErr(a || b || 'error');
    });
  }

  /* ============================================================
     UTILITIES
     ============================================================ */
  function s_(v) { return v == null ? '' : String(v); }
  function num(v, fb) { var n = parseInt(v, 10); return isNaN(n) ? (fb || 0) : n; }

  function nStr(str) {
    return s_(str).toLowerCase().trim()
      .replace(/[^\w\s\u00C0-\u024F\u1E00-\u1EFF]/g, '')
      .replace(/\s+/g, ' ');
  }

  function getBaseName(name) {
    if (!name) return '';
    return s_(name)
      .replace(/[\s\-]*[\(\[]?\s*[Ss]eason\s*\d+\s*[\)\]]?/gi, '')
      .replace(/[\s\-]*[\(\[]?\s*[Pp]h[aầ]n\s*\d+\s*[\)\]]?/gi, '')
      .replace(/[\s\-]*[\(\[]?\s*[Mm][uù]a\s*\d+\s*[\)\]]?/gi, '')
      .replace(/[\s\-]*\bS\d+\b/g, '')
      .trim();
  }

  function fixImg(u, srcKey) {
    if (!u) return '';
    if (u.indexOf('http') === 0) return u;
    return (SOURCES[srcKey] || SOURCES.kkphim).img + u;
  }

  /* ============================================================
     SCORING — match quality
     ============================================================ */
  function mScore(item, title, orig, year) {
    if (!item) return 0;
    var score = 0;
    var nT = nStr(title), nO = nStr(orig);
    var n1 = nStr(item.name || item.title);
    var n2 = nStr(item.origin_name || item.original_name);
    var nTb = nStr(getBaseName(title));
    var nOb = nStr(getBaseName(orig));
    var n1b = nStr(getBaseName(item.name || item.title));
    var n2b = nStr(getBaseName(item.origin_name || item.original_name));

    if (nT && (n1 === nT || n2 === nT)) score += 100;
    else if (nO && nO !== nT && (n1 === nO || n2 === nO)) score += 100;
    else if (nTb && (n1b === nTb || n2b === nTb)) score += 90;
    else if (nOb && nOb !== nTb && (n1b === nOb || n2b === nOb)) score += 90;
    else if (nT && nT.length >= 3 && (n1.indexOf(nT) > -1 || nT.indexOf(n1) > -1)) score += 60;
    else if (nO && nO.length >= 3 && (n1.indexOf(nO) > -1 || nO.indexOf(n1) > -1)) score += 55;
    else if (nTb && nTb.length >= 3 && (n1b.indexOf(nTb) > -1 || nTb.indexOf(n1b) > -1)) score += 40;
    else if (nOb && nOb.length >= 3 && (n2b.indexOf(nOb) > -1 || nOb.indexOf(n1b) > -1)) score += 40;

    if (score > 0 && year && item.year) {
      var iy = num(item.year);
      var ty = num(year);
      if (iy === ty) score += 30;
      else if (Math.abs(iy - ty) <= 1) score += 15;
    }
    return score;
  }

  function mBest(items, title, orig, year) {
    if (!items || !items.length) return null;
    var scored = items.map(function (it) {
      return { item: it, score: mScore(it, title, orig, year) };
    });
    scored.sort(function (a, b) { return b.score - a.score; });
    if (scored[0].score > 0) return scored[0].item;
    if (items.length === 1) return items[0];
    if (year && items.length <= 3) return items[0];
    return null;
  }

  /* ============================================================
     API CALLS — works for KKPhim, OPhim, and compatible APIs
     ============================================================ */
  function searchAPI(srcKey, kw, page) {
    var src = SOURCES[srcKey];
    if (!src) return Promise.resolve([]);
    return new Promise(function (resolve) {
      getJSON(
        src.api + 'v1/api/tim-kiem?keyword=' + encodeURIComponent(kw) +
        '&limit=20&page=' + (page || 1),
        function (d) {
          if (!d) return resolve([]);
          var items = (d.data && d.data.items) || d.items || [];
          resolve(items.filter(function (i) { return i && i.slug; }));
        },
        function () { resolve([]); }
      );
    });
  }

  function detailAPI(srcKey, slug) {
    var src = SOURCES[srcKey];
    if (!src) return Promise.resolve(null);
    return new Promise(function (resolve) {
      getJSON(src.api + 'v1/api/phim/' + slug, function (d) {
        if (!d) return resolve(null);
        if (d.status === 'success' && d.data) {
          return resolve({
            movie: d.data.item || {},
            episodes: d.data.episodes || []
          });
        }
        resolve(null);
      }, function () { resolve(null); });
    });
  }

  function listAPI(srcKey, cat, page) {
    var src = SOURCES[srcKey];
    if (!src) return Promise.resolve({ items: [], total_pages: 1 });
    return new Promise(function (resolve) {
      getJSON(
        src.api + 'v1/api/danh-sach/' + cat + '?page=' + (page || 1),
        function (d) {
          if (!d || !d.data) return resolve({ items: [], total_pages: 1 });
          var data = d.data;
          resolve({
            items: (data.items || []).filter(function (i) { return i && i.slug; }),
            total_pages: data.totalPages || 1
          });
        },
        function () { resolve({ items: [], total_pages: 1 }); }
      );
    });
  }

  /* ============================================================
     CONVERT TO LAMPA FORMAT
     ============================================================ */
  function convertItem(item, srcKey) {
    if (!item) return null;
    var ec = s_(item.episode_current);
    var isSeries = item.type === 'series' || item.type === 'tvshows' ||
      (ec && ec !== 'Full' && ec !== 'full');
    var poster = fixImg(item.poster_url || item.thumb_url, srcKey);
    var title = s_(item.name || item.title);
    var orig = s_(item.origin_name || item.original_name);
    var year = s_(item.year);

    return {
      source: SOURCE_NAME,
      type: isSeries ? 'tv' : 'movie',
      adult: false,
      id: SOURCE_NAME + '_' + (item.slug || ''),
      title: title,
      original_title: orig,
      overview: s_(item.content || item.description || ''),
      img: poster,
      background_image: poster,
      genres: [],
      production_companies: [],
      production_countries: [],
      vote_average: parseFloat(item.tmdb && item.tmdb.vote_average) || 0,
      vote_count: 0,
      year: year,
      release_date: year ? (year + '-01-01') : '',
      first_air_date: year ? (year + '-01-01') : '',
      _raw: item,
      _srcKey: srcKey,
      _slug: s_(item.slug)
    };
  }

  /* ============================================================
     SOURCE METHODS — Lampa.Api.sources interface
     ============================================================ */
  function main(params, oncomplite) {
    oncomplite([
      { title: 'Phim Moi Cap Nhat', url: 'phim-moi-cap-nhat', component: 'category_full', source: SOURCE_NAME },
      { title: 'Phim Bo', url: 'phim-bo', component: 'category_full', source: SOURCE_NAME },
      { title: 'Phim Le', url: 'phim-le', component: 'category_full', source: SOURCE_NAME },
      { title: 'Hoat HinH', url: 'hoat-hinh', component: 'category_full', source: SOURCE_NAME },
      { title: 'TV Shows', url: 'tv-shows', component: 'category_full', source: SOURCE_NAME }
    ]);
  }

  function menu(params, oncomplite) {
    oncomplite([
      { title: 'Phim Moi Cap Nhat', url: 'phim-moi-cap-nhat' },
      { title: 'Phim Bo', url: 'phim-bo' },
      { title: 'Phim Le', url: 'phim-le' },
      { title: 'Hoat HinH', url: 'hoat-hinh' },
      { title: 'TV Shows', url: 'tv-shows' }
    ]);
  }

  function list(params, oncomplite) {
    var srcKey = getActiveSource();
    var cat = params.url || 'phim-moi-cap-nhat';
    var page = params.page || 1;
    listAPI(srcKey, cat, page).then(function (res) {
      var items = (res.items || []).map(function (i) { return convertItem(i, srcKey); }).filter(Boolean);
      oncomplite({
        results: items,
        page: page,
        total_pages: res.total_pages || 1
      });
    });
  }

  function category(params, oncomplite) {
    list(params, oncomplite);
  }

  function full(params, oncomplite) {
    var card = params.card || params.movie || params;
    var srcKey = card._srcKey || getActiveSource();
    var slug = card._slug || s_(card.id).replace(SOURCE_NAME + '_', '');
    if (!slug) { oncomplite({}); return; }

    detailAPI(srcKey, slug).then(function (det) {
      if (!det) { oncomplite({}); return; }
      var m = det.movie || {};
      oncomplite({
        source: SOURCE_NAME,
        type: card.type || (m.type === 'series' ? 'tv' : 'movie'),
        id: SOURCE_NAME + '_' + slug,
        title: s_(m.name || m.title),
        original_title: s_(m.origin_name || m.original_name),
        overview: s_(m.content || m.description || ''),
        img: fixImg(m.poster_url || m.thumb_url, srcKey),
        background_image: fixImg(m.poster_url || m.thumb_url, srcKey),
        year: s_(m.year),
        release_date: s_(m.year) ? s_(m.year) + '-01-01' : '',
        first_air_date: s_(m.year) ? s_(m.year) + '-01-01' : '',
        _episodes: det.episodes || [],
        _srcKey: srcKey,
        _slug: slug,
        _raw: m
      });
    });
  }

  function search(params, oncomplite) {
    var srcKey = getActiveSource();
    var query = params.query || params.title || '';
    var page = params.page || 1;

    // Search active source first, fallback to others
    searchAPI(srcKey, query, page).then(function (items) {
      if (items.length > 0) {
        var results = items.map(function (i) { return convertItem(i, srcKey); }).filter(Boolean);
        oncomplite({ results: results, page: page, total_pages: 1 });
      } else {
        // Try other enabled sources
        var keys = Object.keys(SOURCES).filter(function (k) { return k !== srcKey && isEnabled(k); });
        var tried = 0;
        if (keys.length === 0) {
          oncomplite({ results: [], page: 1, total_pages: 1 });
          return;
        }
        keys.forEach(function (k) {
          searchAPI(k, query, page).then(function (items2) {
            tried++;
            if (items2.length > 0 && !results_sent) {
              results_sent = true;
              var results = items2.map(function (i) { return convertItem(i, k); }).filter(Boolean);
              oncomplite({ results: results, page: page, total_pages: 1 });
            }
            if (tried >= keys.length && !results_sent) {
              results_sent = true;
              oncomplite({ results: [], page: 1, total_pages: 1 });
            }
          });
        });
        var results_sent = false;
      }
    });
  }

  function searchDiscovery(params, oncomplite) {
    search(params, oncomplite);
  }

  function person(params, oncomplite) { oncomplite({}); }

  function seasons(tv, from, oncomplite) {
    var status = new Lampa.Status(from.length);
    status.onComplite = oncomplite;
    from.forEach(function (sn) {
      status.append(String(sn), {
        season_number: sn,
        episodes: [],
        air_date: ''
      });
    });
  }

  function clear() { network.clear(); }

  function discovery() {
    return {
      title: SOURCE_TITLE,
      search: searchDiscovery,
      params: {
        align_left: true,
        object: { source: SOURCE_NAME }
      },
      onMore: function (params) {
        Lampa.Activity.push({
          url: '',
          title: 'Phim Viet: ' + params.query,
          component: 'category_full',
          page: 1,
          query: encodeURIComponent(params.query),
          source: SOURCE_NAME
        });
      },
      onCancel: network.clear.bind(network)
    };
  }

  /* ============================================================
     PLUGIN OBJECT
     ============================================================ */
  var VN = {
    SOURCE_NAME: SOURCE_NAME,
    SOURCE_TITLE: SOURCE_TITLE,
    main: main,
    menu: menu,
    full: full,
    list: list,
    category: category,
    search: search,
    clear: clear,
    person: person,
    seasons: seasons,
    discovery: discovery
  };

  /* ============================================================
     REGISTER PLUGIN
     ============================================================ */
  function addPlugin() {
    if (Lampa.Api.sources && Lampa.Api.sources[SOURCE_NAME]) {
      console.log('[VN Sources] Already registered');
      return;
    }

    // Register source
    Lampa.Api.sources[SOURCE_NAME] = VN;

    // Add to source selector
    var sources = {};
    if (Lampa.Params && Lampa.Params.values && Lampa.Params.values['source']) {
      Lampa.Arrays.extend(sources, Lampa.Params.values['source']);
    }
    sources[SOURCE_NAME] = SOURCE_TITLE;
    Lampa.Params.select('source', sources, 'tmdb');

    // Settings
    if (Lampa.SettingsApi) {
      // Source selector
      Lampa.SettingsApi.addParam({
        component: 'source',
        param: {
          name: 'vn_active_source',
          type: 'select',
          values: {
            'kkphim': 'KKPhim (phimapi.com)',
            'ophim': 'OPhim (ophim1.com)',
            'uhdmovie': 'UHDMovie',
            'fourkhdhub': '4KHDHub'
          },
          default: 'kkphim'
        },
        field: { name: 'Phim Viet - Nguon mac dinh' },
        onChange: function (v) { saveCfg({ active_source: v }); }
      });

      // Toggle each source
      Object.keys(SOURCES).forEach(function (key) {
        Lampa.SettingsApi.addParam({
          component: 'source',
          param: {
            name: 'vn_src_' + key,
            type: 'select',
            values: { 'on': 'Bat', 'off': 'Tat' },
            default: 'on'
          },
          field: { name: '  ' + SOURCES[key].name },
          onChange: function (v) {
            var obj = {};
            obj['src_' + key] = v === 'on';
            saveCfg(obj);
          }
        });
      });
    }

    Lampa.Noty.show('Phim Viet sources da san sang!');
    console.log('[VN Sources] v2.0 OK — 4 sources registered');
  }

  if (window.appready) {
    setTimeout(addPlugin, 100);
  } else {
    Lampa.Listener.follow('app', function (e) {
      if (e.type === 'ready') setTimeout(addPlugin, 100);
    });
  }
})();
