'use strict';

// Only a generic offline page is cached. Orders, profiles, Firebase responses,
// API calls, images and panel pages never enter this worker's cache.
const scopePath = new URL(self.registration.scope).pathname;
const cachePrefix = 'snackup-usuarios-offline-' + encodeURIComponent(scopePath) + '-';
const cacheName = cachePrefix + 'v1';
const offlineUrl = new URL('offline.html', self.registration.scope).href;

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(cacheName).then((cache) => cache.add(
    new Request(offlineUrl, {cache: 'reload', credentials: 'omit'}),
  )).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys().then((names) => Promise.all(names
    .filter((name) => name.startsWith(cachePrefix) && name !== cacheName)
    .map((name) => caches.delete(name))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  let pathname;
  try { pathname = decodeURIComponent(url.pathname); } catch (_) { return; }
  if (request.method !== 'GET' || request.mode !== 'navigate'
      || request.headers.has('Authorization') || url.origin !== self.location.origin
      || !url.pathname.startsWith(scopePath)
      || /^\/(?:api|socket\.io|media|paneles)(?:\/|$)/.test(pathname)) return;
  event.respondWith(fetch(request).catch(async () => {
    const page = await caches.match(offlineUrl, {cacheName});
    return page || new Response('Se necesita conexión para abrir SnackUP.', {
      status: 503, headers: {'Content-Type': 'text/plain; charset=utf-8'},
    });
  }));
});
