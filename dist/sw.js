const CACHE = 'blackblade-29f69fea55a3fc75';
const SHELL = ["./", "index.html", "app.js", "style.css", "manifest.webmanifest", "icon.svg", "runtime.json", "engine.8b649683883a.js", "assets/poster.png", "fonts/Inter.ttf", "fonts/Cormorant.ttf", "game.audio.worklet.js"];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('blackblade-') && key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  const name = url.pathname.split('/').pop();
  if (!(SHELL.some(path => new URL(path, self.registration.scope).pathname === url.pathname) || url.pathname.includes('/data/'))) return;
  const immutable = url.pathname.includes('/data/') || name.startsWith('engine.');
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(event.request, { ignoreSearch: true });
    if (immutable && cached) return cached;
    try {
      const response = await fetch(event.request);
      if (response.ok && response.type === 'basic') await cache.put(event.request, response.clone());
      if (response.ok) return response;
      if (cached) return cached;
      return response;
    } catch (error) { if (cached) return cached; throw error; }
  })());
});
