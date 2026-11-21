import { nextTick, watch, type Ref } from 'vue'
import type { Router } from 'vue-router'

export interface AutoUpdateOptions {
  /** True once a new version is installed and waiting. */
  needRefresh: Ref<boolean>
  /** Whether something must not be interrupted (see update-holds.ts). */
  held: Ref<boolean>
  /** Activates the waiting version. `reloadNeeded()` follows once it controls the page. */
  activate: () => void
  router: Router
  doc?: Document
  /** Reloads the page, or loads `href` in its place. */
  load?: (href?: string) => void
}

/**
 * Moves to a new version on its own, at a moment the user won't notice:
 *
 * - before they have touched the page since it opened,
 * - right after they move to another screen, which already redraws the page, or
 * - while the app is in the background.
 *
 * Never while something holds updates, such as a review with cards left.
 *
 * Call `reloadNeeded()` when a new version has taken control of the page. That
 * happens after `activate()`, or when another tab of the app activated it first;
 * then this page reloads at the next quiet moment, or loads the next screen it
 * navigates to fresh, since the new version may not have this build's files.
 */
export function startAutoUpdates({
  needRefresh,
  held,
  activate,
  router,
  doc = document,
  load = (href) => (href ? window.location.assign(href) : window.location.reload()),
}: AutoUpdateOptions) {
  let interacted = false
  let activated = false
  let stale = false
  let loading = false

  function quiet(navigated: boolean) {
    return !held.value && (!interacted || navigated || doc.visibilityState === 'hidden')
  }

  function tryUpdate(navigated = false) {
    if (loading || !quiet(navigated)) return
    if (stale) {
      loading = true
      load()
    } else if (needRefresh.value && !activated) {
      activated = true
      activate()
    }
  }

  function reloadNeeded() {
    stale = true
    // We asked for this version, and only at a quiet moment: reload right away.
    if (activated && !loading) {
      loading = true
      load()
    } else tryUpdate()
  }

  const onInteract = () => {
    interacted = true
    doc.removeEventListener('pointerdown', onInteract, true)
    doc.removeEventListener('keydown', onInteract, true)
  }
  doc.addEventListener('pointerdown', onInteract, true)
  doc.addEventListener('keydown', onInteract, true)

  const onVisibility = () => tryUpdate()
  doc.addEventListener('visibilitychange', onVisibility)

  // A page another tab moved to the new version loads its next screen fresh.
  const removeBefore = router.beforeEach((to) => {
    if (!stale || loading || held.value) return
    loading = true
    load(router.resolve(to).href)
    return false
  })
  // Otherwise update right after the new screen has mounted, once the old one's holds are gone.
  const removeAfter = router.afterEach((to, from, failure) => {
    if (failure || to.fullPath === from.fullPath) return
    void nextTick(() => tryUpdate(true))
  })
  // If the new screen's code is gone, load it from the new version instead.
  const removeError = router.onError((_error, to) => {
    if (!stale || loading) return
    loading = true
    load(router.resolve(to).href)
  })

  const stopWatch = watch([needRefresh, held], () => tryUpdate())

  return {
    reloadNeeded,
    stop() {
      onInteract()
      doc.removeEventListener('visibilitychange', onVisibility)
      removeBefore()
      removeAfter()
      removeError()
      stopWatch()
    },
  }
}
