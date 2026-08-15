const CACHE_NAME = 'hr-sys-v41';
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

// Install Event
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(ASSETS))
      .then(() => self.skipWaiting())
  );
});

// Activate Event
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cache) => {
          if (cache !== CACHE_NAME) {
            return caches.delete(cache);
          }
        })
      );
    })
  );
  return self.clients.claim();
});

// Fetch Event
self.addEventListener('fetch', (event) => {
  // Only cache GET requests
  if (event.request.method !== 'GET') return;
  
  // Only cache http/https requests (ignore chrome-extension:// etc)
  if (!event.request.url.startsWith('http')) return;
  
  // Exclude Supabase API requests from caching
  if (event.request.url.includes('supabase.co')) return;

  // Network First, falling back to cache
  event.respondWith(
    fetch(event.request)
      .then((networkResponse) => {
        return caches.open(CACHE_NAME).then((cache) => {
          if (networkResponse.status === 200 && networkResponse.type === 'basic') {
            cache.put(event.request.url, networkResponse.clone());
          }
          return networkResponse;
        });
      })
      .catch(() => {
        return caches.match(event.request);
      })
  );
});
