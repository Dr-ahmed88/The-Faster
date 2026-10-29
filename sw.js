/* The Faster GitHub Pages service worker: v27 fixes stale cached 404 responses. */
const CACHE = 'sprint-planner-v27';
const CORE_FILES = [
  './index.html',
  './manifest.webmanifest',
  './icon-192.png',
  './icon-512.png',
  './icon.svg',
  './hero.jpg'
];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // Cache only successful responses; never store a 404 page as the home page.
    await Promise.all(CORE_FILES.map(async path => {
      try {
        const url = new URL(path, self.registration.scope);
        const response = await fetch(url, { cache: 'reload' });
        if (response.ok) await cache.put(url, response);
      } catch (_) {
        // A single unavailable asset must not block installation of the app.
      }
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys
      .filter(key => (key.startsWith('sprint-planner-') || key.startsWith('the-faster-')) && key !== CACHE)
      .map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Navigation requests always try the live website first, so a former 404
  // cannot keep replacing the home page after a successful deployment.
  if (request.mode === 'navigate') {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE);
      try {
        const response = await fetch(request);
        if (response.ok) {
          await cache.put(request, response.clone());
          return response;
        }
        const scope = new URL(self.registration.scope);
        if (url.pathname === scope.pathname) {
          const home = await cache.match(new URL('./index.html', scope));
          if (home) return home;
        }
        return response; // Do not cache failed HTTP responses.
      } catch (_) {
        return await cache.match(new URL('./index.html', self.registration.scope)) || Response.error();
      }
    })());
    return;
  }

  // Cache static files, but store only successful HTTP responses.
  event.respondWith((async () => {
    const cached = await caches.match(request);
    if (cached) return cached;
    try {
      const response = await fetch(request);
      if (response.ok) {
        const cache = await caches.open(CACHE);
        await cache.put(request, response.clone());
      }
      return response;
    } catch (_) {
      return Response.error();
    }
  })());
});
