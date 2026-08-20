/**
 * No APK Force — Bypass Lampa's "Install APK" prompt
 *
 * Problem: Lampa web UI detects mobile browser and shows modal
 * forcing user to install Android APK. This plugin:
 *   1. Overrides platform detection to use web mode
 *   2. Removes the install APK modal/popup
 *   3. Enables all features (torrents, player, etc.) in web mode
 *
 * Install: /opt/lampac/plugins/override/no-apk-force.js
 */
(function () {
  'use strict';
  if (window._no_apk_force) return;
  window._no_apk_force = true;

  /* ============================================================
     1. OVERRIDE PLATFORM DETECTION
     ============================================================ */
  // Force platform to 'browser' so Lampa thinks it's desktop web
  // This prevents the "install APK" modal from appearing
  if (window.Lampa && window.Lampa.Platform) {
    var origGet = window.Lampa.Platform.get;
    window.Lampa.Platform.get = function () {
      return 'browser';
    };
    window.Lampa.Platform.is = function (need) {
      if (Array.isArray(need)) return need.indexOf('browser') >= 0;
      return need === 'browser';
    };
  }

  /* ============================================================
     2. OVERRIDE STORAGE to prevent android detection
     ============================================================ */
  if (window.Lampa && window.Lampa.Storage) {
    var origGet2 = window.Lampa.Storage.get;
    window.Lampa.Storage.get = function (key, def) {
      if (key === 'platform') return 'browser';
      if (key === 'native') return false;
      return origGet2.call(window.Lampa.Storage, key, def);
    };

    var origField = window.Lampa.Storage.field;
    if (origField) {
      window.Lampa.Storage.field = function (key) {
        if (key === 'platform') return 'browser';
        if (key === 'native') return false;
        return origField.call(window.Lampa.Storage, key);
      };
    }
  }

  /* ============================================================
     3. REMOVE "INSTALL APK" MODAL
     ============================================================ */
  function removeApkModal() {
    // Remove any existing APK install modals
    $('.modal-overlay, .modal').each(function () {
      var text = $(this).text().toLowerCase();
      if (
        text.indexOf('установить') > -1 ||
        text.indexOf('install') > -1 ||
        text.indexOf('apk') > -1 ||
        text.indexOf('android') > -1 ||
        text.indexOf('приложен') > -1 ||
        text.indexOf('скачать') > -1
      ) {
        $(this).remove();
        console.log('[NoAPKForce] Removed APK install modal');
      }
    });
  }

  // Run on every activity change
  if (window.Lampa && window.Lampa.Listener) {
    window.Lampa.Listener.follow('activity', function () {
      setTimeout(removeApkModal, 500);
    });
    window.Lampa.Listener.follow('modal', function (e) {
      if (e.type === 'open') {
        setTimeout(removeApkModal, 200);
      }
    });
  }

  // Also remove on DOM changes
  if (typeof MutationObserver !== 'undefined') {
    var observer = new MutationObserver(function (mutations) {
      mutations.forEach(function (m) {
        m.addedNodes.forEach(function (node) {
          if (node.nodeType === 1) {
            var text = (node.textContent || '').toLowerCase();
            if (
              text.indexOf('установить') > -1 ||
              text.indexOf('install apk') > -1 ||
              text.indexOf('скачать приложен') > -1
            ) {
              node.remove();
              console.log('[NoAPKForce] Removed APK prompt node');
            }
          }
        });
      });
    });
    observer.observe(document.body || document.documentElement, {
      childList: true,
      subtree: true
    });
  }

  /* ============================================================
     4. OVERRIDE Android CLASS (disable native calls)
     ============================================================ */
  if (window.Lampa && window.Lampa.Android) {
    var origAndroid = window.Lampa.Android;
    window.Lampa.Android = {
      init: function () { },
      exit: function () { },
      openTorrent: function () { },
      openPlayer: function (link, data) {
        // Fallback: open in new tab instead of Android player
        if (link) window.open(link, '_blank');
      },
      playHash: function () { },
      openYoutube: function (link) {
        if (link) window.open(link, '_blank');
      },
      httpReq: function (data, call) {
        if (call && call.error) call.error({ responseText: 'Web mode' });
      }
    };
  }

  /* ============================================================
     5. FORCE ENABLE TORRENTS
     ============================================================ */
  if (window.lampa_settings) {
    window.lampa_settings.torrents_use = true;
  }

  /* ============================================================
     6. INJECT CSS — remove mobile-only restrictions
     ============================================================ */
  var style = document.createElement('style');
  style.textContent = [
    /* Hide any "download app" banners */
    '.install-banner, .download-app, .apk-banner { display: none !important; }',
    /* Make torrent buttons visible */
    '.torrent__button, [data-component="torrent"] { display: flex !important; }',
    /* Hide modal overlays that force APK install */
    '.modal-overlay, .popup, .popup-overlay { display: none !important; }',
    /* Force desktop mode on mobile */
    '@media (max-width: 768px) { .settings, .settings__content { max-width: 100% !important; } }'
  ].join('\n');
  (document.head || document.documentElement).appendChild(style);

  console.log('[NoAPKForce] v1.0 — APK install bypass active');
})();
