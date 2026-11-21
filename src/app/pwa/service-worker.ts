import { useRegisterSW } from 'virtual:pwa-register/vue'
import { onScopeDispose, watchEffect } from 'vue'
import { useRouter } from 'vue-router'

import { startAutoUpdates } from './auto-update'
import { updatesHeld } from './update-holds'

/** How often a long-open tab checks for a new version. */
const UPDATE_CHECK_INTERVAL_MS = 60 * 60 * 1000

/**
 * Registers the service worker (production builds only) and moves to new
 * versions behind the scenes. A new version installs in the background and
 * waits; it takes over only at a quiet moment (see auto-update.ts), so it never
 * swaps code out from under a page mid-session.
 */
export function useServiceWorker() {
  let registration: ServiceWorkerRegistration | undefined
  const checkForUpdate = () => {
    if (registration && navigator.onLine) void registration.update()
  }

  let reloadNeeded = () => window.location.reload()
  const sw = useRegisterSW({
    immediate: true,
    onNeedReload: () => reloadNeeded(),
    onRegisteredSW(_url, r) {
      registration = r
      if (r) setInterval(checkForUpdate, UPDATE_CHECK_INTERVAL_MS)
    },
  })

  // For E2E tests and debugging: whether a new version is waiting for a quiet moment.
  watchEffect(() => {
    if (sw.needRefresh.value) document.documentElement.dataset.update = 'waiting'
    else delete document.documentElement.dataset.update
  })

  // Coming back to the app is a good time to look for a new version.
  const onVisible = () => {
    if (document.visibilityState === 'visible') checkForUpdate()
  }
  document.addEventListener('visibilitychange', onVisible)

  const updates = startAutoUpdates({
    needRefresh: sw.needRefresh,
    held: updatesHeld,
    activate: () => void sw.updateServiceWorker(),
    router: useRouter(),
  })
  reloadNeeded = updates.reloadNeeded

  onScopeDispose(() => {
    document.removeEventListener('visibilitychange', onVisible)
    updates.stop()
  })
  return sw
}
