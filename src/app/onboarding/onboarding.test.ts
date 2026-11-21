import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'

import { createRepository } from '@/core/storage'
import { fakeIndexedDB, uniqueDatabaseName } from '@/core/storage/test-utils'
import { DeckSchema } from '@/schema/deck'
import { makeDeck, makeOption } from '@/schema/fixtures'

import { hasSeenOnboarding, ONBOARDING_STORAGE_KEY, useOnboardingStore } from './onboarding'

function repo() {
  return createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
}

describe('onboarding', () => {
  beforeEach(() => {
    localStorage.clear()
    setActivePinia(createPinia())
  })

  it('opens on a first visit and stays closed once finished', async () => {
    const store = useOnboardingStore()
    await store.startIfNew(repo())
    expect(store.open).toBe(true)
    expect(store.replay).toBe(false)

    store.finish()
    expect(store.open).toBe(false)
    expect(localStorage.getItem(ONBOARDING_STORAGE_KEY)).toBe('1')

    await store.startIfNew(repo())
    expect(store.open).toBe(false)
  })

  it('skips people who have already reviewed and remembers that', async () => {
    const repository = repo()
    const fsrs = {
      phase: 'learning' as const,
      due: 0,
      stability: 1,
      difficulty: 5,
      elapsedDays: 0,
      scheduledDays: 0,
      learningSteps: 0,
      reps: 1,
      lapses: 0,
    }
    await repository.reviewLog.append({
      cardId: 'grep:gnu:i:flag-to-meaning',
      deckId: 'grep-gnu',
      reviewedAt: 1,
      rating: 3,
      durationMs: 1000,
      before: null,
      after: fsrs,
    })
    const store = useOnboardingStore()
    await store.startIfNew(repository)
    expect(store.open).toBe(false)
    expect(hasSeenOnboarding(localStorage)).toBe(true)
  })

  it('still welcomes a new learner whose decks downloaded already', async () => {
    const repository = repo()
    await repository.decks.install(DeckSchema.parse(makeDeck([makeOption(['-i'])])))
    const store = useOnboardingStore()
    await store.startIfNew(repository)
    expect(store.open).toBe(true)
  })

  it('replays on request', () => {
    localStorage.setItem(ONBOARDING_STORAGE_KEY, '1')
    const store = useOnboardingStore()
    store.start()
    expect(store.open).toBe(true)
    expect(store.replay).toBe(true)
  })

  it('treats unusable storage as seen, so the tour never nags', () => {
    expect(hasSeenOnboarding(undefined)).toBe(true)
    const throwing = {
      getItem: () => {
        throw new Error('denied')
      },
    }
    expect(hasSeenOnboarding(throwing)).toBe(true)
  })
})
