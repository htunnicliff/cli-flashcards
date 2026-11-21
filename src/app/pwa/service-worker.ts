import { useRegisterSW } from 'virtual:pwa-register/vue'

/** How often a long-open tab checks for a new version. */
const UPDATE_CHECK_INTERVAL_MS = 60 * 60 * 1000

/**
 * Registers the service worker (production builds only) and reports when a new
 * version is waiting. The new version never takes over on its own: call
 * `updateServiceWorker()` when the user chooses to reload.
 */
export function useServiceWorker() {
  return useRegisterSW({
    immediate: true,
    onRegisteredSW(_url, registration) {
      if (!registration) return
      setInterval(() => {
        if (navigator.onLine) void registration.update()
      }, UPDATE_CHECK_INTERVAL_MS)
    },
  })
}
