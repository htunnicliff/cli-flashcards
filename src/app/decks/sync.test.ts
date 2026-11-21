import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createRepository, type Repository } from '@/core/storage'
import { fakeIndexedDB, uniqueDatabaseName } from '@/core/storage/test-utils'
import { DeckSchema } from '@/schema'
import { makeDeck, makeOption } from '@/schema/fixtures'

import { describeSync, setDeckFlavor, syncDecks, useDecksChanged } from './sync'
import { fakeFetch, grepDeck, sedDeck } from './test-fixtures'

const LINUX = 'Mozilla/5.0 (X11; Linux x86_64)'
const MAC = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5)'

let repo: Repository

beforeEach(() => {
  repo = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
})

afterEach(async () => {
  await repo.destroy()
})

function jqDeck() {
  return DeckSchema.parse(
    makeDeck([makeOption(['-r', '--raw-output'], { tier: 'core' })], {
      id: 'jq-default',
      tool: 'jq',
      variant: 'default',
    }),
  )
}

const ids = async () => (await repo.decks.list()).map((d) => d.id).sort()

describe('syncDecks', () => {
  it('downloads one deck per tool, in the platform flavor, all studied on a new device', async () => {
    const changed = useDecksChanged()
    const before = changed.value
    const decks = [grepDeck(), sedDeck('gnu'), sedDeck('bsd'), jqDeck()]
    const result = await syncDecks(repo, { fetch: fakeFetch(decks), userAgent: MAC })
    expect(await ids()).toEqual(['grep-gnu', 'jq-default', 'sed-bsd'])
    expect((await repo.decks.list()).every((d) => !d.paused)).toBe(true)
    expect(result.downloaded.map((d) => d.id).sort()).toEqual(['grep-gnu', 'jq-default', 'sed-bsd'])
    expect(changed.value).toBe(before + 1)
    expect(describeSync(result)).toBe('Downloaded 3 decks.')
  })

  it('does nothing when every deck is current', async () => {
    const fetch = fakeFetch([grepDeck()])
    await syncDecks(repo, { fetch, userAgent: LINUX })
    const result = await syncDecks(repo, { fetch, userAgent: LINUX })
    expect(result.downloaded).toEqual([])
    expect(describeSync(result)).toBeUndefined()
  })

  it('starts new tools paused for someone already studying, so reviews are not flooded', async () => {
    await repo.decks.install(grepDeck())
    await syncDecks(repo, { fetch: fakeFetch([grepDeck(), jqDeck()]), userAgent: LINUX })
    expect(await repo.decks.get('jq-default')).toMatchObject({ paused: true })
    expect((await repo.decks.get('grep-gnu'))?.paused).toBeFalsy()
  })

  it('updates outdated decks and keeps their settings and progress', async () => {
    await repo.decks.install(grepDeck(1))
    await repo.decks.setTypeAnswers('grep-gnu', true)
    const v2 = grepDeck(2, [[['-c', '--count'], { tier: 'core' }]])
    const result = await syncDecks(repo, { fetch: fakeFetch([v2]), userAgent: LINUX })
    expect(await repo.decks.get('grep-gnu')).toMatchObject({ deckVersion: 2, typeAnswers: true })
    expect(describeSync(result)).toBe('Updated grep to version 2: 1 option added.')
  })

  it('keeps the flavor someone already downloaded until they pick one', async () => {
    await repo.decks.install(sedDeck('bsd'))
    const fetch = fakeFetch([sedDeck('gnu'), sedDeck('bsd'), grepDeck()])
    await syncDecks(repo, { fetch, userAgent: LINUX })
    // sed stays BSD; grep only comes in GNU, so that's what downloads.
    expect(await ids()).toEqual(['grep-gnu', 'sed-bsd'])
  })

  it('swaps every tool to a picked flavor, keeping settings and progress', async () => {
    await repo.decks.install(sedDeck('bsd'), undefined, { paused: true, includeObscure: true })
    await repo.reviewLog.append({
      cardId: 'sed:bsd:quiet:flag-to-meaning',
      deckId: 'sed-bsd',
      reviewedAt: 1,
      rating: 3,
      durationMs: 1,
      before: null,
      after: {
        phase: 'learning',
        due: 2,
        stability: 1,
        difficulty: 5,
        elapsedDays: 0,
        scheduledDays: 0,
        learningSteps: 1,
        reps: 1,
        lapses: 0,
      },
    })
    const fetch = fakeFetch([sedDeck('gnu'), sedDeck('bsd')])
    const result = await setDeckFlavor(repo, 'gnu', { fetch, userAgent: MAC })
    expect(await ids()).toEqual(['sed-gnu'])
    expect(await repo.decks.get('sed-gnu')).toMatchObject({ paused: true, includeObscure: true })
    expect(await repo.reviewLog.count()).toBe(1)
    expect(describeSync(result)).toBe('Switched sed to GNU / Linux.')
  })

  it('drops the other flavor when someone with both picks one', async () => {
    await repo.decks.install(sedDeck('bsd'))
    await repo.decks.install(sedDeck('gnu'))
    const fetch = fakeFetch([sedDeck('gnu'), sedDeck('bsd')])
    await setDeckFlavor(repo, 'bsd', { fetch, userAgent: LINUX })
    expect(await ids()).toEqual(['sed-bsd'])
  })

  it('installs decks a backup queued, with their settings, and keeps unknown ones queued', async () => {
    await repo.decks.install(jqDeck())
    await repo.settings.set('pendingDeckInstalls', [
      { id: 'grep-gnu', deckVersion: 1, includeObscure: true },
      { id: 'gone-gnu', deckVersion: 1, includeObscure: false },
    ])
    const result = await syncDecks(repo, { fetch: fakeFetch([grepDeck(), jqDeck()]) })
    expect(result.restored.map((d) => d.id)).toEqual(['grep-gnu'])
    // Restored decks were in use, so they aren't paused like other new tools.
    expect(await repo.decks.get('grep-gnu')).toMatchObject({ includeObscure: true })
    expect((await repo.decks.get('grep-gnu'))?.paused).toBeFalsy()
    expect((await repo.settings.get('pendingDeckInstalls')).map((d) => d.id)).toEqual(['gone-gnu'])
  })

  it('leaves failed downloads for next time', async () => {
    const working = fakeFetch([grepDeck(), jqDeck()])
    const fetch = async (input: string, init?: RequestInit) =>
      input.endsWith('jq-default.json')
        ? new Response('down', { status: 503 })
        : working(input, init)
    const result = await syncDecks(repo, { fetch, userAgent: LINUX })
    expect(result.failed).toEqual(['jq-default'])
    expect(await ids()).toEqual(['grep-gnu'])
    await syncDecks(repo, { fetch: working, userAgent: LINUX })
    expect(await ids()).toEqual(['grep-gnu', 'jq-default'])
  })

  it('shares one run between concurrent callers', async () => {
    const fetch = fakeFetch([grepDeck()])
    const [a, b] = await Promise.all([
      syncDecks(repo, { fetch, userAgent: LINUX }),
      syncDecks(repo, { fetch, userAgent: LINUX }),
    ])
    expect(a).toBe(b)
    expect(fetch.calls.filter((url) => url.endsWith('grep-gnu.json'))).toHaveLength(1)
  })
})
