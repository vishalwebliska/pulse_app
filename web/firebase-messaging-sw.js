/* Pulse — Firebase Cloud Messaging service worker (web push).
 *
 * FCM web push delivers background messages to this service worker. The Flaxxa
 * backend sends web push DATA-ONLY (title/body inside `data`, no `notification`
 * block) so this worker owns rendering + click routing — matching the native
 * clients, and avoiding the double-notification a `notification` block causes on
 * web. Config below is the PUBLIC web Firebase config (project anroidapp1234);
 * it mirrors DefaultFirebaseOptions.web in lib/firebase_options.dart.
 *
 * Web push also needs: a VAPID key passed to the app build
 * (--dart-define=PULSE_WEB_VAPID=...) so the page can mint a token, and the
 * matching web fields set in Admin > Platform integrations > FCM. Without a
 * token nothing reaches this worker, but it is harmless to ship.
 */
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDrc-Yr_CABwIUuj3bWDFegYf6o12B87Fs',
  appId: '1:82677459502:web:3eca70fa464bb56a5f0dbf',
  messagingSenderId: '82677459502',
  projectId: 'anroidapp1234',
  authDomain: 'anroidapp1234.firebaseapp.com',
  storageBucket: 'anroidapp1234.firebasestorage.app',
});

const messaging = firebase.messaging();

// Background data-only message → render the notification ourselves.
messaging.onBackgroundMessage((payload) => {
  const data = payload.data || {};
  const title = data.title || 'Pulse';
  const options = {
    body: data.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: { url: data.url || '/' },
  };
  if (data.channel_id) options.tag = 'pulse-ch-' + data.channel_id;
  self.registration.showNotification(title, options);
});

// Tap → focus an open Pulse tab (handing it the deep link to route), or open one.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil((async () => {
    const wins = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of wins) {
      if ('focus' in c) {
        c.postMessage({ pulsePushUrl: url });
        return c.focus();
      }
    }
    if (clients.openWindow) return clients.openWindow('/');
  })());
});
