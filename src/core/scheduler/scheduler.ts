import { deriveCards, type Card } from '../../schema'
import type { CardState, Rating, Repository, ReviewLogEntry, StoredDeck } from '../storage'
import { nextStudyDayStart } from './day'
import { newFsrsState, nextState } from './fsrs'
import { buildQueue, studyDay, type Queue } from './queue'

export interface GradeResult {
  state: CardState
  entry: ReviewLogEntry
  /** True when this grade made the card a leech, which also suspended it. */
  becameLeech: boolean
}

/** A card's state before a suspend or bury, so it can be put back. */
export interface PreviousState {
  cardId: string
  state: CardState | undefined
}

export interface Scheduler {
  /** What to study at `now`, across every installed deck. */
  getQueue(now: number): Promise<Queue>
  /**
   * Grades a card: computes its next FSRS state, then stores the state and a
   * review log entry together. `durationMs` is how long the user took.
   */
  grade(cardId: string, rating: Rating, now: number, durationMs?: number): Promise<GradeResult>
  /**
   * When the next card that has been studied before comes due after `now`,
   * across active decks, or `undefined` if none will. New cards don't count:
   * they are limited per day, not due.
   */
  nextDue(now: number): Promise<number | undefined>
  /**
   * Sets cards aside without grading them: `suspend` until unsuspended, `bury`
   * until the next study day. Returns their earlier states for `restore`.
   */
  setAside(
    cardIds: readonly string[],
    how: 'suspend' | 'bury',
    now: number,
  ): Promise<PreviousState[]>
  /** Puts back states returned by `setAside`, removing ones that didn't exist. */
  restore(previous: readonly PreviousState[]): Promise<void>
  unsuspend(cardIds: readonly string[]): Promise<void>
}

type SchedulerRepository = Pick<
  Repository,
  'decks' | 'cardStates' | 'reviewLog' | 'settings' | 'recordReview'
>

/**
 * The app's entry point to scheduling. Framework-free with an injected clock:
 * Vue and Pinia only call it with `Date.now()`.
 */
export function createScheduler(repository: SchedulerRepository): Scheduler {
  async function loadStates(decks: readonly StoredDeck[]): Promise<CardState[]> {
    const perDeck = await Promise.all(decks.map((d) => repository.cardStates.listByDeck(d.id)))
    return perDeck.flat()
  }

  async function findCard(cardId: string): Promise<Card> {
    for (const stored of await repository.decks.list()) {
      const card = deriveCards(stored.deck).find((c) => c.id === cardId)
      if (card) return card
    }
    throw new Error(`grade: no installed deck has card "${cardId}"`)
  }

  return {
    async getQueue(now) {
      const settings = await repository.settings.getAll()
      const decks = await repository.decks.list()
      const day = studyDay(now, settings.dayRolloverHour)
      const [states, todaysLog] = await Promise.all([
        loadStates(decks),
        repository.reviewLog.between(day.start, day.end),
      ])
      return buildQueue({ decks, states, todaysLog, settings, now })
    },

    async nextDue(now) {
      const decks = (await repository.decks.list()).filter((stored) => !stored.paused)
      let next: number | undefined
      for (const stored of decks) {
        const current = new Set(deriveCards(stored.deck).map((card) => card.id))
        for (const state of await repository.cardStates.listByDeck(stored.id)) {
          if (!current.has(state.cardId) || state.suspended || state.fsrs.phase === 'new') continue
          const due = Math.max(state.fsrs.due, state.buriedUntil ?? 0)
          if (due > now && (next === undefined || due < next)) next = due
        }
      }
      return next
    },

    async grade(cardId, rating, now, durationMs = 0) {
      const desiredRetention = await repository.settings.get('desiredRetention')
      const previous = await repository.cardStates.get(cardId)
      const identity = previous ?? (await findCard(cardId))
      const before = previous && previous.fsrs.phase !== 'new' ? previous.fsrs : null
      const after = nextState(before, rating, now, { desiredRetention })
      const threshold = await repository.settings.get('leechThreshold')
      const lapsed = after.lapses > (before?.lapses ?? 0)
      const becameLeech = lapsed && after.lapses >= threshold && !previous?.leech
      const state: CardState = {
        cardId,
        deckId: identity.deckId,
        optionId: identity.optionId,
        fsrs: after,
        suspended: becameLeech || (previous?.suspended ?? false),
        ...(previous?.buriedUntil === undefined ? {} : { buriedUntil: previous.buriedUntil }),
        ...(becameLeech || previous?.leech ? { leech: true } : {}),
      }
      const entry: ReviewLogEntry = {
        cardId,
        deckId: identity.deckId,
        reviewedAt: now,
        rating,
        durationMs,
        before,
        after,
      }
      const id = await repository.recordReview(state, entry)
      return { state, entry: { ...entry, id }, becameLeech }
    },

    async setAside(cardIds, how, now) {
      const rolloverHour = await repository.settings.get('dayRolloverHour')
      const current = await repository.cardStates.getMany(cardIds)
      const updated: CardState[] = []
      for (const [index, cardId] of cardIds.entries()) {
        const previous = current[index]
        const identity = previous ?? (await findCard(cardId))
        const base: CardState = previous ?? {
          cardId,
          deckId: identity.deckId,
          optionId: identity.optionId,
          fsrs: newFsrsState(now),
          suspended: false,
        }
        updated.push(
          how === 'suspend'
            ? { ...base, suspended: true }
            : { ...base, buriedUntil: nextStudyDayStart(now, rolloverHour) },
        )
      }
      await repository.cardStates.putMany(updated)
      return cardIds.map((cardId, index) => ({ cardId, state: current[index] }))
    },

    async restore(previous) {
      const existing = previous.flatMap((p) => (p.state ? [p.state] : []))
      const missing = previous.filter((p) => !p.state).map((p) => p.cardId)
      await repository.cardStates.putMany(existing)
      await repository.cardStates.deleteMany(missing)
    },

    async unsuspend(cardIds) {
      const states = (await repository.cardStates.getMany(cardIds)).flatMap((state) =>
        state?.suspended ? [{ ...state, suspended: false }] : [],
      )
      await repository.cardStates.putMany(states)
    },
  }
}
