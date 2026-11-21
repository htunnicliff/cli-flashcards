import { computed, onScopeDispose, ref, shallowRef } from 'vue'

import { formatInterval } from '@/core/review'
import { createScheduler, nextState, type QueueItem, type Queue } from '@/core/scheduler'
import {
  requestPersistenceOnce,
  type CardState,
  type Rating,
  type StorageManagerLike,
} from '@/core/storage'
import type { Deck, Option } from '@/schema'

import { useRepository } from '../repository'

export const RATINGS: { rating: Rating; label: string; key: string }[] = [
  { rating: 1, label: 'Again', key: '1' },
  { rating: 2, label: 'Hard', key: '2' },
  { rating: 3, label: 'Good', key: '3' },
  { rating: 4, label: 'Easy', key: '4' },
]

interface Graded {
  item: QueueItem
  /** The card's state before the grade, to restore on undo. */
  previous: CardState | undefined
  entryId: number
}

export interface ReviewSessionOptions {
  now?: () => number
  storage?: StorageManagerLike
}

/**
 * The review screen's state. Grading and undo update what's on screen
 * immediately; writes to IndexedDB run one after another in the background,
 * so fast keyboard grading is never held up by storage or animation.
 */
export function useReviewSession(options: ReviewSessionOptions = {}) {
  const repository = useRepository()
  const scheduler = createScheduler(repository)
  const now = options.now ?? (() => Date.now())

  const items = shallowRef<QueueItem[]>([])
  const today = shallowRef<Queue['today']>()
  const nextLearningDue = ref<number>()
  const nextDue = ref<number>()
  const decks = shallowRef(new Map<string, Deck>())
  const loading = ref(true)
  const revealed = ref(false)
  const desiredRetention = ref(0.9)
  const gradedThisSession = ref(0)
  /** The rating of the last grade, so the leaving card can drift the right way. */
  const lastRating = ref<Rating>()
  const error = ref<string>()

  const history: Graded[] = []
  /** Cards graded on screen whose write hasn't run yet; a refresh must not bring them back. */
  const pending = new Set<string>()
  let shownAt = now()
  let writes: Promise<unknown> = Promise.resolve()
  let learningTimer: ReturnType<typeof setTimeout> | undefined

  const current = computed(() => items.value[0])
  const done = computed(() => !loading.value && items.value.length === 0)

  const counts = computed(() => {
    const result = { new: 0, learning: 0, review: 0 }
    for (const item of items.value) result[item.kind]++
    return result
  })

  /** The option behind the current card, for its argument and examples. */
  const option = computed<Option | undefined>(() => {
    const card = current.value?.card
    if (!card) return undefined
    return decks.value.get(card.deckId)?.options.find((o) => o.id === card.optionId)
  })
  const deck = computed(() =>
    current.value ? decks.value.get(current.value.card.deckId) : undefined,
  )

  /** Next interval for each rating, from the card's current state. */
  const intervals = computed(() => {
    const item = current.value
    if (!item) return {} as Record<Rating, string>
    const at = now()
    const before = item.state && item.state.fsrs.phase !== 'new' ? item.state.fsrs : null
    const result = {} as Record<Rating, string>
    for (const { rating } of RATINGS) {
      const after = nextState(before, rating, at, { desiredRetention: desiredRetention.value })
      result[rating] = formatInterval(after.due - at)
    }
    return result
  })

  function enqueue(work: () => Promise<unknown>) {
    writes = writes.then(work).catch((cause) => {
      error.value = cause instanceof Error ? cause.message : String(cause)
    })
    return writes
  }

  /** Reloads the queue, keeping the card on screen in front if it is still due. */
  async function refresh() {
    const [queue, stored, retention, upcoming] = await Promise.all([
      scheduler.getQueue(now()),
      repository.decks.list(),
      repository.settings.get('desiredRetention'),
      scheduler.nextDue(now()),
    ])
    decks.value = new Map(stored.map((s) => [s.id, s.deck]))
    desiredRetention.value = retention
    today.value = queue.today
    nextLearningDue.value = queue.nextLearningDue
    nextDue.value = upcoming
    const onScreen = items.value[0]
    let next = queue.items.filter((item) => !pending.has(item.card.id))
    if (onScreen && !loading.value) {
      const fresh = next.find((item) => item.card.id === onScreen.card.id)
      next = [fresh ?? onScreen, ...next.filter((item) => item.card.id !== onScreen.card.id)]
    }
    items.value = next
    loading.value = false
    scheduleLearningRefresh()
  }

  /** When only learning cards remain for later today, come back when the next is due. */
  function scheduleLearningRefresh() {
    if (learningTimer) clearTimeout(learningTimer)
    learningTimer = undefined
    if (items.value.length > 0 || nextLearningDue.value === undefined) return
    const wait = Math.max(0, nextLearningDue.value - now()) + 50
    learningTimer = setTimeout(() => void enqueue(refresh), Math.min(wait, 2 ** 31 - 1))
  }
  onScopeDispose(() => learningTimer && clearTimeout(learningTimer))

  function reveal() {
    if (current.value) revealed.value = true
  }

  /** Grades the card on screen and moves on at once; the write follows. */
  function grade(rating: Rating) {
    const item = current.value
    if (!item || !revealed.value) return
    const at = now()
    const durationMs = at - shownAt
    lastRating.value = rating
    items.value = items.value.slice(1)
    revealed.value = false
    shownAt = at
    gradedThisSession.value++
    pending.add(item.card.id)
    void enqueue(async () => {
      const previous = await repository.cardStates.get(item.card.id)
      try {
        const { entry } = await scheduler.grade(item.card.id, rating, at, durationMs)
        history.push({ item, previous, entryId: entry.id! })
      } finally {
        pending.delete(item.card.id)
      }
      await refresh()
      if (items.value.length === 0) {
        await requestPersistenceOnce(
          repository,
          options.storage ?? (typeof navigator === 'undefined' ? undefined : navigator.storage),
        )
      }
    })
  }

  /** Takes back the last grade: the card returns, unrevealed, with its old state. */
  function undo() {
    return enqueue(async () => {
      const last = history.pop()
      if (!last) return
      await repository.undoReview(last.entryId, last.item.card.id, last.previous)
      gradedThisSession.value = Math.max(0, gradedThisSession.value - 1)
      lastRating.value = undefined
      items.value = [last.item, ...items.value.filter((i) => i.card.id !== last.item.card.id)]
      revealed.value = false
      shownAt = now()
      await refresh()
    })
  }

  /** Whether there is a grade from this session to take back. */
  const canUndo = computed(() => gradedThisSession.value > 0)
  /** Whether any deck is installed, so the empty state can point to the Decks page. */
  const hasDecks = computed(() => decks.value.size > 0)

  /** Resolves once every queued write has finished. Tests use it. */
  const settled = () => writes

  void enqueue(refresh)

  return {
    items,
    current,
    deck,
    option,
    today,
    counts,
    done,
    loading,
    revealed,
    intervals,
    nextDue,
    nextLearningDue,
    lastRating,
    gradedThisSession,
    error,
    reveal,
    grade,
    undo,
    canUndo,
    hasDecks,
    refresh: () => enqueue(refresh),
    settled,
  }
}

export type ReviewSession = ReturnType<typeof useReviewSession>
