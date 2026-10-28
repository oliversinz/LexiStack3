{{flutter_js}}
{{flutter_build_config}}

// Bundle the renderer with the app; no runtime CDN dependency.
_flutter.loader.load({config: {canvasKitBaseUrl: 'canvaskit/'}});
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('offline.js').catch(() => {
      // Private browsing/storage restrictions may prevent repeat-visit caching.
    });
  });
}
