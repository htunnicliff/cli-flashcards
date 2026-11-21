import { defineStore } from 'pinia'
import { ref } from 'vue'

import type { Repository } from '@/core/storage'

/**
 * Whether this browser has seen (or skipped) the welcome tour. It lives in localStorage
 * rather than the settings table so it is read synchronously, isn't carried into backups,
 * and the E2E fixture can set it before the app loads (see e2e/support/test.ts).
 */
export const ONBOARDING_STORAGE_KEY = 'recall:onboarded'

export function hasSeenOnboarding(storage: Pick<Storage, 'getItem'> | undefined): boolean {
  try {
    if (!storage) return true
    return storage.getItem(ONBOARDING_STORAGE_KEY) !== null
  } catch {
    // Storage disabled: don't show the tour on every visit.
    return true
  }
}

function markSeen() {
  try {
    localStorage.setItem(ONBOARDING_STORAGE_KEY, '1')
  } catch {
    // Private mode or storage disabled: the tour may show again next visit.
  }
}

export const useOnboardingStore = defineStore('onboarding', () => {
  const open = ref(false)
  /** True when Settings replayed the tour, so the last step closes instead of leading to Review. */
  const replay = ref(false)

  /**
   * Opens the tour on a first visit. Someone who has already reviewed cards (they used
   * the app before the tour existed, or restored a backup) is marked as onboarded instead.
   * Decks download on their own, so having decks says nothing about being new.
   */
  async function startIfNew(repository: Repository) {
    if (hasSeenOnboarding(typeof localStorage === 'undefined' ? undefined : localStorage)) return
    let reviews = 0
    try {
      reviews = await repository.reviewLog.count()
    } catch {
      // IndexedDB unavailable: treat as a new user.
    }
    if (reviews > 0) markSeen()
    else {
      replay.value = false
      open.value = true
    }
  }

  function start() {
    replay.value = true
    open.value = true
  }

  function finish() {
    markSeen()
    open.value = false
  }

  return { open, replay, startIfNew, start, finish }
})
