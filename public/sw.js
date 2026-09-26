// Service Worker para VJ STREAM PWA (iPhone / Android)
const CACHE_NAME = 'vj-stream-v1';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  // Las transmisiones de video y las APIs se procesan siempre por red directa
  if (event.request.url.includes('/api/') || event.request.url.includes('.m3u8') || event.request.url.includes('.ts') || event.request.url.includes('.mp4')) {
    return;
  }
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
