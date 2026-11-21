import { IDBKeyRange, indexedDB } from 'fake-indexeddb'

import type { DexieDependencies } from './database'
import type { CardState, FsrsState, ReviewLogEntry } from './types'

export const fakeIndexedDB: DexieDependencies = { indexedDB, IDBKeyRange }

let counter = 0
/** A fresh database name per test so tests never share state. */
export function uniqueDatabaseName(): string {
  return `test-${Date.now()}-${counter++}`
}

export function makeFsrsState(overrides: Partial<FsrsState> = {}): FsrsState {
  return {
    phase: 'review',
    due: 1_000,
    stability: 3,
    difficulty: 5,
    elapsedDays: 1,
    scheduledDays: 3,
    learningSteps: 0,
    reps: 2,
    lapses: 0,
    lastReview: 0,
    ...overrides,
  }
}

export function makeCardState(cardId: string, overrides: Partial<CardState> = {}): CardState {
  const [tool, variant, optionId] = cardId.split(':')
  return {
    cardId,
    deckId: `${tool}-${variant}`,
    optionId: optionId ?? 'unknown',
    fsrs: makeFsrsState(),
    suspended: false,
    ...overrides,
  }
}

export function makeLogEntry(
  cardId: string,
  overrides: Partial<ReviewLogEntry> = {},
): ReviewLogEntry {
  const [tool, variant] = cardId.split(':')
  return {
    cardId,
    deckId: `${tool}-${variant}`,
    reviewedAt: 0,
    rating: 3,
    durationMs: 4_000,
    before: null,
    after: makeFsrsState(),
    ...overrides,
  }
}
