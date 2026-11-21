import { computed, onScopeDispose, ref, shallowRef } from 'vue'

import { checkAnswer, type AnswerResult } from '@/core/answers'
import { formatInterval } from '@/core/review'
import {
  createScheduler,
  nextState,
  type PreviousState,
  type QueueItem,
  type Queue,
} from '@/core/scheduler'
import {
  requestPersistenceOnce,
  type CardState,
  type Rating,
  type StorageManagerLike,
} from '@/core/storage'
import { deriveCards, isFlagPairCard, type Card, type Deck, type Option } from '@/schema'

import { holdUpdatesDuring, holdUpdatesWhile } from '../pwa/update-holds'
import { useRepository } from '../repository'

export const RATINGS: { rating: Rating; label: string; key: string }[] = [
  { rating: 1, label: 'Again', key: '1' },
  { rating: 2, label: 'Hard', key: '2' },
  { rating: 3, label: 'Good', key: '3' },
  { rating: 4, label: 'Easy', key: '4' },
]

interface Graded {
  kind: 'grade'
  item: QueueItem
  /** The card's state before the grade, to restore on undo. */
  previous: CardState | undefined
  entryId: number
}

interface SetAside {
  kind: 'aside'
  item: QueueItem
  previous: PreviousState[]
}

/** How the last card left the screen, so it can animate the right way. */
export type LeaveHint = { kind: 'grade'; rating: Rating } | { kind: 'aside' } | undefined

/** A message for the snackbar, with an undo button unless `undoable` is false. */
export interface ReviewNotice {
  id: number
  message: string
  undoable: boolean
  /** Where to read more, such as a leech's full description. */
  link?: { to: string; label: string }
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
  /** Decks with typed answers turned on. */
  const typedDecks = shallowRef(new Set<string>())
  const loading = ref(true)
  const revealed = ref(false)
  const desiredRetention = ref(0.9)
  /** Flag pair practice: card fronts show one form of a flag, never both. */
  const flagPairs = ref(false)
  const gradedThisSession = ref(0)
  /** The rating of the last grade, so the leaving card can drift the right way. */
  const lastRating = ref<Rating>()
  const leaveHint = shallowRef<LeaveHint>()
  const notice = shallowRef<ReviewNotice>()
  /** Actions in this session that undo can take back. */
  const undoable = ref(0)
  let noticeId = 0
  const error = ref<string>()
  /** The checked typed answer for the card on screen, once submitted. */
  const answer = shallowRef<AnswerResult & { typed: string }>()

  const history: (Graded | SetAside)[] = []
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

  /** Whether the card on screen asks for its flag to be typed. */
  const typing = computed(() => {
    const card = current.value?.card
    return Boolean(card && card.type !== 'flag-to-meaning' && typedDecks.value.has(card.deckId))
  })

  /** The grade a typed answer suggests: Good when right, Again when wrong. */
  const suggestedRating = computed<Rating | undefined>(() =>
    answer.value ? (answer.value.correct ? 3 : 1) : undefined,
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
    // A reload into a new version mid-write could lose a grade.
    writes = writes
      .then(() => holdUpdatesDuring(work))
      .catch((cause) => {
        error.value = cause instanceof Error ? cause.message : String(cause)
      })
    return writes
  }

  /** Reloads the queue, keeping the card on screen in front if it is still due. */
  async function refresh() {
    const [queue, stored, retention, upcoming, pairs] = await Promise.all([
      scheduler.getQueue(now()),
      repository.decks.list(),
      repository.settings.get('desiredRetention'),
      scheduler.nextDue(now()),
      repository.settings.get('flagPairs'),
    ])
    flagPairs.value = pairs
    decks.value = new Map(stored.map((s) => [s.id, s.deck]))
    typedDecks.value = new Set(stored.filter((s) => s.typeAnswers).map((s) => s.id))
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

  /** Checks a typed answer against the card on screen and reveals the back. */
  function submitAnswer(typed: string) {
    const item = current.value
    const target = option.value
    if (!item || !target || revealed.value) return
    const options = deck.value?.options ?? [target]
    const only = isFlagPairCard(item.card) ? item.card.targets : undefined
    answer.value = {
      typed,
      ...checkAnswer(typed, { option: target, options, style: deck.value?.parsingStyle, only }),
    }
    revealed.value = true
  }

  /** Grades the card on screen and moves on at once; the write follows. */
  function grade(rating: Rating) {
    const item = current.value
    if (!item || !revealed.value) return
    const at = now()
    const durationMs = at - shownAt
    lastRating.value = rating
    leaveHint.value = { kind: 'grade', rating }
    undoable.value++
    items.value = items.value.slice(1)
    revealed.value = false
    answer.value = undefined
    shownAt = at
    gradedThisSession.value++
    pending.add(item.card.id)
    void enqueue(async () => {
      const previous = await repository.cardStates.get(item.card.id)
      try {
        const { entry, state, becameLeech } = await scheduler.grade(
          item.card.id,
          rating,
          at,
          durationMs,
        )
        history.push({ kind: 'grade', item, previous, entryId: entry.id! })
        if (becameLeech) {
          showNotice({
            message: `Forgotten ${state.fsrs.lapses} times, so this card is now suspended as a leech.`,
            undoable: false,
            link: {
              to: `/decks/${item.card.deckId}#option-${item.card.optionId}`,
              label: 'Read the full description',
            },
          })
        }
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
      if (last.kind === 'grade') {
        await repository.undoReview(last.entryId, last.item.card.id, last.previous)
        gradedThisSession.value = Math.max(0, gradedThisSession.value - 1)
      } else {
        await scheduler.restore(last.previous)
      }
      undoable.value = Math.max(0, undoable.value - 1)
      notice.value = undefined
      lastRating.value = undefined
      leaveHint.value = undefined
      items.value = [last.item, ...items.value.filter((i) => i.card.id !== last.item.card.id)]
      revealed.value = false
      answer.value = undefined
      shownAt = now()
      await refresh()
    })
  }

  /**
   * Sets the card on screen aside without grading it: suspends it (or, with
   * `scope: 'option'`, every card for its option) or buries it until tomorrow.
   */
  function setAside(how: 'suspend' | 'bury', scope: 'card' | 'option' = 'card') {
    const item = current.value
    if (!item) return
    const at = now()
    const cardIds =
      scope === 'option'
        ? deriveCards(decks.value.get(item.card.deckId)!, { flagPairs: true })
            .filter((card) => card.optionId === item.card.optionId)
            .map((card) => card.id)
        : [item.card.id]
    leaveHint.value = { kind: 'aside' }
    undoable.value++
    items.value = items.value.filter((i) => !cardIds.includes(i.card.id))
    revealed.value = false
    answer.value = undefined
    shownAt = at
    for (const id of cardIds) pending.add(id)
    const message =
      how === 'bury'
        ? 'Buried until tomorrow.'
        : scope === 'option'
          ? `Suspended every card for ${frontFlag(item.card)}.`
          : 'Card suspended.'
    showNotice({ message, undoable: true })
    void enqueue(async () => {
      try {
        const previous = await scheduler.setAside(cardIds, how, at)
        history.push({ kind: 'aside', item, previous })
      } finally {
        for (const id of cardIds) pending.delete(id)
      }
      await refresh()
    })
  }

  function showNotice(next: Omit<ReviewNotice, 'id'>) {
    notice.value = { ...next, id: ++noticeId }
  }

  function dismissNotice() {
    notice.value = undefined
  }

  /** Whether there is an action from this session to take back. */
  const canUndo = computed(() => undoable.value > 0)
  /** Whether any deck is installed, so the empty state can point to the Decks page. */
  const hasDecks = computed(() => decks.value.size > 0)

  /** Resolves once every queued write has finished. Tests use it. */
  const settled = () => writes

  // Never reload into a new version with cards left to review.
  holdUpdatesWhile(() => !done.value)

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
    leaveHint,
    flagPairs,
    notice,
    gradedThisSession,
    error,
    typing,
    answer,
    suggestedRating,
    reveal,
    submitAnswer,
    grade,
    setAside,
    dismissNotice,
    undo,
    canUndo,
    hasDecks,
    refresh: () => enqueue(refresh),
    settled,
  }
}

export type ReviewSession = ReturnType<typeof useReviewSession>

/**
 * The flag to name a card by on screen. A flag pair card goes by the form its
 * front shows, so a label such as "Suspend all -r cards" never gives the answer away.
 */
export function frontFlag(card: Card): string {
  return isFlagPairCard(card) ? card.shown : card.flag
}
