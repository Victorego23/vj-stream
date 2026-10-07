// Service Worker para VJ STREAM / TOM TV PWA (iPhone / Android)
const CACHE_NAME = 'tomtv-v2';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  const url = event.request.url;
  // Las descargas de APK, APIs y transmisiones de video se procesan siempre por red directa nativa
  if (
    url.includes('/apk') ||
    url.includes('/download') ||
    url.includes('/tv') ||
    url.endsWith('.apk') ||
    url.includes('.apk?') ||
    url.includes('/api/') ||
    url.includes('.m3u8') ||
    url.includes('.ts') ||
    url.includes('.mp4')
  ) {
    return;
  }
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
