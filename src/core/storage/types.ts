import type { Deck } from '../../schema'

/** Where a card is in the FSRS life cycle. */
export const CARD_PHASES = ['new', 'learning', 'review', 'relearning'] as const
export type CardPhase = (typeof CARD_PHASES)[number]

/** 1 = Again, 2 = Hard, 3 = Good, 4 = Easy, as in FSRS. */
export type Rating = 1 | 2 | 3 | 4

/**
 * A card's FSRS memory state, stored as plain data. Times are epoch
 * milliseconds so the record is structured-clone and JSON safe. The scheduler
 * (#9) maps this to and from the FSRS library's own card type.
 */
export interface FsrsState {
  phase: CardPhase
  /** When the card is next due. */
  due: number
  stability: number
  difficulty: number
  /** Days between the previous review and the last one. */
  elapsedDays: number
  /** Days the last review scheduled the card out by. */
  scheduledDays: number
  /** Index into the learning or relearning steps. */
  learningSteps: number
  reps: number
  lapses: number
  lastReview?: number
}

/** An installed deck, as fetched, with per-deck preferences. */
export interface StoredDeck {
  id: string
  deckVersion: number
  installedAt: number
  updatedAt: number
  /** Obscure-tier options are left out of new cards unless this is on. */
  includeObscure: boolean
  /** Paused decks show no cards until resumed. Absent on decks stored before #12. */
  paused?: boolean
  /** Meaning → flag and cloze cards ask for the flag to be typed. Absent means off. */
  typeAnswers?: boolean
  deck: Deck
}

/**
 * Scheduling state for one card, keyed by card ID. Rows are never removed when
 * a deck changes: a state whose option is gone from the current deck version is
 * ignored (see `activeCardStates`) and comes back if the option returns.
 */
export interface CardState {
  cardId: string
  deckId: string
  optionId: string
  fsrs: FsrsState
  suspended: boolean
  /** Buried cards are skipped until this time (epoch ms). */
  buriedUntil?: number
  /**
   * Forgotten `leechThreshold` times. Set (and the card suspended) by the
   * scheduler on the lapse that crosses the threshold; kept after unsuspending.
   */
  leech?: boolean
}

/**
 * One grade, appended and never edited. The review log is the source of truth:
 * card states can be rebuilt by replaying it.
 */
export interface ReviewLogEntry {
  /** Auto-incremented; absent until the entry is stored. */
  id?: number
  cardId: string
  deckId: string
  reviewedAt: number
  rating: Rating
  /** How long the user took to answer, in milliseconds. */
  durationMs: number
  /** `null` for the card's first review. */
  before: FsrsState | null
  after: FsrsState
}

/** What happened when we asked the browser to keep our data. */
export interface PersistenceRecord {
  requestedAt: number
  granted: boolean
}

/**
 * Every stored setting with its type. Add a key here and a default in
 * `SETTING_DEFAULTS`; no schema change is needed.
 */
export interface Settings {
  /** Set once `navigator.storage.persist()` has been asked. */
  persistence: PersistenceRecord | null
  /** Probability of recall FSRS aims for when it picks an interval. */
  desiredRetention: number
  /** New cards introduced per day, across all decks. */
  newCardsPerDay: number
  /** Review (not learning) cards shown per day, across all decks. */
  maxReviewsPerDay: number
  /** Local hour at which a new study day starts; 4 means 4 AM. */
  dayRolloverHour: number
  /** Lapses after which a card is tagged as a leech and suspended. */
  leechThreshold: number
  /** When a backup was last exported (epoch ms). */
  lastBackupAt: number | null
  /**
   * Decks an imported backup used that this device hadn't installed. The deck
   * library installs them when it can reach the deck files, then clears them.
   */
  pendingDeckInstalls: PendingDeckInstall[]
}

export interface PendingDeckInstall {
  id: string
  deckVersion: number
  includeObscure: boolean
}

export type SettingKey = keyof Settings

export const SETTING_DEFAULTS: Settings = {
  persistence: null,
  desiredRetention: 0.9,
  newCardsPerDay: 20,
  maxReviewsPerDay: 200,
  dayRolloverHour: 4,
  leechThreshold: 6,
  lastBackupAt: null,
  pendingDeckInstalls: [],
}

export interface SettingRow<K extends SettingKey = SettingKey> {
  key: K
  value: Settings[K]
}
