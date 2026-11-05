'use strict';

// Only genuine encrypted Push API deliveries trigger notifications. This
// worker does not cache pages, intercept requests, or retain API credentials.
const appBase = new URL('.', self.location.href);
self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
self.addEventListener('push', event => {
  if (!event.data) return;
  let payload;
  try { payload = event.data.json(); } catch (_) { return; }
  if (!payload || typeof payload !== 'object' ||
      typeof payload.title !== 'string') return;
  const eventId = typeof payload.data?.eventId === 'string' ?
    payload.data.eventId.slice(0, 128) : '';
  event.waitUntil(self.registration.showNotification(payload.title.slice(0, 120), {
    body: 'Abre SnackUP para consultar tu pedido.',
    icon: new URL('icons/Icon-192.png', appBase).href,
    tag: eventId ? 'snackup-' + eventId : undefined,
    renotify: false
  }));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    for (const client of windows) {
      const url = new URL(client.url);
      if (url.origin === appBase.origin && url.pathname === appBase.pathname) {
        return client.focus();
      }
    }
    // Never navigate to a URL supplied by a push payload.
    return self.clients.openWindow(appBase.href);
  })());
});
