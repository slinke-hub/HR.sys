const CACHE_NAME = 'muqam-hr-mobile-v6';
const APP_SHELL = [
  '/', '/index.html', '/manifest.json', '/offline.html',
  '/css/variables.css', '/css/layout.css', '/css/components.css',
  '/js/DragDropTouch.js', '/js/data.js', '/js/db.js', '/js/contract.js', '/js/payroll.js', '/js/app.js',
  '/js/vendor/lucide.min.js', '/js/vendor/supabase.js', '/js/vendor/chart.umd.min.js', '/js/vendor/xlsx.full.min.js',
  '/images/logo.png'
];

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(names => Promise.all(names.filter(name => name !== CACHE_NAME).map(name => caches.delete(name))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('message', event => {
  if (event.data?.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then(response => {
          const copy = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put('/index.html', copy));
          return response;
        })
        .catch(async () => (await caches.match('/index.html')) || caches.match('/offline.html'))
    );
    return;
  }

  event.respondWith(
    caches.match(request).then(cached => {
      const network = fetch(request).then(response => {
        // Clone immediately. If cloning is deferred until the cache opens, the
        // browser may already have started consuming the original response body.
        if (response.ok && response.type !== 'opaque') {
          const responseForCache = response.clone();
          caches.open(CACHE_NAME)
            .then(cache => cache.put(request, responseForCache))
            .catch(error => console.warn('Service worker cache update skipped:', error));
        }
        return response;
      }).catch(error => {
        if (cached) return cached;
        throw error;
      });
      return cached || network;
    })
  );
});
