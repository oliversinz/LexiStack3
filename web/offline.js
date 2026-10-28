// Bump this version when publishing changed static assets.
const CACHE = 'lexistack-1.0.0';
const ASSETS = [
  './', 'index.html', 'flutter_bootstrap.js', 'main.dart.js', 'manifest.json',
  'assets/AssetManifest.bin', 'assets/AssetManifest.bin.json', 'assets/FontManifest.json',
  'assets/assets/levels/manifest.json',
  ...['pack1', 'pack2', 'pack3', 'pack4', 'daily'].map(p => `assets/assets/levels/${p}.json`),
  ...['Roboto-Regular', 'Roboto-Bold', 'RobotoCondensed-Bold'].map(f => `assets/assets/fonts/${f}.ttf`),
  'assets/fonts/MaterialIcons-Regular.otf',
  'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js', 'canvaskit/chromium/canvaskit.wasm',
  'favicon.png', 'icons/Icon-192.png', 'icons/Icon-512.png'
];
self.addEventListener('install', event => event.waitUntil(
  caches.open(CACHE).then(cache => cache.addAll(ASSETS)).then(() => self.skipWaiting())
));
self.addEventListener('activate', event => event.waitUntil(
  caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('lexistack-') && k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim())
));
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET' || new URL(event.request.url).origin !== self.location.origin) return;
  event.respondWith(caches.match(event.request).then(hit => hit || fetch(event.request).then(response => {
    if (response.ok) { const copy = response.clone(); caches.open(CACHE).then(cache => cache.put(event.request, copy)); }
    return response;
  })));
});
