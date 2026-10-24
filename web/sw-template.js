const VERSION = '__VERSION__';
const CACHE = 'blackblade-' + VERSION;
const SHELL = __SHELL__;
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    // A full/private cache must not strand the PWA on an old broken worker.
    try { await (await caches.open(CACHE)).addAll(SHELL); } catch {}
    await self.skipWaiting();
  })());
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    try { await Promise.all((await caches.keys()).filter(key => key.startsWith('blackblade-') && key !== CACHE).map(key => caches.delete(key))); } catch {}
    await self.clients.claim();
    for (const client of await self.clients.matchAll({ type: 'window', includeUncontrolled: true })) {
      client.postMessage({ type: 'blackblade-update-ready', version: VERSION });
    }
  })());
});
self.addEventListener('message', event => {
  if (event.data?.type === 'blackblade-version') event.source?.postMessage({ type: 'blackblade-update-ready', version: VERSION });
});
async function cachedByteRange(response, range, ifRange) {
  if (!range || response.status !== 200) return response;
  if (ifRange) {
    if (ifRange.startsWith('W/') || ifRange.startsWith('"')) {
      if (ifRange.startsWith('W/') || response.headers.get('ETag') !== ifRange) return response;
    } else {
      const modified = Date.parse(response.headers.get('Last-Modified')), limit = Date.parse(ifRange);
      if (!Number.isFinite(modified) || !Number.isFinite(limit) || modified > limit) return response;
    }
  }
  const match = /^bytes=(\d*)-(\d*)$/i.exec(range.trim());
  // A server may ignore unsupported multipart ranges and return a full 200.
  if (!match || (!match[1] && !match[2])) return response;
  const body = await response.arrayBuffer(), size = body.byteLength;
  let start, end;
  if (!match[1]) { const suffix = Number(match[2]); start = Math.max(0, size - suffix); end = size - 1; }
  else { start = Number(match[1]); end = match[2] ? Math.min(Number(match[2]), size - 1) : size - 1; }
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || start >= size || end < start) {
    return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${size}`, 'Accept-Ranges': 'bytes' } });
  }
  const headers = new Headers(response.headers);
  headers.set('Content-Range', `bytes ${start}-${end}/${size}`);
  headers.set('Content-Length', String(end - start + 1)); headers.set('Accept-Ranges', 'bytes');
  headers.delete('Content-Encoding');
  return new Response(body.slice(start, end + 1), { status: 206, headers });
}
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  const name = url.pathname.split('/').pop();
  if (!(SHELL.some(path => new URL(path, self.registration.scope).pathname === url.pathname) || url.pathname.includes('/data/') || url.pathname.includes('/audio/'))) return;
  const immutable = url.pathname.includes('/data/') || name.startsWith('engine.');
  const range = event.request.headers.get('Range');
  const ifRange = event.request.headers.get('If-Range');
  event.respondWith((async () => {
    let cache, cached;
    try { cache = await caches.open(CACHE); cached = await cache.match(event.request, { ignoreSearch: true }); }
    catch { return fetch(event.request); }
    if (immutable && cached) return cachedByteRange(cached, range, ifRange);
    try {
      const response = await fetch(event.request);
      // Safari media requests can return 206. Cache.put rejects partial bodies;
      // neither that nor an exhausted cache may discard a valid online response.
      if (response.status === 200 && response.type === 'basic') {
        const key = range ? new Request(event.request.url) : event.request;
        event.waitUntil(cache.put(key, response.clone()).catch(() => {}));
      }
      if (response.ok || response.status === 416) return response;
      if (cached) return cachedByteRange(cached, range, ifRange);
      return response;
    } catch (error) { if (cached) return cachedByteRange(cached, range, ifRange); throw error; }
  })());
});
