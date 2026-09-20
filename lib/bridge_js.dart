/// JS injetado no WebView para integrar o painel Shiny ao app nativo.
///
/// - Pull-to-refresh: detecta swipe descendente com a página no topo.
/// - Downloads: intercepta cliques em `a.shiny-download-link` (botões
///   `downloadButton`/`downloadLink` do Shiny), faz `fetch` no contexto da
///   página (mesma origem, cookies de sessão incluídos) e envia o arquivo
///   em blocos base64 para o Dart via JavascriptChannel `WLVDNative`.
const String kBridgeJs = r'''
(function() {
  if (window.__wlvdBridge) return;
  window.__wlvdBridge = true;
  var busy = false;

  function send(msg) {
    try { WLVDNative.postMessage(JSON.stringify(msg)); } catch (e) {}
  }

  var touchStartY = null;
  var refreshFired = false;
  document.addEventListener('touchstart', function(e) {
    touchStartY = e.touches.length ? e.touches[0].clientY : null;
    refreshFired = false;
  }, { passive: true, capture: true });

  document.addEventListener('touchmove', function(e) {
    if (touchStartY === null || refreshFired || !e.touches.length) return;
    var y = e.touches[0].clientY;
    var atTop = (window.scrollY || document.documentElement.scrollTop || 0) <= 0;
    if (atTop && y - touchStartY > 110) {
      refreshFired = true;
      send({ type: 'pullrefresh' });
    }
  }, { passive: true, capture: true });

  function fileNameFromDisposition(header) {
    if (!header) return null;
    var m = header.match(/filename\*\s*=\s*UTF-8''([^;]+)/i);
    if (m) { try { return decodeURIComponent(m[1]); } catch (e) {} }
    m = header.match(/filename\s*=\s*"?([^";]+)"?/i);
    if (m) {
      try { return decodeURIComponent(m[1]); } catch (e) { return m[1]; }
    }
    return null;
  }

  function sanitize(name) {
    return String(name || '').replace(/[\\\/:*?"<>|\u0000-\u001f]/g, '_').trim();
  }

  document.addEventListener('click', function(e) {
    var t = e.target;
    var a = (t && t.closest) ? t.closest('a.shiny-download-link') : null;
    if (!a) return;
    e.preventDefault();
    e.stopPropagation();
    if (busy) {
      send({ type: 'busy' });
      return;
    }

    var url = a.href;
    if (!url || url.slice(-1) === '#') {
      try {
        var cfg = window.Shiny && window.Shiny.shinyapp && window.Shiny.shinyapp.config;
        if (cfg && cfg.sessionId && a.id) {
          url = 'session/' + cfg.sessionId + '/download/' + a.id + '?w=';
        }
      } catch (err) {
        url = null;
      }
    }
    if (!url) {
      send({ type: 'error', message: 'Download indisponível.' });
      return;
    }

    busy = true;
    var suggested = sanitize(a.getAttribute('download')) ||
        sanitize(a.id || 'download') + '.xlsx';
    send({ type: 'download', url: url, name: suggested });

    var controller = new AbortController();
    var timeout = setTimeout(function() { controller.abort(); }, 15 * 60 * 1000);

    fetch(url, { credentials: 'same-origin', signal: controller.signal })
      .then(function(resp) {
        if (!resp.ok) throw new Error('HTTP ' + resp.status);
        var name = fileNameFromDisposition(resp.headers.get('content-disposition')) ||
            suggested;
        return resp.blob().then(function(blob) {
          clearTimeout(timeout);
          return { blob: blob, name: sanitize(name) || suggested };
        });
      })
      .then(function(r) {
        return new Promise(function(resolve, reject) {
          var reader = new FileReader();
          reader.onload = function() {
            resolve({
              base64: String(reader.result).split(',')[1] || '',
              name: r.name
            });
          };
          reader.onerror = function() { reject(new Error('Falha ao ler o arquivo.')); };
          reader.readAsDataURL(r.blob);
        });
      })
      .then(function(r) {
        var chunk = 262144;
        var total = Math.ceil(r.base64.length / chunk);
        for (var i = 0; i < total; i++) {
          send({ type: 'chunk', seq: i, total: total, data: r.base64.substr(i * chunk, chunk) });
        }
        send({ type: 'done', name: r.name, chunks: total });
      })
      .catch(function(err) {
        clearTimeout(timeout);
        send({ type: 'error', message: String((err && err.message) || err) });
      })
      .then(function() {
        busy = false;
      });
  }, true);
})();
''';
