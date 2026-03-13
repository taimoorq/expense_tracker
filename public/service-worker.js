const CACHE_NAME = "expense-tracker-shell-v1"
const OFFLINE_URLS = [
  "/",
  "/site.webmanifest",
  "/favicon-32x32.png",
  "/apple-touch-icon.png",
  "/icon.svg"
]

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(OFFLINE_URLS))
  )
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      )
    )
  )
  self.clients.claim()
})

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return

  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      if (cachedResponse) return cachedResponse

      return fetch(event.request)
        .then((networkResponse) => {
          const responseCopy = networkResponse.clone()
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, responseCopy))
          return networkResponse
        })
        .catch(() => caches.match("/"))
    })
  )
})
