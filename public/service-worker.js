const CACHE_NAME = "expense-tracker-shell-v2"
const PRECACHE_URLS = [
  "/",
  "/site.webmanifest",
  "/favicon-32x32.png",
  "/apple-touch-icon.png",
  "/icon.svg"
]

const cacheResponse = async (request, response) => {
  if (!response || !response.ok || response.type !== "basic") return response

  const cache = await caches.open(CACHE_NAME)
  cache.put(request, response.clone())
  return response
}

const isStaticAsset = (request, url) => {
  if (url.origin !== self.location.origin) return false

  return request.destination === "style" ||
    request.destination === "script" ||
    request.destination === "image" ||
    request.destination === "font" ||
    request.destination === "manifest" ||
    url.pathname.startsWith("/assets/")
}

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_URLS))
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

  const url = new URL(event.request.url)

  if (event.request.mode === "navigate") {
    event.respondWith(
      fetch(event.request)
        .then((response) => cacheResponse(event.request, response))
        .catch(async () => {
          return (await caches.match(event.request)) || caches.match("/")
        })
    )
    return
  }

  if (!isStaticAsset(event.request, url)) return

  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      const networkRequest = fetch(event.request)
        .then((response) => cacheResponse(event.request, response))
        .catch(() => cachedResponse)

      return cachedResponse || networkRequest
    })
  )
})
