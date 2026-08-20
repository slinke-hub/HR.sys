const CACHE_NAME = 'hr-sys-v45';
const ASSETS = [
  '/',
  '/index.html',
  '/css/variables.css',
  '/css/layout.css',
  '/css/components.css',
  '/js/app.js',
  '/images/logo.png',
  'https://unpkg.com/lucide@latest'
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cache) => caches.delete(cache))
      );
    }).then(() => {
      self.registration.unregister();
    })
  );
  return self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  // Always fetch from network to bypass old cache completely
  event.respondWith(
    fetch(event.request).catch((error) => {
      console.warn('Service Worker fetch failed:', error);
      return Response.error();
    })
  );
});
