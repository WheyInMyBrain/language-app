import { precacheAndRoute, cleanupOutdatedCaches } from 'workbox-precaching';

cleanupOutdatedCaches();
precacheAndRoute(self.__WB_MANIFEST || []);

// 1. Receive background push from Rust backend
self.addEventListener('push', (event) => {
  if (!event.data) return;

  let payload = {
    title: 'Language Vault',
    body: 'You have a new study update.',
    url: '/',
    tag: 'general-alert'
  };

  try {
    payload = event.data.json();
  } catch (_) {
    payload.body = event.data.text();
  }

  const options = {
    body: payload.body,
    icon: '/logo-192.png',
    badge: '/badge-72.png',
    tag: payload.tag || 'lang-vault-alert',
    renotify: true,
    data: {
      url: payload.url || '/'
    }
  };

  event.waitUntil(self.registration.showNotification(payload.title, options));
});

// 2. Click handler: focus existing window or launch target URL
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const targetUrl = event.notification.data?.url || '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      // If a window is already open, navigate and focus it
      for (const client of clientList) {
        if ('focus' in client) {
          client.navigate(targetUrl);
          return client.focus();
        }
      }
      // If the app was closed, launch a new browser window directly at the target URL
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});