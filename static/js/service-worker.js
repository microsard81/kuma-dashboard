/********************************************************************
 * SERVICE WORKER – VERSIONE FINALE
 * ---------------------------------------------------------------
 * ✔ Non cachea MAI HTML
 * ✔ Non cachea MAI richieste con query (?t=…)
 * ✔ Cache-first SOLO per file statici /static/*
 * ✔ Gestione WebPush inclusa
 ********************************************************************/

const STATIC_CACHE = "static-v6";

/* ---------------------------------------------------------------
 * INSTALL – Precache degli asset statici
 * ------------------------------------------------------------- */
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(STATIC_CACHE).then((cache) => {
      return cache.addAll([
        "/static/css/dashboard.css",
        "/static/js/dashboard.js",
        "/static/img/logoLight.png",
        "/static/img/logoDark.png",
        "/static/img/icon-192.png",
        "/static/img/icon-512.png"
      ]);
    })
  );
});

/* ---------------------------------------------------------------
 * ACTIVATE – Pulizia vecchie versioni
 * ------------------------------------------------------------- */
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((key) => key !== STATIC_CACHE).map((key) => caches.delete(key))
      )
    )
  );
});

/* ---------------------------------------------------------------
 * FETCH – regole IMPORTANTI
 * ---------------------------------------------------------------
 * 1) Se c’è una query-string → network-only
 * 2) Se destination=document → network-only
 * 3) Se path = "/" → network-only
 * 4) Se /static/ → cache-first
 * 5) Default: network-only
 * ------------------------------------------------------------- */
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // 1) Qualsiasi richiesta con query → SEMPRE rete
  if (url.search.length > 0) {
    event.respondWith(fetch(event.request));
    return;
  }

  // 2) Pagine HTML → rete sempre
  if (event.request.destination === "document") {
    event.respondWith(fetch(event.request));
    return;
  }

  // 3) Route principale → rete
  if (url.pathname === "/") {
    event.respondWith(fetch(event.request));
    return;
  }

  // 4) Asset statici → cache-first
  if (url.pathname.startsWith("/static/")) {
    event.respondWith(
      caches.open(STATIC_CACHE).then((cache) =>
        cache.match(event.request).then((cached) => {
          if (cached) return cached;
          return fetch(event.request).then((resp) => {
            cache.put(event.request, resp.clone());
            return resp;
          });
        })
      )
    );
    return;
  }

  // 5) Tutto il resto → rete
  event.respondWith(fetch(event.request));
});

/* ---------------------------------------------------------------
 * PUSH – mostra le notifiche
 * ------------------------------------------------------------- */
self.addEventListener("push", (event) => {
  let payload = {};

  try {
    if (event.data) {
      payload = event.data.json();
    }
  } catch (e) {
    payload = { title: "Notifica", body: event.data ? event.data.text() : "" };
  }

  const title = payload.title || "IN.VA Uptime Dashboard";
  const options = {
    body: payload.body || "Aggiornamento stato monitoraggio.",
    icon: "/static/img/icon-192.png",
    badge: "/static/img/icon-192.png",
    data: payload.data || {},
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

/* ---------------------------------------------------------------
 * CLICK sulla notifica → apri dashboard
 * ------------------------------------------------------------- */
self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientsList) => {
      for (const client of clientsList) {
        if ("focus" in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow("/");
    })
  );
});