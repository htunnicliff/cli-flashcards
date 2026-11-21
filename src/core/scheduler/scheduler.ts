import { deriveCards, type Card } from '../../schema'
import type { CardState, Rating, Repository, ReviewLogEntry, StoredDeck } from '../storage'
import { nextState } from './fsrs'
import { buildQueue, studyDay, type Queue } from './queue'

export interface GradeResult {
  state: CardState
  entry: ReviewLogEntry
}

export interface Scheduler {
  /** What to study at `now`, across every installed deck. */
  getQueue(now: number): Promise<Queue>
  /**
   * Grades a card: computes its next FSRS state, then stores the state and a
   * review log entry together. `durationMs` is how long the user took.
   */
  grade(cardId: string, rating: Rating, now: number, durationMs?: number): Promise<GradeResult>
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

    async grade(cardId, rating, now, durationMs = 0) {
      const desiredRetention = await repository.settings.get('desiredRetention')
      const previous = await repository.cardStates.get(cardId)
      const identity = previous ?? (await findCard(cardId))
      const before = previous && previous.fsrs.phase !== 'new' ? previous.fsrs : null
      const after = nextState(before, rating, now, { desiredRetention })
      const state: CardState = {
        cardId,
        deckId: identity.deckId,
        optionId: identity.optionId,
        fsrs: after,
        suspended: previous?.suspended ?? false,
        ...(previous?.buriedUntil === undefined ? {} : { buriedUntil: previous.buriedUntil }),
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
      return { state, entry: { ...entry, id } }
    },
  }
}
