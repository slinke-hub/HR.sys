// Bump whenever the shell or versioned scripts change so already-open clients
// activate a fresh worker and do not keep executing a stale application bundle.
const CACHE_NAME = 'muqam-hr-mobile-v250';
const APP_SHELL = [
  '/', '/index.html', '/manifest.json', '/offline.html',
  '/css/variables.css', '/css/layout.css', '/css/components.css', '/css/hr-suite-beta.css', '/css/android.css', '/css/crm-tailwind.css',
  '/js/DragDropTouch.js', '/js/data.js', '/js/db.js', '/js/shared-services.js', '/js/contract.js', '/js/payroll.js', '/js/hr-suite-beta.js', '/js/enterprise-beta.js', '/js/crm-dashboard.bundle.js', '/js/app.js',
  '/js/vendor/lucide.min.js', '/js/vendor/supabase.js', '/js/vendor/chart.umd.min.js', '/js/vendor/xlsx.full.min.js', '/js/vendor/tesseract/tesseract.min.js', '/js/document-ocr.js',
  '/images/logo.png', '/images/logo-dark.png', '/images/favicon.png?v=1'
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

  // Versioned application assets are served from cache immediately and
  // refreshed in the background. Exact query-string matches are preferred so
  // a newly deployed bundle never receives an older version by accident.
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(request);
    if (cached) {
      fetch(request, { cache: 'no-store' }).then(response => {
        if (response.ok && response.type !== 'opaque') cache.put(request, response);
      }).catch(() => {});
      return cached;
    }
    try {
      const response = await fetch(request);
      if (response.ok && response.type !== 'opaque') cache.put(request, response.clone());
      return response;
    } catch (error) {
      const fallback = await cache.match(request, { ignoreSearch: true });
      if (fallback) return fallback;
      throw error;
    }
  })());
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
