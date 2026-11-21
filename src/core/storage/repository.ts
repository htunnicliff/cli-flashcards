import { deriveCards, type Deck } from '../../schema'

import { openDatabase, type FlashcardsDatabase, type OpenDatabaseOptions } from './database'
import {
  SETTING_DEFAULTS,
  type CardState,
  type ReviewLogEntry,
  type SettingKey,
  type Settings,
  type StoredDeck,
} from './types'

/**
 * The app's only way into IndexedDB. Everything outside `src/core/storage`
 * goes through these functions and never touches Dexie.
 */
export interface Repository {
  decks: DeckRepository
  cardStates: CardStateRepository
  reviewLog: ReviewLogRepository
  settings: SettingsRepository
  /**
   * Writes a grade's new card state and its review log entry in one
   * transaction, so the two never disagree. Returns the log entry's ID.
   */
  recordReview(state: CardState, entry: ReviewLogEntry): Promise<number>
  /**
   * Takes back a grade the user just made: removes its review log entry and
   * restores the card's previous state (or removes the state if the card had
   * none). The one exception to the append-only log, for the review screen's undo.
   */
  undoReview(entryId: number, cardId: string, previous: CardState | undefined): Promise<void>
  /**
   * Deletes card states and review log entries, for one deck or for all of
   * them. The only operation that removes review history.
   */
  resetProgress(deckId?: string): Promise<void>
  /**
   * Runs `work` in one read-write transaction over every table, so a
   * multi-step change (such as an import) lands completely or not at all.
   * `work` may only await repository calls, not other async work such as fetch.
   */
  atomically<T>(work: () => Promise<T>): Promise<T>
  close(): void
  /** Deletes the whole database. Tests use it to clean up. */
  destroy(): Promise<void>
}

export interface DeckRepository {
  /**
   * Installs a deck or replaces it with a newer version. Card states and the
   * review log are left alone, and the deck's preferences are kept.
   */
  install(deck: Deck, now?: number): Promise<StoredDeck>
  get(id: string): Promise<StoredDeck | undefined>
  list(): Promise<StoredDeck[]>
  setIncludeObscure(id: string, include: boolean): Promise<void>
  /** Paused decks are skipped by the scheduler; their progress is kept. */
  setPaused(id: string, paused: boolean): Promise<void>
  /** Uninstalls the deck. Its progress stays, so reinstalling picks up where it left off. */
  remove(id: string): Promise<void>
}

export interface CardStateRepository {
  get(cardId: string): Promise<CardState | undefined>
  /** Same order as `cardIds`, with `undefined` for cards never reviewed. */
  getMany(cardIds: readonly string[]): Promise<(CardState | undefined)[]>
  /** Every stored state for a deck, including ones for options the deck no longer has. */
  listByDeck(deckId: string): Promise<CardState[]>
  /** States due at or before `time`, earliest first. Suspended and buried cards are included. */
  dueBy(time: number): Promise<CardState[]>
  put(state: CardState): Promise<void>
  putMany(states: readonly CardState[]): Promise<void>
}

export interface ReviewLogRepository {
  append(entry: ReviewLogEntry): Promise<number>
  /** A card's reviews, oldest first. */
  forCard(cardId: string): Promise<ReviewLogEntry[]>
  forDeck(deckId: string): Promise<ReviewLogEntry[]>
  /** Reviews with `from <= reviewedAt < to`, oldest first. */
  between(from: number, to: number): Promise<ReviewLogEntry[]>
  all(): Promise<ReviewLogEntry[]>
  count(): Promise<number>
}

export interface SettingsRepository {
  get<K extends SettingKey>(key: K): Promise<Settings[K]>
  getAll(): Promise<Settings>
  set<K extends SettingKey>(key: K, value: Settings[K]): Promise<void>
}

/**
 * Keeps only the states that belong to a card the deck currently derives.
 * States for options that were removed or hidden stay in the database but are
 * ignored here.
 */
export function activeCardStates(deck: Deck, states: readonly CardState[]): CardState[] {
  const current = new Set(deriveCards(deck).map((card) => card.id))
  return states.filter((state) => state.deckId === deck.id && current.has(state.cardId))
}

function byReviewOrder(a: ReviewLogEntry, b: ReviewLogEntry): number {
  return a.reviewedAt - b.reviewedAt || (a.id ?? 0) - (b.id ?? 0)
}

export function createRepository(
  options: OpenDatabaseOptions | FlashcardsDatabase = {},
): Repository {
  const db = 'transaction' in options ? options : openDatabase(options)

  const decks: DeckRepository = {
    async install(deck, now = Date.now()) {
      return db.transaction('rw', db.decks, async () => {
        const existing = await db.decks.get(deck.id)
        const stored: StoredDeck = {
          id: deck.id,
          deckVersion: deck.deckVersion,
          installedAt: existing?.installedAt ?? now,
          updatedAt: now,
          includeObscure: existing?.includeObscure ?? false,
          ...(existing?.paused ? { paused: true } : {}),
          deck,
        }
        await db.decks.put(stored)
        return stored
      })
    },
    get: (id) => db.decks.get(id),
    list: () => db.decks.toArray(),
    async setIncludeObscure(id, include) {
      const updated = await db.decks.update(id, { includeObscure: include })
      if (updated === 0) throw new Error(`setIncludeObscure: deck "${id}" is not installed`)
    },
    async setPaused(id, paused) {
      const updated = await db.decks.update(id, { paused })
      if (updated === 0) throw new Error(`setPaused: deck "${id}" is not installed`)
    },
    async remove(id) {
      await db.decks.delete(id)
    },
  }

  const cardStates: CardStateRepository = {
    get: (cardId) => db.cardStates.get(cardId),
    getMany: (cardIds) => db.cardStates.bulkGet([...cardIds]),
    listByDeck: (deckId) => db.cardStates.where('deckId').equals(deckId).toArray(),
    dueBy: (time) => db.cardStates.where('fsrs.due').belowOrEqual(time).sortBy('fsrs.due'),
    async put(state) {
      await db.cardStates.put(state)
    },
    async putMany(states) {
      await db.cardStates.bulkPut([...states])
    },
  }

  const reviewLog: ReviewLogRepository = {
    append: (entry) => addLogEntry(db, entry),
    forCard: async (cardId) =>
      (await db.reviewLog.where('cardId').equals(cardId).toArray()).sort(byReviewOrder),
    forDeck: async (deckId) =>
      (await db.reviewLog.where('deckId').equals(deckId).toArray()).sort(byReviewOrder),
    between: (from, to) =>
      db.reviewLog.where('reviewedAt').between(from, to, true, false).sortBy('reviewedAt'),
    all: () => db.reviewLog.orderBy('reviewedAt').toArray(),
    count: () => db.reviewLog.count(),
  }

  const settings: SettingsRepository = {
    async get(key) {
      const row = await db.settings.get(key)
      return (row?.value ?? SETTING_DEFAULTS[key]) as Settings[typeof key]
    },
    async getAll() {
      const rows = await db.settings.toArray()
      const values: Record<string, unknown> = { ...SETTING_DEFAULTS }
      for (const row of rows) if (row.key in SETTING_DEFAULTS) values[row.key] = row.value
      return values as unknown as Settings
    },
    async set(key, value) {
      await db.settings.put({ key, value })
    },
  }

  return {
    decks,
    cardStates,
    reviewLog,
    settings,
    recordReview: (state, entry) =>
      db.transaction('rw', db.cardStates, db.reviewLog, async () => {
        await db.cardStates.put(state)
        return addLogEntry(db, entry)
      }),
    undoReview: (entryId, cardId, previous) =>
      db.transaction('rw', db.cardStates, db.reviewLog, async () => {
        await db.reviewLog.delete(entryId)
        if (previous) await db.cardStates.put(previous)
        else await db.cardStates.delete(cardId)
      }),
    resetProgress: (deckId) =>
      db.transaction('rw', db.cardStates, db.reviewLog, async () => {
        if (deckId === undefined) {
          await Promise.all([db.cardStates.clear(), db.reviewLog.clear()])
        } else {
          await Promise.all([
            db.cardStates.where('deckId').equals(deckId).delete(),
            db.reviewLog.where('deckId').equals(deckId).delete(),
          ])
        }
      }),
    atomically: (work) =>
      db.transaction('rw', [db.decks, db.cardStates, db.reviewLog, db.settings], work),
    close: () => db.close(),
    destroy: () => db.delete(),
  }
}

/** Adds an entry under a fresh auto-incremented ID, ignoring any `id` it carries. */
async function addLogEntry(db: FlashcardsDatabase, entry: ReviewLogEntry): Promise<number> {
  const record = { ...entry }
  delete record.id
  const id = await db.reviewLog.add(record)
  if (id === undefined) throw new Error('reviewLog: IndexedDB returned no key')
  return id
}
