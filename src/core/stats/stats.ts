import { deriveCards } from '../../schema'
import { studyDayStart } from '../scheduler/day'
import type { CardState, ReviewLogEntry, StoredDeck } from '../storage'

/** Anki's convention: a card is mature once its interval reaches three weeks. */
export const MATURE_INTERVAL_DAYS = 21

/** The study day `offset` days after the one containing `time` (negative for earlier). */
export function shiftStudyDay(time: number, offset: number, rolloverHour: number): number {
  const date = new Date(studyDayStart(time, rolloverHour))
  date.setDate(date.getDate() + offset)
  return date.getTime()
}

/** Review counts keyed by study-day start. */
export function reviewsByDay(
  log: readonly Pick<ReviewLogEntry, 'reviewedAt'>[],
  rolloverHour: number,
): Map<number, number> {
  const counts = new Map<number, number>()
  for (const entry of log) {
    const day = studyDayStart(entry.reviewedAt, rolloverHour)
    counts.set(day, (counts.get(day) ?? 0) + 1)
  }
  return counts
}

/**
 * Consecutive study days with at least one review, ending today. If today has
 * no reviews yet the streak still counts through yesterday, so it doesn't
 * reset at rollover before you've had a chance to study.
 */
export function currentStreak(
  byDay: ReadonlyMap<number, number>,
  now: number,
  rolloverHour: number,
): number {
  let offset = byDay.has(studyDayStart(now, rolloverHour)) ? 0 : -1
  let streak = 0
  while (byDay.has(shiftStudyDay(now, offset, rolloverHour))) {
    streak++
    offset--
  }
  return streak
}

export interface CardCounts {
  new: number
  learning: number
  review: number
  suspended: number
}

export interface DeckCardCounts extends CardCounts {
  deckId: string
}

/**
 * Cards in each state per deck, counting the cards the deck derives now.
 * Suspended wins over the FSRS phase; learning includes relearning.
 */
export function cardCountsByDeck(
  decks: readonly StoredDeck[],
  states: readonly CardState[],
): DeckCardCounts[] {
  const byId = new Map(states.map((s) => [s.cardId, s]))
  return decks.map((stored) => {
    const counts: DeckCardCounts = {
      deckId: stored.id,
      new: 0,
      learning: 0,
      review: 0,
      suspended: 0,
    }
    for (const card of deriveCards(stored.deck)) {
      const state = byId.get(card.id)
      if (state?.suspended) counts.suspended++
      else if (!state || state.fsrs.phase === 'new') counts.new++
      else if (state.fsrs.phase === 'review') counts.review++
      else counts.learning++
    }
    return counts
  })
}

export interface Retention {
  /** Mature reviews not rated Again. */
  passed: number
  total: number
  /** `passed / total`, or `undefined` with no mature reviews. */
  rate?: number
}

/**
 * True retention: of reviews of mature cards (a review-phase card with an
 * interval of at least 21 days) in the last `days` study days, the share not
 * rated Again.
 */
export function trueRetention(
  log: readonly ReviewLogEntry[],
  now: number,
  rolloverHour: number,
  days = 30,
): Retention {
  const from = shiftStudyDay(now, -(days - 1), rolloverHour)
  let passed = 0
  let total = 0
  for (const entry of log) {
    if (entry.reviewedAt < from || entry.reviewedAt > now) continue
    const before = entry.before
    if (!before || before.phase !== 'review' || before.scheduledDays < MATURE_INTERVAL_DAYS)
      continue
    total++
    if (entry.rating !== 1) passed++
  }
  return total ? { passed, total, rate: passed / total } : { passed, total }
}

export interface DayCount {
  /** Study-day start, epoch ms. */
  day: number
  count: number
}

/**
 * Cards due on each of the next `days` study days, today first. Overdue cards
 * count toward today. Suspended and never-seen cards are left out, as are
 * states whose card the decks no longer derive.
 */
export function dueForecast(
  decks: readonly StoredDeck[],
  states: readonly CardState[],
  now: number,
  rolloverHour: number,
  days = 30,
): DayCount[] {
  const live = new Set(decks.flatMap((d) => deriveCards(d.deck).map((c) => c.id)))
  const starts = Array.from({ length: days + 1 }, (_, i) => shiftStudyDay(now, i, rolloverHour))
  const counts = new Array<number>(days).fill(0)
  for (const state of states) {
    if (state.suspended || state.fsrs.phase === 'new' || !live.has(state.cardId)) continue
    const due = Math.max(state.fsrs.due, starts[0]!)
    const index = starts.findIndex((start, i) => i < days && due >= start && due < starts[i + 1]!)
    if (index !== -1) counts[index]!++
  }
  return counts.map((count, i) => ({ day: starts[i]!, count }))
}

/** Reviews on each of the last `days` study days, oldest first, ending today. */
export function reviewHistory(
  byDay: ReadonlyMap<number, number>,
  now: number,
  rolloverHour: number,
  days = 365,
): DayCount[] {
  return Array.from({ length: days }, (_, i) => {
    const day = shiftStudyDay(now, i - (days - 1), rolloverHour)
    return { day, count: byDay.get(day) ?? 0 }
  })
}

/** Heatmap shade 0–4 for a day's count, relative to the busiest day. */
export function heatLevel(count: number, max: number): 0 | 1 | 2 | 3 | 4 {
  if (count <= 0 || max <= 0) return 0
  return Math.min(4, Math.max(1, Math.ceil((count / max) * 4))) as 1 | 2 | 3 | 4
}

export interface Stats {
  reviewsToday: number
  streak: number
  cards: DeckCardCounts[]
  retention: Retention
  forecast: DayCount[]
  history: DayCount[]
}

/** Every number on the stats page, from stored data only. */
export function computeStats(input: {
  decks: readonly StoredDeck[]
  states: readonly CardState[]
  log: readonly ReviewLogEntry[]
  now: number
  rolloverHour: number
}): Stats {
  const { decks, states, log, now, rolloverHour } = input
  const byDay = reviewsByDay(log, rolloverHour)
  return {
    reviewsToday: byDay.get(studyDayStart(now, rolloverHour)) ?? 0,
    streak: currentStreak(byDay, now, rolloverHour),
    cards: cardCountsByDeck(decks, states),
    retention: trueRetention(log, now, rolloverHour),
    forecast: dueForecast(decks, states, now, rolloverHour),
    history: reviewHistory(byDay, now, rolloverHour),
  }
}
