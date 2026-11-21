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
  /** True when Settings replayed the tour, so the last step closes instead of leading to Decks. */
  const replay = ref(false)

  /**
   * Opens the tour on a first visit. Someone who already has decks installed (they used
   * the app before the tour existed, or restored a backup) is marked as onboarded instead.
   */
  async function startIfNew(repository: Repository) {
    if (hasSeenOnboarding(typeof localStorage === 'undefined' ? undefined : localStorage)) return
    let decks = 0
    try {
      decks = (await repository.decks.list()).length
    } catch {
      // IndexedDB unavailable: treat as a new user.
    }
    if (decks > 0) markSeen()
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
