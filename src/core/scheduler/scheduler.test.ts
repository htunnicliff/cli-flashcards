import fc from 'fast-check'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { DeckSchema, type Deck } from '../../schema'
import { makeDeck, makeOption } from '../../schema/fixtures'
import { createRepository, type Rating, type Repository } from '../storage'
import { fakeIndexedDB, uniqueDatabaseName } from '../storage/test-utils'
import { replay } from './fsrs'
import { createScheduler, type Scheduler } from './scheduler'

const MINUTE = 60 * 1000
const DAY = 24 * 60 * MINUTE
/** Local noon, well clear of the 4 AM rollover. */
const at = (day: number, hour = 12, minute = 0) => new Date(2026, 0, day, hour, minute).getTime()

/** Each option yields flag-to-meaning and meaning-to-flag cards (no examples, so no cloze). */
function deck(options: Parameters<typeof makeOption>[], overrides: Partial<Deck> = {}): Deck {
  return DeckSchema.parse(
    makeDeck(
      options.map((args) => makeOption(...args)),
      overrides,
    ),
  )
}

const grep = deck([
  [['-v', '--invert-match'], { tier: 'common' }],
  [['-i', '--ignore-case'], { tier: 'core' }],
  [['-P', '--perl-regexp'], { tier: 'obscure' }],
  [['-c', '--count'], { tier: 'core' }],
])

let repo: Repository
let scheduler: Scheduler

beforeEach(async () => {
  repo = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
  scheduler = createScheduler(repo)
  await repo.decks.install(grep)
})

afterEach(async () => {
  await repo.destroy()
})

const ids = async (now: number) => (await scheduler.getQueue(now)).items.map((i) => i.card.id)

/** Grades the card until it leaves learning, returning when it is next due. */
async function graduate(cardId: string, now: number): Promise<number> {
  let { state } = await scheduler.grade(cardId, 3, now)
  while (state.fsrs.phase !== 'review') {
    ;({ state } = await scheduler.grade(cardId, 3, state.fsrs.due))
  }
  return state.fsrs.due
}

describe('nextDue', () => {
  it('is undefined before anything is studied', async () => {
    expect(await scheduler.nextDue(at(10))).toBeUndefined()
  })

  it('finds the earliest future due card, ignoring paused decks', async () => {
    const due = await graduate('grep:gnu:ignore-case:flag-to-meaning', at(10))
    expect(await scheduler.nextDue(at(10, 13))).toBe(due)
    await repo.decks.setPaused('grep-gnu', true)
    expect(await scheduler.nextDue(at(10, 13))).toBeUndefined()
  })
})

describe('getQueue', () => {
  it('introduces new cards core first, one card per option, skipping obscure', async () => {
    expect(await ids(at(10))).toEqual([
      'grep:gnu:ignore-case:flag-to-meaning',
      'grep:gnu:count:flag-to-meaning',
      'grep:gnu:invert-match:flag-to-meaning',
    ])
  })

  it('includes obscure options when the deck opts in', async () => {
    await repo.decks.setIncludeObscure('grep-gnu', true)
    expect(await ids(at(10))).toContain('grep:gnu:perl-regexp:flag-to-meaning')
  })

  it('skips paused decks and picks them up again when resumed', async () => {
    await repo.decks.setPaused('grep-gnu', true)
    expect(await ids(at(10))).toEqual([])
    await repo.decks.setPaused('grep-gnu', false)
    expect(await ids(at(10))).toHaveLength(3)
  })

  it('respects the daily new-card limit, counting cards already introduced today', async () => {
    await repo.settings.set('newCardsPerDay', 2)
    const first = await scheduler.getQueue(at(10))
    expect(first.items.map((i) => i.kind)).toEqual(['new', 'new'])
    expect(first.today).toMatchObject({ newDone: 0, newLeft: 2 })

    await scheduler.grade(first.items[0]!.card.id, 3, at(10))
    const second = await scheduler.getQueue(at(10, 12, 1))
    expect(second.today).toMatchObject({ newDone: 1, newLeft: 1 })
    expect(second.items.filter((i) => i.kind === 'new')).toHaveLength(1)
  })

  it('shows a first-reviewed card again when its learning step is due', async () => {
    const cardId = 'grep:gnu:ignore-case:flag-to-meaning'
    const { state } = await scheduler.grade(cardId, 3, at(10))
    expect(state.fsrs.phase).toBe('learning')

    const soon = await scheduler.getQueue(at(10, 12, 1))
    expect(soon.items.map((i) => i.card.id)).not.toContain(cardId)
    expect(soon.nextLearningDue).toBe(state.fsrs.due)

    const later = await scheduler.getQueue(state.fsrs.due)
    expect(later.items[0]).toMatchObject({ kind: 'learning', card: { id: cardId } })
  })

  it('buries siblings for the rest of the day, then shows them after rollover', async () => {
    const card = 'grep:gnu:ignore-case:flag-to-meaning'
    const sibling = 'grep:gnu:ignore-case:meaning-to-flag'
    const due = await graduate(card, at(10))
    const sameDay = await ids(at(10, 23))
    expect(sameDay).not.toContain(sibling)
    expect(sameDay).not.toContain(card)

    // 2 AM is still the 10th's study day with the default 4 AM rollover.
    expect(await ids(at(11, 2))).not.toContain(sibling)
    const nextDay = await ids(at(11, 5))
    expect(nextDay).toContain(sibling)
    expect(due).toBeGreaterThan(at(11, 5))
  })

  it('shows due reviews before new cards and caps them at the daily limit', async () => {
    const reviewIds = [
      'grep:gnu:ignore-case:flag-to-meaning',
      'grep:gnu:count:flag-to-meaning',
      'grep:gnu:invert-match:flag-to-meaning',
    ]
    for (const id of reviewIds) await graduate(id, at(1))
    await repo.settings.set('maxReviewsPerDay', 2)

    const queue = await scheduler.getQueue(at(28))
    expect(queue.items.map((i) => i.kind)).toEqual(['review', 'review', 'new'])
    expect(queue.today).toMatchObject({ reviewsDone: 0, reviewsLeft: 2 })

    await scheduler.grade(queue.items[0]!.card.id, 3, at(28))
    const after = await scheduler.getQueue(at(28, 12, 1))
    expect(after.today).toMatchObject({ reviewsDone: 1, reviewsLeft: 1 })
    expect(after.items.filter((i) => i.kind === 'review')).toHaveLength(1)
  })

  it('moves a lapsed review into relearning and brings it back the same day', async () => {
    const cardId = 'grep:gnu:count:flag-to-meaning'
    const due = await graduate(cardId, at(1))
    const { state, entry } = await scheduler.grade(cardId, 1, due)
    expect(state.fsrs).toMatchObject({ phase: 'relearning', lapses: 1 })
    expect(entry.before?.phase).toBe('review')

    const queue = await scheduler.getQueue(state.fsrs.due)
    expect(queue.items[0]).toMatchObject({ kind: 'learning', card: { id: cardId } })
  })

  it('skips suspended and buried cards', async () => {
    const [first, second] = (await scheduler.getQueue(at(10))).items
    await repo.cardStates.put({
      ...(await scheduler.grade(first!.card.id, 3, at(1))).state,
      suspended: true,
    })
    await repo.cardStates.put({
      cardId: second!.card.id,
      deckId: 'grep-gnu',
      optionId: second!.card.optionId,
      fsrs: (await scheduler.grade(second!.card.id, 3, at(1))).state.fsrs,
      suspended: false,
      buriedUntil: at(20),
    })
    const queue = await ids(at(10))
    expect(queue).not.toContain(first!.card.id)
    expect(queue).not.toContain(second!.card.id)
    expect(await ids(at(21))).toContain(second!.card.id)
  })

  it('ignores progress for options a new deck version dropped', async () => {
    await graduate('grep:gnu:invert-match:flag-to-meaning', at(1))
    await repo.decks.install(
      deck([[['-i', '--ignore-case'], { tier: 'core' }]], { deckVersion: 2 }),
    )
    expect(await ids(at(28))).toEqual(['grep:gnu:ignore-case:flag-to-meaning'])
  })
})

describe('grade', () => {
  it('writes every grade to the review log', async () => {
    const cardId = 'grep:gnu:ignore-case:flag-to-meaning'
    const { entry } = await scheduler.grade(cardId, 3, at(10), 2_500)
    expect(await repo.reviewLog.forCard(cardId)).toEqual([entry])
    expect(entry).toMatchObject({ deckId: 'grep-gnu', rating: 3, durationMs: 2_500, before: null })
    expect(await repo.cardStates.get(cardId)).toMatchObject({ fsrs: entry.after })
  })

  it('uses the desired retention setting', async () => {
    const intervalAt = async (retention: number) => {
      await repo.resetProgress()
      await repo.settings.set('desiredRetention', retention)
      return (await graduate('grep:gnu:count:flag-to-meaning', at(1))) - at(1)
    }
    expect(await intervalAt(0.8)).toBeGreaterThan(await intervalAt(0.95))
  })

  it('rejects a card no installed deck has', async () => {
    await expect(scheduler.grade('grep:gnu:nope:cloze', 3, at(10))).rejects.toThrow(
      /no installed deck/,
    )
  })

  it('stores a state that replaying the review log reproduces', async () => {
    const cardId = 'grep:gnu:invert-match:meaning-to-flag'
    await fc.assert(
      fc.asyncProperty(
        fc.array(
          fc.record({
            rating: fc.constantFrom<Rating>(1, 2, 3, 4),
            gap: fc.integer({ min: 0, max: 30 * DAY }),
          }),
          { minLength: 1, maxLength: 8 },
        ),
        async (steps) => {
          await repo.resetProgress()
          let now = at(1)
          for (const step of steps) {
            now += step.gap
            await scheduler.grade(cardId, step.rating, now)
          }
          const stored = await repo.cardStates.get(cardId)
          const log = await repo.reviewLog.forCard(cardId)
          expect(replay(log, { desiredRetention: 0.9 })).toEqual(stored!.fsrs)
        },
      ),
      { numRuns: 25 },
    )
  })
})
