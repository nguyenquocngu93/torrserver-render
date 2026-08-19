// ==LampaPlugin==
// Name: SubSense Subtitles
// Description: Tải phụ đề từ SubSense (subsense.nepiraw.com) — 2 cách: (1) gắn sub vào luồng phát để truyền qua external player nếu native hỗ trợ, (2) lưu file .srt để mở trong MX Player.
// Version: 3.0.0
// Author: personal use
// ==/LampaPlugin==

(function () {
    'use strict';

    if (typeof window.Lampa === 'undefined') {
        console.error('[SubSense] Lampa not found');
        return;
    }

    var NAME = 'SubSense';
    var MAX = 10;
    var manifest = '';
    var lang = 'vie';           // vie | eng | all
    var chosenTracks = [];      // sub đã chọn (để gắn vào data khi phát)
    var lastSubs = [];

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

    function isInnerPlaying() {
        try { return Lampa.Player && Lampa.Player.opened && Lampa.Player.opened(); } catch (e) { return false; }
    }

    function noty(msg) {
        try { Lampa.Noty.show(msg); } catch (e) { console.log('[SubSense]', msg); }
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

    function fetchText(url, ok, err) {
        if (Lampa.Network && Lampa.Network.native) {
            Lampa.Network.native(url, function (text) { ok(String(text)); }, function (e) { err(e); });
        } else {
            fetch(url).then(function (r) { return r.text(); }).then(ok).catch(err);
        }
    }

    // ============ CÁCH 1: truyền sub qua external player ============

    function attachToData(data) {
        if (!data) return;
        var tracks = chosenTracks.length ? chosenTracks
                  : (lastSubs || []).map(function (s, i) { return toTrack(s, i); }).filter(function (t) { return t.url; });
        if (!tracks.length) return;
        data.subtitles = tracks;
        data.subs = tracks.map(function (t) { return t.url; });
        console.log('[SubSense] gắn', tracks.length, 'sub vào data (truyền qua external)');
    }

    // ============ CÁCH 2: lưu file .srt ============

    function saveSrt(sub, label) {
        if (!sub || !sub.url) { noty('Không có URL phụ đề'); return; }
        var fname = (label || 'subtitle').replace(/[^\w.\- ]+/g, '').trim().slice(0, 80) + '.srt';

        fetchText(sub.url, function (text) {
            if (!text || !text.length) { noty('Không tải được nội dung phụ đề'); return; }
            try {
                // Blob download → WebView thường lưu vào thư mục Downloads
                var blob = new Blob([text], { type: 'application/x-subrip' });
                var url = URL.createObjectURL(blob);
                var a = document.createElement('a');
                a.href = url;
                a.download = fname;
                document.body.appendChild(a);
                a.click();
                setTimeout(function () {
                    URL.revokeObjectURL(url);
                    if (a.parentNode) a.parentNode.removeChild(a);
                }, 3000);
                noty('Đang lưu ' + fname + ' (kiểm tra thư mục Downloads). Rồi mở trong MX: phụ đề → Open → chọn file.');
            } catch (e) {
                console.warn('[SubSense] blob save fail', e);
                noty('Không lưu được tự động. Dùng "Mở link phụ đề" để tải file .srt.');
            }
        }, function (e) {
            noty('Lỗi tải nội dung: ' + (e && e.message || e));
        });
    }

    function openSubInBrowser(url) {
        try {
            if (Lampa.Android && Lampa.Android.openBrowser) Lampa.Android.openBrowser(url);
            else if (window.open) window.open(url, '_blank');
            else location.href = url;
        } catch (e) { console.warn(e); }
    }

    // ============ chọn sub ============

    function showSubPicker(mode) {
        var movie = getMovie();
        var imdb = getImdb(movie);
        if (!imdb) {
            try {
                var act = Lampa.Activity.active();
                if (act && act.movie) { movie = act.movie; imdb = getImdb(movie); }
            } catch (e) {}
        }
        if (!imdb) { noty('Không tìm được IMDB ID (mở trang phim trước)'); return; }

        apiSubtitles(imdb, getType(movie), function (err, subs) {
            if (err) { noty('Lỗi: ' + err.message); return; }
            var list = pick(subs);
            if (!list.length) { noty('Không có phụ đề phù hợp'); return; }

            var items = list.map(function (s, i) {
                return { title: subTitle(s, i), sub: s, index: i };
            });

            Lampa.Select.show({
                title: 'SubSense — chọn phụ đề',
                items: items,
                onSelect: function (it) {
                    if (!it || !it.sub) return;
                    var sub = it.sub, idx = it.index;

                    if (mode === 'save') {
                        saveSrt(sub, subTitle(sub, idx));
                        return;
                    }

                    // mode 'play' (truyền)
                    chosenTracks = [toTrack(sub, idx)];
                    lastSubs = list;
                    var msg = 'Đã chọn sub "' + subTitle(sub, idx) + '".';
                    if (isInnerPlaying()) {
                        try { Lampa.Player.subtitles(chosenTracks); msg += ' Đã nạp vào player.'; } catch (e) {}
                    } else {
                        msg += ' Bấm Phát để gửi sub qua player.';
                    }
                    noty(msg);
                }
            });
        });
    }

    function mainMenu() {
        var movie = getMovie();
        var imdb = getImdb(movie);
        if (!imdb) {
            try { var act = Lampa.Activity.active(); if (act && act.movie) { movie = act.movie; imdb = getImdb(movie); } } catch (e) {}
        }
        if (!imdb) { noty('Mở trang phim trước rồi vào SubSense'); return; }

        Lampa.Select.show({
            title: 'SubSense',
            items: [
                { title: '🎬 Chọn sub & phát (truyền qua player)', value: 'play' },
                { title: '💾 Lưu file .srt (mở trong MX Player)', value: 'save' },
                { title: '🔗 Mở link phụ đề trong trình duyệt', value: 'open' }
            ],
            onSelect: function (it) {
                if (!it) return;
                if (it.value === 'open') {
                    apiSubtitles(imdb, getType(movie), function (err, subs) {
                        if (err) { noty('Lỗi: ' + err.message); return; }
                        var list = pick(subs);
                        if (!list.length) { noty('Không có phụ đề'); return; }
                        Lampa.Select.show({
                            title: 'Mở link phụ đề',
                            items: list.map(function (s, i) { return { title: subTitle(s, i), url: s.url }; }),
                            onSelect: function (it2) { if (it2 && it2.url) openSubInBrowser(it2.url); }
                        });
                    });
                } else {
                    showSubPicker(it.value);
                }
            }
        });
    }

    // ============ init ============

    function start() {
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
                    field: { name: 'Ngôn ngữ phụ đề ưu tiên', description: 'vie = Tiếng Việt, eng = English, all = Tất cả' },
                    onChange: function (v) { lang = v; }
                });
            }
        } catch (e) { console.warn('[SubSense] settings error', e); }

        manifest = Lampa.Storage.get('subsense_manifest', '');
        lang = Lampa.Storage.get('subsense_lang', 'vie');

        // Gắn sub vào data trước khi external launch (truyền qua MX nếu native hỗ trợ)
        try {
            if (Lampa.Player && Lampa.Player.listener) {
                Lampa.Player.listener.follow('create', function (e) {
                    if (e && e.data) attachToData(e.data);
                });
            }
        } catch (e) { console.warn('[SubSense] create hook error', e); }

        // Nút SubSense trong menu chính
        try {
            if (Lampa.Menu && Lampa.Menu.addButton) {
                Lampa.Menu.addButton(
                    '<svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="M6 9h8"/><path d="M6 13h12"/><path d="M6 17h6"/></svg>',
                    'SubSense',
                    mainMenu
                );
            }
        } catch (e) { console.warn('[SubSense] menu error', e); }

        console.log('[SubSense] plugin started v3.0');
    }

    if (window.appready) start();
    else {
        Lampa.Listener.follow('app', function (e) {
            if (e.type == 'ready') start();
        });
    }
})();
