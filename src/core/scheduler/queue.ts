import { deriveCards, type Card, type Tier } from '../../schema'
import type { CardState, ReviewLogEntry, Settings, StoredDeck } from '../storage'
import { nextStudyDayStart, studyDayStart } from './day'

export type QueueKind = 'learning' | 'review' | 'new'

export interface QueueItem {
  kind: QueueKind
  card: Card
  /** Absent for a new card that has never been graded. */
  state?: CardState
}

export interface Queue {
  /** Cards to show now, in order: learning steps, then due reviews, then new cards. */
  items: QueueItem[]
  /** Today's daily limits: grades counted so far, and how many more the limits allow. */
  today: {
    reviewsDone: number
    reviewsLeft: number
    newDone: number
    newLeft: number
  }
  /**
   * When the next learning-step card becomes due later today, if one does.
   * The review screen can wait for it instead of declaring the session done.
   */
  nextLearningDue?: number
}

export interface QueueInput {
  decks: readonly StoredDeck[]
  /** Stored states for the decks' cards; extra states are ignored. */
  states: readonly CardState[]
  /** Every review in the current study day. */
  todaysLog: readonly ReviewLogEntry[]
  settings: Pick<Settings, 'newCardsPerDay' | 'maxReviewsPerDay' | 'dayRolloverHour'>
  now: number
}

const TIER_ORDER: Record<Tier, number> = { core: 0, common: 1, obscure: 2 }

function optionKey(card: Pick<Card, 'deckId' | 'optionId'>): string {
  return `${card.deckId}\u0000${card.optionId}`
}

/** A grade counts against a daily limit by what the card was before it. */
function countsAs(entry: ReviewLogEntry): 'new' | 'review' | 'learning' {
  if (entry.before === null || entry.before.phase === 'new') return 'new'
  return entry.before.phase === 'review' ? 'review' : 'learning'
}

/**
 * Picks what to study now. Pure: the caller loads the data and passes `now`.
 *
 * - Learning and relearning cards come first once their step is due.
 * - Review cards due today come next, earliest first, up to the daily review limit.
 * - New cards fill in up to the daily new limit: `core` tier first, then
 *   `common`, then `obscure` for decks that include it; within a tier, in deck
 *   order. A new card's siblings (other card types of the same option) wait for
 *   another day.
 * - Sibling burying: once any card of an option has been graded today, or one
 *   is already in the queue, that option's other cards wait until tomorrow.
 *   A card graded today still returns for its own learning steps.
 * - Suspended cards and cards buried past `now` are skipped.
 */
export function buildQueue({ decks, states, todaysLog, settings, now }: QueueInput): Queue {
  const dayEnd = nextStudyDayStart(now, settings.dayRolloverHour)
  const stateById = new Map(states.map((state) => [state.cardId, state]))

  const gradedToday = new Set<string>()
  const optionsGradedToday = new Set<string>()
  let reviewsDone = 0
  let newDone = 0
  for (const entry of todaysLog) {
    gradedToday.add(entry.cardId)
    const state = stateById.get(entry.cardId)
    optionsGradedToday.add(
      state ? optionKey(state) : `${entry.deckId}\u0000${entry.cardId.split(':')[2]}`,
    )
    const kind = countsAs(entry)
    if (kind === 'review') reviewsDone++
    else if (kind === 'new') newDone++
  }

  const learning: QueueItem[] = []
  const reviews: QueueItem[] = []
  const fresh: { item: QueueItem; tier: number; deck: number; order: number }[] = []
  let nextLearningDue: number | undefined

  decks.forEach((stored, deckIndex) => {
    const tierByOption = new Map(stored.deck.options.map((o) => [o.id, o.tier]))
    deriveCards(stored.deck).forEach((card, order) => {
      const tier = tierByOption.get(card.optionId) ?? 'common'
      const state = stateById.get(card.id)
      if (state?.suspended) return
      if (state?.buriedUntil !== undefined && state.buriedUntil > now) return
      const siblingSeen = optionsGradedToday.has(optionKey(card)) && !gradedToday.has(card.id)
      if (siblingSeen) return

      const phase = state?.fsrs.phase ?? 'new'
      if (phase === 'learning' || phase === 'relearning') {
        if (state!.fsrs.due <= now) learning.push({ kind: 'learning', card, state })
        else if (state!.fsrs.due < dayEnd)
          nextLearningDue = Math.min(nextLearningDue ?? Infinity, state!.fsrs.due)
      } else if (phase === 'review') {
        if (state!.fsrs.due < dayEnd) reviews.push({ kind: 'review', card, state })
      } else {
        if (tier === 'obscure' && !stored.includeObscure) return
        fresh.push({
          item: { kind: 'new', card, ...(state ? { state } : {}) },
          tier: TIER_ORDER[tier],
          deck: deckIndex,
          order,
        })
      }
    })
  })

  const byDue = (a: QueueItem, b: QueueItem) =>
    a.state!.fsrs.due - b.state!.fsrs.due || a.card.id.localeCompare(b.card.id)
  learning.sort(byDue)
  reviews.sort(byDue)
  fresh.sort((a, b) => a.tier - b.tier || a.deck - b.deck || a.order - b.order)

  const reviewsLeft = Math.max(0, settings.maxReviewsPerDay - reviewsDone)
  const newLeft = Math.max(0, settings.newCardsPerDay - newDone)

  // Learning cards are already one per option (siblings of a graded card are
  // filtered above), so only reviews and new cards need de-duplicating.
  const queuedOptions = new Set(learning.map((item) => optionKey(item.card)))
  const take = (candidates: QueueItem[], limit: number) => {
    const taken: QueueItem[] = []
    for (const item of candidates) {
      if (taken.length >= limit) break
      const key = optionKey(item.card)
      if (queuedOptions.has(key)) continue
      queuedOptions.add(key)
      taken.push(item)
    }
    return taken
  }
  const dueReviews = take(reviews, reviewsLeft)
  const newCards = take(
    fresh.map((f) => f.item),
    newLeft,
  )

  return {
    items: [...learning, ...dueReviews, ...newCards],
    today: {
      reviewsDone,
      reviewsLeft,
      newDone,
      newLeft,
    },
    ...(nextLearningDue === undefined ? {} : { nextLearningDue }),
  }
}

/** The study day `[start, end)` containing `now`. */
export function studyDay(now: number, rolloverHour: number): { start: number; end: number } {
  return { start: studyDayStart(now, rolloverHour), end: nextStudyDayStart(now, rolloverHour) }
}
