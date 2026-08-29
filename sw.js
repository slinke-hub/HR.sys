const CACHE_NAME = 'muqam-hr-mobile-v30';
const APP_SHELL = [
  '/', '/index.html', '/manifest.json', '/offline.html',
  '/css/variables.css', '/css/layout.css', '/css/components.css', '/css/android.css',
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

self.addEventListener('push', event => {
  let payload = { title: 'MUQAM HR', body: 'You have a new update.', url: '/?view=notifications' };
  try {
    if (event.data) payload = { ...payload, ...event.data.json() };
  } catch (_error) {
    payload.body = event.data?.text() || payload.body;
  }
  event.waitUntil(self.registration.showNotification(payload.title, {
    body: payload.body,
    icon: '/images/logo.png',
    badge: '/images/logo.png',
    tag: payload.tag || 'muqam-hr-update',
    renotify: true,
    data: { url: payload.url || '/?view=notifications' }
  }));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const targetUrl = new URL(event.notification.data?.url || '/?view=notifications', self.location.origin).href;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const existing = windows.find(client => new URL(client.url).origin === self.location.origin);
    if (existing) {
      await existing.navigate(targetUrl);
      return existing.focus();
    }
    return self.clients.openWindow(targetUrl);
  })());
});
