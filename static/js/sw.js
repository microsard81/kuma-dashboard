/********************************************************************
 * SERVICE WORKER – VERSIONE RINOMINATA (sw.js)
 * ---------------------------------------------------------------
 * ✔ Forza Safari a caricare il nuovo file (bug fix)
 * ✔ Non cachea MAI HTML
 * ✔ Non cachea MAI richieste con query (?t=…)
 * ✔ Cache-first SOLO per file statici /static/*
 * ✔ Gestione WebPush
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
        keys.filter((k) => k !== STATIC_CACHE).map((k) => caches.delete(k))
      )
    )
  );
});

/* ---------------------------------------------------------------
 * FETCH RULES
 * ------------------------------------------------------------- */
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // Query → rete sempre
  if (url.search.length > 0) {
    event.respondWith(fetch(event.request));
    return;
  }

  // Documenti HTML → rete
  if (event.request.destination === "document") {
    event.respondWith(fetch(event.request));
    return;
  }

  // Homepage → rete
  if (url.pathname === "/") {
    event.respondWith(fetch(event.request));
    return;
  }

  // Static assets → cache-first
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

  // Default → rete
  event.respondWith(fetch(event.request));
});

/* ---------------------------------------------------------------
 * PUSH
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
 * CLICK NOTIFICA
 * ------------------------------------------------------------- */
self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ("focus" in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow("/");
    })
  );
});