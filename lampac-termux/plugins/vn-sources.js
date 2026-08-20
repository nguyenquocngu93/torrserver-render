/**
 * vn-sources.js — Vietnamese Sources Plugin for Lampa / Lampac
 * 
 * Tích hợp 4 nguồn phim Việt: KKPhim, OPhim, UHDMovie, 4KHDHub
 * Kết nối với TorrShelf (port 8787) để scraping
 * hoặc scrape trực tiếp nếu TorrShelf không khả dụng.
 * 
 * Deploy: cp vn-sources.js /opt/lampac/plugins/override/
 * Config: thêm LampaWeb.customPlugins trong init.conf
 */
(function () {
  'use strict';

  if (typeof Lampa === 'undefined') return;

  /* ─── Config ────────────────────────────────────────────── */
  var TORRSHELF = localStorage.getItem('vn_torrshelf') || 'http://127.0.0.1:8787';
  var network   = new Lampa.Reguest();
  var sources   = [
    {
      id:    'kkphim',
      name:  'KKPhim',
      color: '#e74c3c',
      slug:  'kkphim',
      base:  'https://khophim.co',
      icon:  '🎬'
    },
    {
      id:    'ophim',
      name:  'OPhim',
      color: '#3498db',
      slug:  'ophim',
      base:  'https://ophim.me',
      icon:  '🎞️'
    },
    {
      id:    'uhdmovie',
      name:  'UHDMovie',
      color: '#2ecc71',
      slug:  'uhdmovie',
      base:  'https://uhdmovie.dev',
      icon:  '📺'
    },
    {
      id:    'khd4k',
      name:  '4KHDHub',
      color: '#f39c12',
      slug:  'khd4k',
      base:  'https://4khdhub.com',
      icon:  '🌟'
    }
  ];

  /* ─── Manifest ──────────────────────────────────────────── */
  Lampa.Manifest.plugins = {
    name:    'Phim Việt',
    version: '1.0.0',
    description: 'Nguồn phim Việt: KKPhim, OPhim, UHDMovie, 4KHDHub'
  };

  /* ─── Helpers ───────────────────────────────────────────── */

  function trim(s) {
    return (s || '').replace(/^\s+|\s+$/g, '');
  }

  function htmlDecode(s) {
    if (!s) return '';
    var el = document.createElement('textarea');
    el.innerHTML = s;
    return el.value;
  }

  function fetchJSON(url, callback, errback) {
    network.silent(url, function (data) {
      callback(data);
    }, function () {
      if (errback) errback();
    }, false, { timeout: 15000 });
  }

  /* ─── TorrShelf API ─────────────────────────────────────── */

  function torrshelfSearch(query, sourceId, callback) {
    var url = TORRSHELF + '/api/search?keyword=' + encodeURIComponent(query);
    if (sourceId) url += '&source=' + sourceId;
    fetchJSON(url, callback, function () { callback([]); });
  }

  function torrshelfStreams(id, callback) {
    fetchJSON(TORRSHELF + '/api/streams?id=' + encodeURIComponent(id), callback, function () { callback([]); });
  }

  /* ─── Direct Scrape (fallback) ──────────────────────────── */

  function directSearch(source, query, callback) {
    // Thử TorrShelf trước
    torrshelfSearch(query, source.slug, function (data) {
      if (data && data.length) return callback(data);

      // Fallback: scrape trực tiếp từ web nguồn
      var searchUrl = getSearchUrl(source, query);
      if (!searchUrl) return callback([]);

      fetchJSON(searchUrl, function (html) {
        callback(parseSearchResult(source, html));
      }, function () { callback([]); });
    });
  }

  function getSearchUrl(source, query) {
    var q = encodeURIComponent(query);
    return source.base + '/ajax/movie/search?keyword=' + q;
  }

  function parseSearchResult(source, html) {
    var results = [];
    if (typeof html === 'string') {
      try {
        var tmp = document.createElement('div');
        tmp.innerHTML = html;
        var items = tmp.querySelectorAll('.flw-item, .film_list-wrap .flw-item, .item');
        items.forEach(function (el) {
          var link  = el.querySelector('a');
          var img   = el.querySelector('img');
          var title = el.querySelector('.film-name, h3, .film-title');
          var year  = el.querySelector('.fd-infor, .fdi-item');
          var qual  = el.querySelector('.pick, .quality');

          if (link) {
            results.push({
              id:         link.getAttribute('href') || '',
              title:      trim(title ? title.textContent : ''),
              poster:     img ? (img.getAttribute('data-src') || img.getAttribute('src') || '') : '',
              year:       year ? trim(year.textContent) : '',
              quality:    qual ? trim(qual.textContent) : '',
              source:     source.id,
              sourceName: source.name
            });
          }
        });
      } catch (e) { /* ignore parse errors */ }
    } else if (Array.isArray(html)) {
      results = html;
    }
    return results;
  }

  function directStreams(card, callback) {
    if (card.streams && card.streams.length) return callback(card.streams);
    torrshelfStreams(card.id, function (data) {
      callback(data || []);
    });
  }

  /* ─── Source Component Factory ──────────────────────────── */

  function makeSource(src) {
    return function (object) {
      var comp = new Lampa.CompactDetail(object);
      var self = this;

      comp.create = function () {
        comp.build = function () {
          comp.append(new Lampa.Title({
            title: src.icon + ' ' + src.name,
            border: true
          }));
        };
      };

      comp.start = function () {
        comp.build();
      };

      self.onSearch = function (query) {
        directSearch(src, query, function (items) {
          self.drawItems(comp, items);
        });
      };

      self.drawItems = function (container, items) {
        if (!items || !items.length) {
          container.append(new Lampa.Empty({ title: 'Không tìm thấy' }));
          return;
        }

        items.forEach(function (item) {
          var card = new Lampa.Card({
            title:    item.title,
            poster:   item.poster,
            year:     item.year || '',
            quality:  item.quality || '',
            card_data: item
          });

          card.on('click', function () {
            self.openItem(item);
          });

          container.append(card);
        });
      };

      self.openItem = function (item) {
        directStreams(item, function (streams) {
          if (!streams || !streams.length) {
            Lampa.Noty.show('Không có stream khả dụng');
            return;
          }

          if (streams.length > 1) {
            self.showEpisodes(item, streams);
          } else {
            self.play(streams[0]);
          }
        });
      };

      self.showEpisodes = function (item, streams) {
        var body = [];
        streams.forEach(function (s, i) {
          body.push({
            title:   s.title || ('Tập ' + (i + 1)),
            quality: s.quality || '',
            index:   i
          });
        });

        var list = new Lampa.Select({
          title: item.title + ' — Chọn tập',
          items: body,
          onSelect: function (el) {
            self.play(streams[el.index]);
            list.close();
          }
        });
        list.create();
      };

      self.play = function (stream) {
        var video = {
          title:     stream.title || stream.url,
          url:       stream.url || stream.magnet || '',
          quality:   stream.quality || '',
          subtitles: stream.subtitles || []
        };

        Lampa.Player.play(video);
      };

      return comp;
    };
  }

  /* ─── Bulk Search (tất cả nguồn) ────────────────────────── */

  function makeAllSource(object) {
    var comp = new Lampa.CompactDetail(object);
    var self = this;

    comp.create = function () {
      comp.build = function () {
        comp.append(new Lampa.Title({
          title: '🇻🇳 Tất cả nguồn Việt',
          border: true
        }));
      };
    };

    comp.start = function () {
      comp.build();
    };

    self.onSearch = function (query) {
      var allItems = [];
      var done = 0;
      sources.forEach(function (src) {
        directSearch(src, query, function (items) {
          allItems = allItems.concat(items);
          done++;
          if (done === sources.length) {
            self.drawItems(comp, allItems);
          }
        });
      });
    };

    self.drawItems = function (container, items) {
      if (!items || !items.length) {
        container.append(new Lampa.Empty({ title: 'Không tìm thấy' }));
        return;
      }

      items.forEach(function (item) {
        var src = sources.find(function (s) { return s.id === item.source; }) || {};
        var card = new Lampa.Card({
          title:    '[' + (src.name || item.source || '') + '] ' + item.title,
          poster:   item.poster,
          year:     item.year || '',
          quality:  item.quality || '',
          card_data: item
        });

        card.on('click', function () {
          self.openItem(item);
        });

        container.append(card);
      });
    };

    self.openItem = function (item) {
      directStreams(item, function (streams) {
        if (!streams || !streams.length) {
          Lampa.Noty.show('Không có stream khả dụng');
          return;
        }
        if (streams.length > 1) {
          self.showEpisodes(item, streams);
        } else {
          self.play(streams[0]);
        }
      });
    };

    self.showEpisodes = function (item, streams) {
      var body = [];
      streams.forEach(function (s, i) {
        body.push({
          title:   s.title || ('Tập ' + (i + 1)),
          quality: s.quality || '',
          index:   i
        });
      });
      var list = new Lampa.Select({
        title: item.title + ' — Chọn tập',
        items: body,
        onSelect: function (el) {
          self.play(streams[el.index]);
          list.close();
        }
      });
      list.create();
    };

    self.play = function (stream) {
      var video = {
        title:     stream.title || stream.url,
        url:       stream.url || stream.magnet || '',
        quality:   stream.quality || '',
        subtitles: stream.subtitles || []
      };
      Lampa.Player.play(video);
    };

    return comp;
  }

  /* ─── Register ──────────────────────────────────────────── */

  function register() {
    if (typeof Lampa.CompactDetail === 'undefined') {
      setTimeout(register, 500);
      return;
    }

    sources.forEach(function (src) {
      Lampa.Manifest.plugins['source_' + src.id] = {
        name:        src.name,
        version:     '1.0.0',
        description: 'Nguồn ' + src.name
      };
    });

    Lampa.Manifest.plugins['source_all'] = {
      name:        'Tất cả nguồn Việt',
      version:     '1.0.0',
      description: 'Tìm trên cả 4 nguồn'
    };
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', register);
  } else {
    register();
  }

})();
