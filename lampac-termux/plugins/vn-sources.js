/**
 * vn-sources.js — Vietnamese Sources for Lampa/Lampac
 * 
 * 4 nguồn: KKPhim, OPhim, UHDMovie, 4KHDHub
 * Calls TorrShelf API (port 8787) for search + streams
 * 
 * Deploy: /opt/lampac/plugins/override/vn-sources.js
 */
(function(){
  'use strict';
  if(!window.Lampa) return;

  var API = localStorage.getItem('vn_api') || 'http://127.0.0.1:8787';
  var net = new Lampa.Reguest();

  /* ─── Search all sources ──────────────────────────────── */
  function searchAll(query, cb){
    net.silent(API+'/api/search?keyword='+encodeURIComponent(query), function(d){
      cb(d||[]);
    }, function(){ cb([]); });
  }

  /* ─── Get streams ─────────────────────────────────────── */
  function getStreams(title, year, cb){
    var url = API+'/api/streams?title='+encodeURIComponent(title);
    if(year) url += '&year='+encodeURIComponent(year);
    net.silent(url, function(d){
      cb(d&&d.streams ? d.streams : []);
    }, function(){ cb([]); });
  }

  /* ─── Draw results into Lampa ─────────────────────────── */
  function drawResults(container, items){
    if(!items||!items.length){
      var empty = document.createElement('div');
      empty.className = 'empty';
      empty.textContent = 'Không tìm thấy kết quả';
      container.appendChild(empty);
      return;
    }
    items.forEach(function(item){
      var card = document.createElement('div');
      card.className = 'card selector';
      card.style.cssText = 'display:inline-block;width:150px;margin:5px;cursor:pointer;text-align:center;';
      
      var img = document.createElement('img');
      img.src = item.poster || '';
      img.style.cssText = 'width:150px;height:220px;object-fit:cover;border-radius:8px;';
      img.onerror = function(){ this.src = 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" width="150" height="220"><rect fill="%23333" width="150" height="220"/><text fill="%23999" x="50%" y="50%" text-anchor="middle" dy=".3em">No Poster</text></svg>'; };
      
      var title = document.createElement('div');
      title.style.cssText = 'color:#fff;font-size:12px;margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;';
      title.textContent = item.title || '';
      
      var src = document.createElement('div');
      src.style.cssText = 'color:#888;font-size:10px;';
      src.textContent = item.sourceName || item.source || '';
      
      card.appendChild(img);
      card.appendChild(title);
      card.appendChild(src);
      
      card.onclick = function(){ openItem(item); };
      
      container.appendChild(card);
    });
  }

  /* ─── Open item → get streams → play ──────────────────── */
  function openItem(item){
    Lampa.Noty.show('Đang tìm stream...');
    getStreams(item.title, item.year, function(streams){
      if(!streams||!streams.length){
        Lampa.Noty.show('Không có stream cho: '+item.title);
        return;
      }
      if(streams.length===1){
        play(streams[0], item.title);
      } else {
        showSelect(streams, item.title);
      }
    });
  }

  function showSelect(streams, title){
    var body = document.createElement('div');
    body.className = 'modal-overlay';
    body.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.8);z-index:9999;display:flex;align-items:center;justify-content:center;';
    
    var list = document.createElement('div');
    list.style.cssText = 'background:#222;border-radius:12px;padding:20px;max-width:400px;width:90%;max-height:70vh;overflow-y:auto;';
    
    var h = document.createElement('h3');
    h.style.cssText = 'color:#fff;margin:0 0 15px 0;';
    h.textContent = title + ' — Chọn tập';
    list.appendChild(h);
    
    streams.forEach(function(s,i){
      var btn = document.createElement('div');
      btn.className = 'selector';
      btn.style.cssText = 'padding:10px;margin:5px 0;background:#333;border-radius:8px;color:#fff;cursor:pointer;';
      btn.textContent = s.title || ('Stream '+(i+1));
      btn.onmouseover = function(){ this.style.background='#444'; };
      btn.onmouseout = function(){ this.style.background='#333'; };
      btn.onclick = function(){
        body.remove();
        play(s, title);
      };
      list.appendChild(btn);
    });
    
    var close = document.createElement('div');
    close.className = 'selector';
    close.style.cssText = 'padding:10px;margin:15px 0 0;background:#c0392b;border-radius:8px;color:#fff;text-align:center;cursor:pointer;';
    close.textContent = 'Đóng';
    close.onclick = function(){ body.remove(); };
    list.appendChild(close);
    
    body.appendChild(list);
    body.onclick = function(e){ if(e.target===body) body.remove(); };
    document.body.appendChild(body);
  }

  function play(stream, title){
    if(!stream.url){
      Lampa.Noty.show('Không có URL stream');
      return;
    }
    Lampa.Player.play({
      title: stream.title || title || 'Video',
      url: stream.url,
      quality: stream.quality || '',
      subtitles: stream.subtitles || []
    });
  }

  /* ─── Search UI ───────────────────────────────────────── */
  function showSearch(container){
    var wrap = document.createElement('div');
    wrap.style.cssText = 'padding:15px;';
    
    var input = document.createElement('input');
    input.type = 'text';
    input.placeholder = 'Tìm phim Việt...';
    input.style.cssText = 'width:100%;padding:12px;border-radius:8px;border:1px solid #444;background:#222;color:#fff;font-size:16px;box-sizing:border-box;';
    
    var results = document.createElement('div');
    results.style.cssText = 'margin-top:15px;display:flex;flex-wrap:wrap;justify-content:center;';
    
    var timer;
    input.oninput = function(){
      clearTimeout(timer);
      var q = input.value.trim();
      if(q.length<2){ results.innerHTML=''; return; }
      timer = setTimeout(function(){
        results.innerHTML = '<div style="color:#888;width:100%;text-align:center;">Đang tìm...</div>';
        searchAll(q, function(items){
          results.innerHTML = '';
          drawResults(results, items);
        });
      }, 500);
    };
    
    wrap.appendChild(input);
    wrap.appendChild(results);
    container.appendChild(wrap);
    
    input.focus();
  }

  /* ─── Register as Lampa component ─────────────────────── */
  function register(){
    if(typeof Lampa.Component==='undefined'){
      setTimeout(register, 500);
      return;
    }

    /* Add to components */
    Lampa.Component.add('vn_sources', function(object){
      var comp = new Lampa.CompactDetail(object);
      var self = this;
      
      comp.create = function(){
        comp.build = function(){
          showSearch(comp);
        };
      };
      
      comp.start = function(){
        if(comp.build) comp.build();
      };
      
      return comp;
    });

    /* Add manifest */
    Lampa.Manifest.plugins = Lampa.Manifest.plugins || {};
    Lampa.Manifest.plugins.name = 'Phim Việt';
    Lampa.Manifest.plugins.version = '1.0.0';
    Lampa.Manifest.plugins.description = 'Nguồn phim Việt: KKPhim, OPhim, UHDMovie, 4KHDHub';

    console.log('[VN Sources] v2.0 registered');
  }

  if(document.readyState==='loading'){
    document.addEventListener('DOMContentLoaded', register);
  } else {
    register();
  }
})();
