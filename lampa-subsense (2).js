// ==LampaPlugin==
// Name: SubSense Subtitles
// Description: Tự tải phụ đề từ SubSense (subsense.nepiraw.com). Hỗ trợ gửi sub qua MX Player (external player) bằng cách gắn subtitles vào data trước khi launch.
// Version: 2.1.0
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
    var chosenTracks = [];      // sub đã chọn thủ công (để gắn vào data khi phát)
    var lastSubs = [];          // sub đã tự nạp (dùng lại khi cần)

    // ============ helpers ============

    function getBase() {
        var m = (manifest || '').trim();
        m = m.replace(/\/manifest\.json.*$/, '');
        m = m.replace(/^stremio:\/\//, 'https://');
        return m;
    }

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

    function toTrack(s, i) {
        return { url: s.url, label: subTitle(s, i) };
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
                call(null, (data && data.subtitles) || []);
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

    function pick(subs) {
        var out = [];
        (subs || []).forEach(function (s) {
            if (lang !== 'all' && s.lang !== lang) return;
            if (out.length >= MAX) return;
            out.push(s);
        });
        return out;
    }

    // ============ áp sub ============

    // Nạp track vào player nội bộ (menu CC)
    function applyToPlayer(subs) {
        if (!subs || !subs.length || !Lampa.Player || !Lampa.Player.subtitles) return;
        var tracks = [];
        subs.forEach(function (s, i) { if (s.url) tracks.push(toTrack(s, i)); });
        if (!tracks.length) return;
        Lampa.Player.subtitles(tracks);
        console.log('[SubSense] added to inner player:', tracks.length);
    }

    // Gắn sub vào data TRƯỚC khi Android.openPlayer chạy → MX Player nhận sub qua Intent
    function attachToData(data) {
        if (!data) return;
        var tracks = chosenTracks.length ? chosenTracks
                  : (lastSubs || []).map(toTrack).filter(function (t) { return t.url; });
        if (!tracks.length) return;
        data.subtitles = tracks;
        // MX Player đọc extra "subs"; native Lampa có thể map từ subtitles — gửi cả 2 cho chắc
        data.subs = tracks.map(function (t) { return t.url; });
        console.log('[SubSense] attached', tracks.length, 'subtitles to data for external player');
    }

    // ============ tự tải khi phát (player nội bộ) ============

    function autoLoad(data) {
        var movie = getMovie(data);
        var imdb = getImdb(movie);
        if (!imdb) { console.log('[SubSense] no imdb_id, skip auto'); return; }

        apiSubtitles(imdb, getType(movie), function (err, subs) {
            if (err) { console.log('[SubSense] auto err:', err.message); return; }
            var list = pick(subs);
            if (!list.length) { console.log('[SubSense] no subs for', imdb); return; }
            lastSubs = list;
            applyToPlayer(list);
        });
    }

    // ============ bộ chọn thủ công ============

    function picker() {
        var movie = getMovie();
        var imdb = getImdb(movie);

        if (!imdb) {
            // thử từ activity hiện tại
            try {
                var act = Lampa.Activity.active();
                if (act && act.movie) { movie = act.movie; imdb = getImdb(movie); }
            } catch (e) {}
        }
        if (!imdb) { Lampa.Noty.show('Không tìm được IMDB ID của phim (mở trang phim trước)'); return; }

        apiSubtitles(imdb, getType(movie), function (err, subs) {
            if (err) { Lampa.Noty.show('Lỗi: ' + err.message); return; }
            var list = pick(subs);
            if (!list.length) { Lampa.Noty.show('Không có phụ đề phù hợp'); return; }

            var items = list.map(function (s, i) {
                return { title: subTitle(s, i), sub: s, index: i };
            });

            Lampa.Select.show({
                title: 'SubSense — chọn phụ đề',
                items: items,
                onSelect: function (it) {
                    if (!it || !it.sub) return;
                    chosenTracks = [toTrack(it.sub, it.index)];
                    lastSubs = list;
                    // nếu player nội bộ đang mở thì nạp luôn
                    try { if (Lampa.Player.opened && Lampa.Player.opened()) applyToPlayer([it.sub]); } catch (e) {}
                    Lampa.Noty.show('Đã chọn sub. Bấm Phát để MX Player nhận sub.');
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

        // 2) Bắt sự kiện "create" — TRƯỚC khi Android.openPlayer → gắn sub vào data cho MX Player
        try {
            if (Lampa.Player && Lampa.Player.listener) {
                Lampa.Player.listener.follow('create', function (e) {
                    if (e && e.data) attachToData(e.data);
                });
            }
        } catch (e) { console.warn('[SubSense] create hook error', e); }

        // 3) Tự tải sub khi player nội bộ bắt đầu phát
        try {
            if (Lampa.Player && Lampa.Player.listener) {
                Lampa.Player.listener.follow('start', function (data) { autoLoad(data); });
            }
        } catch (e) { console.warn('[SubSense] start hook error', e); }

        // 4) Nút SubSense trong menu chính
        try {
            if (Lampa.Menu && Lampa.Menu.addButton) {
                Lampa.Menu.addButton(
                    '<svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="M6 9h8"/><path d="M6 13h12"/><path d="M6 17h6"/></svg>',
                    'SubSense',
                    picker
                );
            }
        } catch (e) { console.warn('[SubSense] menu error', e); }

        console.log('[SubSense] plugin started v2.1');
    }

    if (window.appready) start();
    else {
        Lampa.Listener.follow('app', function (e) {
            if (e.type == 'ready') start();
        });
    }
})();
