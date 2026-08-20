/**
 * no-apk-force.js — Bypass "Install APK" modal in Lampac/Lampa web
 * 
 * Deploy: /opt/lampac/plugins/override/no-apk-force.js
 * MUST load BEFORE other plugins (first in customPlugins list)
 */
(function(){
  'use strict';
  if(window._no_apk) return;
  window._no_apk = true;

  /* 1. Force platform = browser */
  var P = window.Lampa && Lampa.Platform;
  if(P){
    if(P.get) P.get = function(){ return 'browser'; };
    if(P.is)  P.is  = function(n){ 
      if(Array.isArray(n)) return n.indexOf('browser')>=0; 
      return n==='browser'; 
    };
  }

  /* 2. Force Storage platform */
  var S = window.Lampa && Lampa.Storage;
  if(S){
    if(S.get){
      var _get = S.get;
      S.get = function(k,d){
        if(k==='platform') return 'browser';
        if(k==='native')   return false;
        return _get.call(S,k,d);
      };
    }
    if(S.field){
      var _field = S.field;
      S.field = function(k){
        if(k==='platform') return 'browser';
        if(k==='native')   return false;
        return _field.call(S,k);
      };
    }
  }

  /* 3. Override Android class */
  window.Lampa = window.Lampa || {};
  window.Lampa.Android = {
    init:         function(){},
    exit:         function(){},
    openTorrent:  function(){},
    playHash:     function(){},
    httpReq:      function(d,c){ if(c&&c.error) c.error({responseText:'web'}); },
    openPlayer:   function(link){ if(link) window.open(link,'_blank'); },
    openYoutube:  function(link){ if(link) window.open(link,'_blank'); }
  };

  /* 4. Remove APK modals via DOM mutation */
  function killModal(){
    var all = document.querySelectorAll('.modal-overlay, .popup, .popup-overlay, .full-overlay');
    for(var i=0;i<all.length;i++){
      var t = (all[i].textContent||'').toLowerCase();
      if(t.indexOf('apk')>-1 || t.indexOf('install')>-1 || t.indexOf('установ')>-1 || t.indexOf('скачать')>-1 || t.indexOf('android')>-1){
        all[i].style.display='none';
        all[i].remove();
      }
    }
    /* Also hide generic "select content" overlay that blocks usage */
    var overlays = document.querySelectorAll('.overlay, .content-overlay');
    for(var j=0;j<overlays.length;j++){
      var ot = (overlays[j].textContent||'').toLowerCase();
      if(ot.indexOf('apk')>-1 || ot.indexOf('установ')>-1){
        overlays[j].style.display='none';
      }
    }
  }

  /* Run killModal aggressively */
  killModal();
  setInterval(killModal, 500);

  if(typeof MutationObserver!=='undefined'){
    new MutationObserver(function(muts){
      for(var i=0;i<muts.length;i++){
        var nodes = muts[i].addedNodes;
        for(var j=0;j<nodes.length;j++){
          if(nodes[j].nodeType===1) killModal();
        }
      }
    }).observe(document.body||document.documentElement, {childList:true, subtree:true});
  }

  /* 5. Listen for Lampa activity changes */
  if(window.Lampa && Lampa.Listener){
    Lampa.Listener.follow('activity', function(){ setTimeout(killModal,300); });
    Lampa.Listener.follow('modal', function(e){ 
      if(e.type==='open') setTimeout(killModal,100); 
    });
  }

  /* 6. Inject CSS — hide download/app banners */
  var css = document.createElement('style');
  css.textContent = 
    '.install-banner,.download-app,.apk-banner,.popup-overlay{display:none!importantimportant}' +
    '.modal-overlay{display:none!importantimportant}';
  document.head.appendChild(css);

  /* 7. Override settings if exists */
  if(window.lampa_settings){
    window.lampa_settings.torrents_use = true;
  }

  console.log('[NoAPK] v2.0 active');
})();
