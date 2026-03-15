const isLocalHost = (hostname) => {
  return hostname === "localhost" || hostname === "127.0.0.1" || hostname === "[::1]"
}

const unregisterServiceWorkers = async () => {
  if (!("serviceWorker" in navigator)) return

  const registrations = await navigator.serviceWorker.getRegistrations()
  await Promise.all(registrations.map((registration) => registration.unregister()))

  if ("caches" in window) {
    const cacheNames = await caches.keys()
    await Promise.all(
      cacheNames
        .filter((name) => name.startsWith("expense-tracker-shell-"))
        .map((name) => caches.delete(name))
    )
  }
}

const registerServiceWorker = () => {
  if (!("serviceWorker" in navigator)) return

  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/service-worker.js", { updateViaCache: "none" }).then((registration) => {
      registration.update().catch(() => {})
    }).catch(() => {})
  })
}

const railsEnv = document.body?.dataset.railsEnv
const shouldDisableServiceWorker = railsEnv === "development" || railsEnv === "test" || isLocalHost(window.location.hostname)

if (shouldDisableServiceWorker) {
  unregisterServiceWorkers().catch(() => {})
} else {
  registerServiceWorker()
}