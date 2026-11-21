import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { DeckSchema } from '@/schema'
import { makeDeck, makeOption } from '@/schema/fixtures'

import { activeCardStates, createRepository, type Repository } from './repository'
import { SETTING_DEFAULTS } from './types'
import {
  fakeIndexedDB,
  makeCardState,
  makeFsrsState,
  makeLogEntry,
  uniqueDatabaseName,
} from './test-utils'

const grepV1 = DeckSchema.parse(
  makeDeck([makeOption(['-i', '--ignore-case']), makeOption(['-v', '--invert-match'])]),
)
const grepV2 = DeckSchema.parse(makeDeck([makeOption(['-i', '--ignore-case'])], { deckVersion: 2 }))

let repo: Repository

beforeEach(() => {
  repo = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
})

afterEach(async () => {
  await repo.destroy()
})

describe('decks', () => {
  it('installs, lists and removes decks', async () => {
    const stored = await repo.decks.install(grepV1, 100)
    expect(stored).toMatchObject({
      id: 'grep-gnu',
      deckVersion: 1,
      installedAt: 100,
      updatedAt: 100,
      includeObscure: false,
    })
    expect(await repo.decks.get('grep-gnu')).toEqual(stored)
    expect(await repo.decks.list()).toHaveLength(1)

    await repo.decks.remove('grep-gnu')
    expect(await repo.decks.get('grep-gnu')).toBeUndefined()
  })

  it('keeps install time and preferences when a new version is installed', async () => {
    await repo.decks.install(grepV1, 100)
    await repo.decks.setIncludeObscure('grep-gnu', true)
    const updated = await repo.decks.install(grepV2, 200)
    expect(updated).toMatchObject({
      deckVersion: 2,
      installedAt: 100,
      updatedAt: 200,
      includeObscure: true,
    })
    expect(updated.deck.options).toHaveLength(1)
  })

  it('refuses preferences for a deck that is not installed', async () => {
    await expect(repo.decks.setIncludeObscure('nope', true)).rejects.toThrow(/not installed/)
  })

  it('keeps progress when a deck is updated or removed', async () => {
    await repo.decks.install(grepV1)
    const state = makeCardState('grep:gnu:v:flag-to-meaning')
    await repo.recordReview(state, makeLogEntry(state.cardId))

    await repo.decks.install(grepV2)
    await repo.decks.remove('grep-gnu')

    expect(await repo.cardStates.get(state.cardId)).toEqual(state)
    expect(await repo.reviewLog.count()).toBe(1)
  })
})

describe('cardStates', () => {
  it('stores and reads states by card, deck and due date', async () => {
    const early = makeCardState('grep:gnu:i:flag-to-meaning', { fsrs: makeFsrsState({ due: 10 }) })
    const late = makeCardState('grep:gnu:v:flag-to-meaning', { fsrs: makeFsrsState({ due: 50 }) })
    const other = makeCardState('rg:rust:i:cloze', { fsrs: makeFsrsState({ due: 5 }) })
    await repo.cardStates.putMany([late, early, other])

    expect(await repo.cardStates.get(early.cardId)).toEqual(early)
    expect(await repo.cardStates.getMany([late.cardId, 'missing', early.cardId])).toEqual([
      late,
      undefined,
      early,
    ])
    expect((await repo.cardStates.listByDeck('grep-gnu')).map((s) => s.cardId).sort()).toEqual(
      [early.cardId, late.cardId].sort(),
    )
    expect((await repo.cardStates.dueBy(20)).map((s) => s.cardId)).toEqual([
      other.cardId,
      early.cardId,
    ])

    await repo.cardStates.put({ ...early, suspended: true })
    expect((await repo.cardStates.get(early.cardId))?.suspended).toBe(true)
  })

  it('ignores states for options a deck no longer has, and restores them when the option returns', async () => {
    const kept = makeCardState('grep:gnu:ignore-case:flag-to-meaning')
    const dropped = makeCardState('grep:gnu:invert-match:flag-to-meaning')
    const foreign = makeCardState('rg:rust:ignore-case:flag-to-meaning')
    await repo.cardStates.putMany([kept, dropped, foreign])
    const stored = await repo.cardStates.listByDeck('grep-gnu')

    expect(
      activeCardStates(grepV1, stored)
        .map((s) => s.cardId)
        .sort(),
    ).toEqual([kept.cardId, dropped.cardId].sort())
    expect(activeCardStates(grepV2, stored).map((s) => s.cardId)).toEqual([kept.cardId])
    expect(activeCardStates(grepV1, [foreign])).toEqual([])
  })
})

describe('reviewLog', () => {
  it('appends entries and reads them back in review order', async () => {
    const a = 'grep:gnu:i:flag-to-meaning'
    const b = 'grep:gnu:v:cloze'
    const idLate = await repo.reviewLog.append(makeLogEntry(a, { reviewedAt: 300 }))
    const idEarly = await repo.reviewLog.append(makeLogEntry(a, { reviewedAt: 100 }))
    await repo.reviewLog.append(makeLogEntry(b, { reviewedAt: 200 }))
    await repo.reviewLog.append(makeLogEntry('rg:rust:i:cloze', { reviewedAt: 400 }))

    expect(idEarly).toBeGreaterThan(idLate)
    expect((await repo.reviewLog.forCard(a)).map((e) => e.reviewedAt)).toEqual([100, 300])
    expect((await repo.reviewLog.forDeck('grep-gnu')).map((e) => e.reviewedAt)).toEqual([
      100, 200, 300,
    ])
    expect((await repo.reviewLog.between(100, 300)).map((e) => e.reviewedAt)).toEqual([100, 200])
    expect((await repo.reviewLog.all()).map((e) => e.reviewedAt)).toEqual([100, 200, 300, 400])
    expect(await repo.reviewLog.count()).toBe(4)
  })

  it('ignores an id passed in and assigns its own', async () => {
    const id = await repo.reviewLog.append(makeLogEntry('grep:gnu:i:cloze', { id: 999 }))
    expect(id).not.toBe(999)
    expect((await repo.reviewLog.all())[0]?.id).toBe(id)
  })
})

describe('recordReview', () => {
  it('writes the state and the log entry together', async () => {
    const state = makeCardState('grep:gnu:i:flag-to-meaning')
    const id = await repo.recordReview(state, makeLogEntry(state.cardId, { reviewedAt: 5 }))
    expect(await repo.cardStates.get(state.cardId)).toEqual(state)
    expect(await repo.reviewLog.all()).toEqual([
      expect.objectContaining({ id, cardId: state.cardId, reviewedAt: 5 }),
    ])
  })

  it('writes neither when one write fails', async () => {
    const state = makeCardState('grep:gnu:i:flag-to-meaning')
    // A function can't be structured-cloned, so the log write throws.
    const bad = makeLogEntry(state.cardId, { durationMs: (() => 0) as unknown as number })
    await expect(repo.recordReview(state, bad)).rejects.toThrow()
    expect(await repo.cardStates.get(state.cardId)).toBeUndefined()
    expect(await repo.reviewLog.count()).toBe(0)
  })
})

describe('resetProgress', () => {
  beforeEach(async () => {
    for (const cardId of ['grep:gnu:i:cloze', 'rg:rust:i:cloze']) {
      await repo.recordReview(makeCardState(cardId), makeLogEntry(cardId))
    }
    await repo.decks.install(grepV1)
  })

  it('clears one deck', async () => {
    await repo.resetProgress('grep-gnu')
    expect(await repo.cardStates.listByDeck('grep-gnu')).toEqual([])
    expect((await repo.reviewLog.all()).map((e) => e.deckId)).toEqual(['rg-rust'])
    expect(await repo.decks.get('grep-gnu')).toBeDefined()
  })

  it('clears every deck', async () => {
    await repo.resetProgress()
    expect(await repo.cardStates.dueBy(Infinity)).toEqual([])
    expect(await repo.reviewLog.count()).toBe(0)
    expect(await repo.decks.list()).toHaveLength(1)
  })
})

describe('settings', () => {
  it('returns defaults until a value is set', async () => {
    expect(await repo.settings.get('persistence')).toBeNull()
    await repo.settings.set('persistence', { requestedAt: 1, granted: true })
    expect(await repo.settings.get('persistence')).toEqual({ requestedAt: 1, granted: true })
    expect(await repo.settings.getAll()).toEqual({
      ...SETTING_DEFAULTS,
      persistence: { requestedAt: 1, granted: true },
    })
  })
})

it('keeps data across reopening', async () => {
  const name = uniqueDatabaseName()
  const first = createRepository({ name, dependencies: fakeIndexedDB })
  await first.decks.install(grepV1)
  first.close()

  const second = createRepository({ name, dependencies: fakeIndexedDB })
  expect(await second.decks.get('grep-gnu')).toBeDefined()
  await second.destroy()
})
