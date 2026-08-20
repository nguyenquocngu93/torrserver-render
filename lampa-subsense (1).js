// ==LampaPlugin==
// Name: SubSense Subtitles
// Description: Tự tải phụ đề từ SubSense (subsense.nepiraw.com) khi phát phim trên Lampa. Có nút SubSense trong menu chính để chọn phụ đề.
// Version: 2.0.0
// Author: personal use
// ==/LampaPlugin==

(function () {
    'use strict';

    if (typeof window.Lampa === 'undefined') {
        console.error('[SubSense] Lampa not found');
        return;
    }

    var NAME = 'SubSense';
    var MAX = 10;               // số sub tối đa tự nạp mỗi lần
    var manifest = '';          // URL manifest người dùng nhập
    var lang = 'vie';           // vie | eng | all

    // ============ helpers ============

    function getBase() {
        var m = (manifest || '').trim();
        m = m.replace(/\/manifest\.json.*$/, '');
        m = m.replace(/^stremio:\/\//, 'https://');
        return m;
    }

    // Lấy đối tượng phim (có imdb_id) từ dữ liệu phát
    function getMovie(data) {
        var card = null;
        if (data && data.card) card = data.card;
        if (!card && Lampa.Player && Lampa.Player.playdata) {
            var w = Lampa.Player.playdata();
            if (w && w.card) card = w.card;
        }
        if (!card && Lampa.Activity && Lampa.Activity.active) {
            var act = Lampa.Activity.active();
            if (act && act.movie) card = act.movie;
        }
        return card;
    }

    function getImdb(movie) {
        if (!movie) return null;
        if (movie.imdb_id) return movie.imdb_id;
        if (movie.info && movie.info.imdb_id) return movie.info.imdb_id;
        if (movie.id && /^tt\d+$/.test(movie.id)) return movie.id;
        return null;
    }

    function getType(movie) {
        return movie && movie.name ? 'series' : 'movie';
    }

    function subTitle(s, i) {
        return (s.lang || '?') + ' — ' + (s.fileName || s.releaseName || s.label || ('Phụ đề ' + (i + 1)));
    }

    // ============ SubSense API ============

    function apiSubtitles(imdb, type, call) {
        var base = getBase();
        if (!base) {
            call(new Error('Chưa nhập SubSense manifest URL (Cài đặt → SubSense)'));
            return;
        }
        var url = base + '/subtitles/' + type + '/' + imdb + '.json';
        console.log('[SubSense] GET', url);

        if (Lampa.Network && Lampa.Network.native) {
            Lampa.Network.native(url, function (data) {
                var subs = (data && data.subtitles) || [];
                call(null, subs);
            }, function (err) {
                call(err || new Error('Lỗi mạng'));
            });
        } else {
            fetch(url, { headers: { 'Accept': 'application/json' } })
                .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
                .then(function (d) { call(null, (d && d.subtitles) || []); })
                .catch(function (e) { call(e); });
        }
    }

    // Lọc theo ngôn ngữ + giới hạn
    function pick(subs) {
        var out = [];
        (subs || []).forEach(function (s) {
            if (lang !== 'all' && s.lang !== lang) return;
            if (out.length >= MAX) return;
            out.push(s);
        });
        return out;
    }

    // ============ áp sub vào player ============

    function apply(subs) {
        if (!subs || !subs.length || !Lampa.Player || !Lampa.Player.subtitles) return;
        var tracks = [];
        subs.forEach(function (s, i) {
            if (!s.url) return;
            tracks.push({ url: s.url, label: subTitle(s, i) });
        });
        if (!tracks.length) return;
        Lampa.Player.subtitles(tracks);
        console.log('[SubSense] added', tracks.length, 'tracks');
    }

    // ============ tự tải khi phát ============

    function autoLoad(data) {
        var movie = getMovie(data);
        var imdb = getImdb(movie);
        if (!imdb) { console.log('[SubSense] no imdb_id, skip'); return; }

        apiSubtitles(imdb, getType(movie), function (err, subs) {
            if (err) { console.log('[SubSense] error:', err.message); return; }
            var list = pick(subs);
            if (!list.length) { console.log('[SubSense] no subs for', imdb); return; }
            apply(list);
        });
    }

    // ============ bộ chọn thủ công ============

    function picker() {
        if (!Lampa.Player.opened || !Lampa.Player.opened()) {
            Lampa.Noty.show('Hãy phát một bộ phim trước, rồi mở SubSense để chọn phụ đề');
            return;
        }
        var movie = getMovie();
        var imdb = getImdb(movie);
        if (!imdb) { Lampa.Noty.show('Không tìm được IMDB ID của phim'); return; }

        apiSubtitles(imdb, getType(movie), function (err, subs) {
            if (err) { Lampa.Noty.show('Lỗi: ' + err.message); return; }
            var list = pick(subs);
            if (!list.length) { Lampa.Noty.show('Không có phụ đề phù hợp'); return; }

            var items = list.map(function (s, i) {
                return { title: subTitle(s, i), sub: s };
            });

            Lampa.Select.show({
                title: 'SubSense — chọn phụ đề',
                items: items,
                onSelect: function (it) {
                    if (it && it.sub) {
                        apply([it.sub]);
                        Lampa.Noty.show('Đã thêm phụ đề');
                    }
                }
            });
        });
    }

    // ============ init ============

    function start() {
        // 1) Mục cài đặt riêng: Cài đặt → SubSense
        try {
            if (Lampa.SettingsApi && Lampa.SettingsApi.addComponent) {
                Lampa.SettingsApi.addComponent({
                    component: 'subsense',
                    icon: '<svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="M6 9h8"/><path d="M6 13h12"/><path d="M6 17h6"/></svg>',
                    name: 'SubSense'
                });

                Lampa.SettingsApi.addParam({
                    component: 'subsense',
                    param: { name: 'subsense_manifest', type: 'input', values: '', default: '', placeholder: 'https://subsense.nepiraw.com/xxxx-.../manifest.json' },
                    field: { name: 'SubSense manifest URL', description: 'Lấy tại subsense.nepiraw.com/configure → Copy Manifest URL' },
                    onChange: function (v) { manifest = (v || '').trim(); }
                });

                Lampa.SettingsApi.addParam({
                    component: 'subsense',
                    param: { name: 'subsense_lang', type: 'select', values: { vie: 'Tiếng Việt', eng: 'English', all: 'Tất cả ngôn ngữ' }, default: 'vie' },
                    field: { name: 'Ngôn ngữ phụ đề ưu tiên', description: 'Tiếng Việt = vie, English = eng' },
                    onChange: function (v) { lang = v; }
                });
            } else {
                console.warn('[SubSense] SettingsApi missing');
            }
        } catch (e) { console.warn('[SubSense] settings error', e); }

        manifest = Lampa.Storage.get('subsense_manifest', '');
        lang = Lampa.Storage.get('subsense_lang', 'vie');

        // 2) Tự tải sub khi player bắt đầu phát
        try {
            if (Lampa.Player && Lampa.Player.listener) {
                Lampa.Player.listener.follow('start', function (data) { autoLoad(data); });
            }
        } catch (e) { console.warn('[SubSense] player hook error', e); }

        // 3) Nút SubSense trong menu chính (mở bộ chọn sub)
        try {
            if (Lampa.Menu && Lampa.Menu.addButton) {
                Lampa.Menu.addButton(
                    '<svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="M6 9h8"/><path d="M6 13h12"/><path d="M6 17h6"/></svg>',
                    'SubSense',
                    picker
                );
            }
        } catch (e) { console.warn('[SubSense] menu error', e); }

        console.log('[SubSense] plugin started');
    }

    if (window.appready) start();
    else {
        Lampa.Listener.follow('app', function (e) {
            if (e.type == 'ready') start();
        });
    }
})();
