import fc from 'fast-check'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { DeckSchema } from '../../schema'
import { makeDeck, makeOption } from '../../schema/fixtures'
import { createRepository, type CardPhase, type Rating, type Repository } from '../storage'
import {
  fakeIndexedDB,
  makeCardState,
  makeFsrsState,
  makeLogEntry,
  uniqueDatabaseName,
} from '../storage/test-utils'
import {
  backupFileName,
  BackupError,
  daysSinceBackup,
  exportBackup,
  importBackup,
  parseBackup,
  summarizeBackup,
  type Backup,
} from './backup'

const grep = DeckSchema.parse(makeDeck([makeOption(['-i', '--ignore-case'])]))
const rg = DeckSchema.parse(
  makeDeck([makeOption(['-i', '--ignore-case'])], { id: 'rg-rust', tool: 'rg', variant: 'rust' }),
)

const repos: Repository[] = []
function freshRepository(): Repository {
  const repo = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
  repos.push(repo)
  return repo
}

afterEach(async () => {
  await Promise.all(repos.splice(0).map((r) => r.destroy()))
})

/** Everything a backup should carry, in a comparable order, with a fixed export time. */
const snapshot = (repo: Repository) => exportBackup(repo, 0)

const cardIds = [
  'grep:gnu:ignore-case:cloze',
  'grep:gnu:ignore-case:flag-to-meaning',
  'rg:rust:ignore-case:cloze',
]

type Progress = typeof progress extends fc.Arbitrary<infer T> ? T : never

const progress = fc.record({
  states: fc.uniqueArray(
    fc.record({
      cardId: fc.constantFrom(...cardIds),
      phase: fc.constantFrom<CardPhase>('learning', 'review', 'relearning'),
      lastReview: fc.integer({ min: 0, max: 1e12 }),
      suspended: fc.boolean(),
    }),
    { selector: (s) => s.cardId },
  ),
  log: fc.array(
    fc.record({
      cardId: fc.constantFrom(...cardIds),
      reviewedAt: fc.integer({ min: 0, max: 1e12 }),
      rating: fc.constantFrom<Rating>(1, 2, 3, 4),
    }),
    { maxLength: 20 },
  ),
  retention: fc.constantFrom(0.8, 0.9, 0.95),
})

async function seed(repo: Repository, data: Progress) {
  await repo.decks.install(grep)
  await repo.cardStates.putMany(
    data.states.map((s) =>
      makeCardState(s.cardId, {
        deckId: s.cardId.startsWith('rg') ? 'rg-rust' : 'grep-gnu',
        fsrs: makeFsrsState({ phase: s.phase, lastReview: s.lastReview }),
        suspended: s.suspended,
      }),
    ),
  )
  for (const entry of data.log) {
    await repo.reviewLog.append(
      makeLogEntry(entry.cardId, {
        deckId: entry.cardId.startsWith('rg') ? 'rg-rust' : 'grep-gnu',
        reviewedAt: entry.reviewedAt,
        rating: entry.rating,
      }),
    )
  }
  await repo.settings.set('desiredRetention', data.retention)
}

describe('export and import', () => {
  it('round-trips into an empty database', async () => {
    await fc.assert(
      fc.asyncProperty(progress, async (data) => {
        const source = freshRepository()
        await seed(source, data)
        const backup = parseBackup(JSON.stringify(await exportBackup(source, 1)))

        const target = freshRepository()
        await target.decks.install(grep)
        await importBackup(target, backup, 'replace')
        expect(await snapshot(target)).toEqual(await snapshot(source))
      }),
      { numRuns: 20 },
    )
  })

  it('changes nothing when a backup is merged into its own database', async () => {
    await fc.assert(
      fc.asyncProperty(progress, async (data) => {
        const repo = freshRepository()
        await seed(repo, data)
        const before = await snapshot(repo)
        const result = await importBackup(repo, await exportBackup(repo, 1), 'merge')
        expect(result.addedReviews).toBe(0)
        expect(await snapshot(repo)).toEqual(before)
      }),
      { numRuns: 20 },
    )
  })

  it('merges by adding missing reviews and keeping the more recent card state', async () => {
    const card = 'grep:gnu:ignore-case:cloze'
    const other = 'grep:gnu:ignore-case:flag-to-meaning'
    const local = freshRepository()
    await local.decks.install(grep)
    await local.cardStates.putMany([
      makeCardState(card, { fsrs: makeFsrsState({ lastReview: 200, reps: 5 }) }),
      makeCardState(other, { fsrs: makeFsrsState({ lastReview: 100, reps: 1 }) }),
    ])
    await local.reviewLog.append(makeLogEntry(card, { reviewedAt: 200 }))
    await local.settings.set('newCardsPerDay', 5)

    const remote = freshRepository()
    await remote.decks.install(grep)
    await remote.cardStates.putMany([
      makeCardState(card, { fsrs: makeFsrsState({ lastReview: 150, reps: 4 }) }),
      makeCardState(other, { fsrs: makeFsrsState({ lastReview: 300, reps: 2 }) }),
    ])
    await remote.reviewLog.append(makeLogEntry(card, { reviewedAt: 200 }))
    await remote.reviewLog.append(makeLogEntry(other, { reviewedAt: 300 }))
    await remote.settings.set('newCardsPerDay', 50)

    const result = await importBackup(local, await exportBackup(remote), 'merge')
    expect(result.addedReviews).toBe(1)
    expect((await local.cardStates.get(card))?.fsrs.reps).toBe(5)
    expect((await local.cardStates.get(other))?.fsrs.reps).toBe(2)
    expect((await local.reviewLog.all()).map((e) => e.reviewedAt)).toEqual([200, 300])
    expect(await local.settings.get('newCardsPerDay')).toBe(5)
  })

  it('replace wipes local progress and takes the backup’s settings', async () => {
    const local = freshRepository()
    await local.decks.install(grep)
    await local.recordReview(
      makeCardState('grep:gnu:ignore-case:cloze'),
      makeLogEntry('grep:gnu:ignore-case:cloze'),
    )
    await local.settings.set('newCardsPerDay', 5)

    const remote = freshRepository()
    await remote.decks.install(grep)
    await remote.decks.setIncludeObscure('grep-gnu', true)
    await importBackup(local, await exportBackup(remote), 'replace')
    expect(await local.reviewLog.count()).toBe(0)
    expect(await local.cardStates.listByDeck('grep-gnu')).toEqual([])
    expect(await local.settings.get('newCardsPerDay')).toBe(20)
    expect((await local.decks.get('grep-gnu'))?.includeObscure).toBe(true)
  })

  it('queues decks this device has not installed', async () => {
    const remote = freshRepository()
    await remote.decks.install(grep)
    await remote.decks.install(rg)
    const local = freshRepository()
    await local.decks.install(grep)

    const result = await importBackup(local, await exportBackup(remote), 'merge')
    expect(result.pendingDecks).toEqual([{ id: 'rg-rust', deckVersion: 1, includeObscure: false }])
    expect(await local.settings.get('pendingDeckInstalls')).toEqual(result.pendingDecks)
  })

  it('leaves device-only settings behind and records the backup time', async () => {
    const repo = freshRepository()
    await repo.settings.set('persistence', { requestedAt: 1, granted: true })
    const backup = await exportBackup(repo, 1234)
    expect(Object.keys(backup.settings).sort()).toEqual([
      'dayRolloverHour',
      'desiredRetention',
      'maxReviewsPerDay',
      'newCardsPerDay',
    ])
    expect(await repo.settings.get('lastBackupAt')).toBe(1234)
  })
})

describe('parseBackup', () => {
  let valid: Backup
  beforeEach(async () => {
    const repo = freshRepository()
    await repo.decks.install(grep)
    await repo.reviewLog.append(makeLogEntry('grep:gnu:ignore-case:cloze', { reviewedAt: 10 }))
    await repo.reviewLog.append(makeLogEntry('grep:gnu:ignore-case:cloze', { reviewedAt: 90 }))
    valid = await exportBackup(repo, 100)
  })

  it('accepts a JSON string', () => {
    expect(parseBackup(JSON.stringify(valid))).toEqual(valid)
  })

  it.each([
    ['not json', '{', /valid JSON/],
    ['another file', { hello: 'world' }, /isn’t a --recall backup/],
    ['a newer version', { format: 'recall-backup', backupVersion: 99 }, /newer version/],
  ])('rejects %s', (_, input, message) => {
    expect(() => parseBackup(input)).toThrow(BackupError)
    expect(() => parseBackup(input)).toThrow(message)
  })

  it('says where a damaged backup is wrong', () => {
    const damaged = { ...valid, reviewLog: [{ ...valid.reviewLog[0], rating: 7 }] }
    expect(() => parseBackup(damaged)).toThrow(/reviewLog\.0\.rating/)
  })

  it('summarises decks, reviews and their date range', () => {
    expect(summarizeBackup(valid)).toEqual({
      decks: ['grep-gnu'],
      cards: 0,
      reviews: 2,
      firstReview: 10,
      lastReview: 90,
      exportedAt: 100,
    })
  })
})

describe('helpers', () => {
  it('names the file by local date', () => {
    expect(backupFileName(new Date(2026, 0, 5, 23).getTime())).toBe('recall-backup-2026-01-05.json')
  })

  it('counts whole days since the last backup', () => {
    const day = 24 * 60 * 60 * 1000
    expect(daysSinceBackup(null, 0)).toBeUndefined()
    expect(daysSinceBackup(0, day - 1)).toBe(0)
    expect(daysSinceBackup(0, 3 * day + 5)).toBe(3)
  })
})
