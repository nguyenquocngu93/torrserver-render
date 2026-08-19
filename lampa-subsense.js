// ==LampaPlugin==
// Name: SubSense Subtitles
// Description: Auto-load Vietnamese/English subtitles from SubSense (subsense.nepiraw.com) and add them to the Lampa player. Works with MX Player as external player.
// Version: 1.0.0
// Author: for personal use
// ==/LampaPlugin==

(function () {
    'use strict';

    if (typeof window.Lampa === 'undefined') {
        console.error('[SubSense] Lampa not found');
        return;
    }

    var NAME = 'SubSense';

    var Plugin = {
        name: NAME,
        manifestUrl: '',
        preferredLang: 'Vietnamese',

        // ---------- init ----------
        init: function () {
            if (!Lampa.Settings || !Lampa.PlayerMenu || !Lampa.Player || !Lampa.Select || !Lampa.Noty) {
                console.error('[SubSense] Missing Lampa modules');
                return;
            }
            this.addSettings();
            this.addPlayerMenu();
            this.loadSaved();

            // Auto-load subtitles when a video starts
            Lampa.Listener.follow('player', (function (self) {
                return function (e) {
                    if (e.type === 'start') self.autoLoad();
                };
            })(this));

            console.log('[SubSense] Plugin initialized');
        },

        // ---------- settings ----------
        addSettings: function () {
            var self = this;
            Lampa.Settings.add(this.name, {
                manifest_url: {
                    name: 'SubSense manifest URL',
                    type: 'input',
                    default: '',
                    placeholder: 'https://subsense.nepiraw.com/xxxxxxxx-.../manifest.json',
                    onChange: function (v) {
                        self.manifestUrl = (v || '').trim();
                        Lampa.Storage.set('subsense_manifest', self.manifestUrl);
                    }
                },
                subtitle_lang: {
                    name: 'Ngôn ngữ phụ đề ưu tiên',
                    type: 'select',
                    values: { Vietnamese: 'Tiếng Việt', English: 'English', All: 'Tất cả ngôn ngữ' },
                    default: 'Vietnamese',
                    onChange: function (v) {
                        self.preferredLang = v;
                        Lampa.Storage.set('subsense_lang', v);
                    }
                }
            });
        },

        loadSaved: function () {
            this.manifestUrl = Lampa.Storage.get('subsense_manifest', '');
            this.preferredLang = Lampa.Storage.get('subsense_lang', 'Vietnamese');
        },

        // ---------- player menu button ----------
        addPlayerMenu: function () {
            Lampa.PlayerMenu.add({
                title: 'SubSense — chọn phụ đề',
                subtitle: 'Tải phụ đề từ SubSense',
                icon: 'subtitles',
                action: (function (self) {
                    return function () { self.showSubPicker(); };
                })(this)
            });
        },

        // ---------- helpers ----------
        getApiBase: function () {
            var url = this.manifestUrl || '';
            url = url.replace(/\/manifest\.json.*$/, '');
            url = url.replace(/^stremio:\/\//, 'https://');
            return url;
        },

        getMovie: function () {
            var film = Lampa.Player.data;
            if (!film || !film.movie) return null;
            return film.movie;
        },

        getImdbId: function (movie) {
            if (movie.info && movie.info.imdb_id) return movie.info.imdb_id;
            if (movie.imdb_id) return movie.imdb_id;
            if (movie.id && /^tt\d+$/.test(movie.id)) return movie.id;
            if (movie.imdbId) return movie.imdbId;
            return null;
        },

        getType: function (movie) {
            return (movie.name && !movie.title) ? 'series' : 'movie';
        },

        // ---------- fetch from SubSense ----------
        fetchSubs: function (imdb, type, done) {
            var base = this.getApiBase();
            if (!base) {
                done(new Error('Chưa nhập SubSense manifest URL (Cài đặt → SubSense Subtitles)'));
                return;
            }
            var url = base + '/subtitles/' + type + '/' + imdb + '.json';
            console.log('[SubSense] GET', url);

            fetch(url, { headers: { 'Accept': 'application/json' } })
                .then(function (r) {
                    if (!r.ok) throw new Error('HTTP ' + r.status);
                    return r.json();
                })
                .then(function (data) {
                    var subs = (data && data.subtitles) ? data.subtitles : [];
                    done(null, subs);
                })
                .catch(function (e) { done(e); });
        },

        filterSubs: function (subs) {
            var self = this;
            if (!subs || !subs.length) return [];
            if (!self.preferredLang || self.preferredLang === 'All') return subs;

            var want = self.preferredLang.toLowerCase();
            var matched = subs.filter(function (s) {
                var lang = ((s.lang || '') + ' ' + (s.name || '')).toLowerCase();
                return lang.indexOf(want) !== -1;
            });
            return matched.length ? matched : subs; // fallback: trả hết nếu không khớp
        },

        // ---------- actions ----------
        autoLoad: function () {
            var movie = this.getMovie();
            if (!movie) return;
            var imdb = this.getImdbId(movie);
            if (!imdb) { console.log('[SubSense] No IMDB id, skip auto-load'); return; }

            var self = this;
            this.fetchSubs(imdb, this.getType(movie), function (err, subs) {
                if (err) { console.log('[SubSense] auto-load error:', err.message); return; }
                var list = self.filterSubs(subs);
                if (!list.length) { console.log('[SubSense] No subs found for', imdb); return; }
                self.applySub(list[0]);
                console.log('[SubSense] Auto-applied sub:', list[0].lang, list[0].name);
            });
        },

        showSubPicker: function () {
            var movie = this.getMovie();
            if (!movie) { Lampa.Noty.show('Không có phim đang phát'); return; }
            var imdb = this.getImdbId(movie);
            if (!imdb) { Lampa.Noty.show('Không tìm được IMDB ID của phim'); return; }

            var self = this;
            Lampa.Noty.show('Đang tải danh sách phụ đề...');
            this.fetchSubs(imdb, this.getType(movie), function (err, subs) {
                if (err) { Lampa.Noty.show('Lỗi: ' + err.message); return; }
                var list = self.filterSubs(subs);
                if (!list.length) { Lampa.Noty.show('Không có phụ đề nào'); return; }

                var items = list.map(function (s, i) {
                    return {
                        title: (s.lang || '?') + ' — ' + (s.name || s.id || ('Phụ đề ' + (i + 1))),
                        url: s.url,
                        label: (s.lang || '') + ' ' + (s.name || '')
                    };
                });

                Lampa.Select.show({
                    title: 'SubSense — chọn phụ đề',
                    items: items,
                    onSelect: function (item) {
                        self.applySubByUrl(item.url, item.label);
                    }
                });
            });
        },

        // ---------- apply to player ----------
        applySub: function (sub) {
            if (sub.url) this.applySubByUrl(sub.url, (sub.lang || '') + ' ' + (sub.name || ''));
        },

        applySubByUrl: function (url, label) {
            var self = this;
            // Try to load content (avoids CORS issues in some setups)
            fetch(url, { headers: { 'Accept': 'text/plain,text/vtt,application/x-subrip' } })
                .then(function (r) { return r.text(); })
                .then(function (text) {
                    var parsed = self.parseSubtitle(text);
                    if (!parsed.length) throw new Error('Không parse được file phụ đề');
                    self.addToPlayer({ label: label || 'SubSense', content: parsed });
                    Lampa.Noty.show('Đã thêm phụ đề: ' + (label || 'SubSense'));
                })
                .catch(function (e) {
                    console.log('[SubSense] content fetch failed, trying url mode:', e.message);
                    self.addToPlayer({ label: label || 'SubSense', url: url });
                    Lampa.Noty.show('Đã thêm phụ đề (URL): ' + (label || 'SubSense'));
                });
        },

        addToPlayer: function (track) {
            var player = Lampa.Player;
            if (player.subtitles && player.subtitles.add) {
                player.subtitles.add(track);
            } else if (player.subtitlesAdd) {
                player.subtitlesAdd(track);
            } else if (player.setSubtitles) {
                player.setSubtitles([track]);
            } else {
                console.log('[SubSense] No subtitles API found, trying subtitles list');
                try {
                    Lampa.Player.subtitles = Lampa.Player.subtitles || { list: [] };
                    Lampa.Player.subtitles.list.push(track);
                } catch (err) { console.error('[SubSense]', err); }
            }
        },

        // ---------- SRT/VTT parser ----------
        parseSubtitle: function (text) {
            if (!text) return [];
            // Normalize line endings
            text = text.replace(/\r/g, '');
            // VTT header strip
            text = text.replace(/^WEBVTT[^\n]*\n+/, '');
            // Strip VTT cue settings: 00:01.000 --> 00:02.000 align:start position:0%
            var out = [];
            var blocks = text.split(/\n{2,}/);
            for (var i = 0; i < blocks.length; i++) {
                var b = blocks[i];
                var lines = b.split('\n');
                var timeLine = null;
                var start = null, end = null, textLines = [];
                for (var j = 0; j < lines.length; j++) {
                    var ln = lines[j].trim();
                    if (!ln) continue;
                    if (/^\d+$/.test(ln) && !timeLine) continue; // SRT index
                    if (ln.indexOf('-->') !== -1) {
                        timeLine = ln;
                        var parts = ln.split('-->');
                        start = this.timeToSec(parts[0]);
                        end = this.timeToSec(parts[1]);
                    } else if (timeLine) {
                        textLines.push(ln);
                    }
                }
                if (start !== null && textLines.length) {
                    out.push({ start: start, end: end !== null ? end : start + 3, text: textLines.join('\n') });
                }
            }
            return out;
        },

        timeToSec: function (t) {
            t = (t || '').trim();
            // 00:01:02.500 or 00:01.500
            var m = t.match(/(?:(\d+):)?(\d+):(\d+)(?:[.,](\d+))?/);
            if (!m) return 0;
            var h = m[1] ? parseInt(m[1], 10) : 0;
            var min = parseInt(m[2], 10);
            var sec = parseInt(m[3], 10);
            var ms = m[4] ? parseFloat('0.' + m[4]) : 0;
            return h * 3600 + min * 60 + sec + ms;
        }
    };

    try {
        Plugin.init();
        window.Lampa.Plugins = window.Lampa.Plugins || {};
        window.Lampa.Plugins[NAME] = Plugin;
        console.log('[SubSense] Plugin loaded');
    } catch (e) {
        console.error('[SubSense] Init error:', e);
        if (Lampa.Noty) Lampa.Noty.show('SubSense plugin lỗi: ' + e.message);
    }
})();
