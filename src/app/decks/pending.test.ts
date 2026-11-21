import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createRepository, type Repository } from '@/core/storage'
import { fakeIndexedDB, uniqueDatabaseName } from '@/core/storage/test-utils'

import { installPendingDecks, useDecksChanged } from './pending'
import { fakeFetch, grepDeck, sedDeck } from './test-fixtures'

let repo: Repository

beforeEach(() => {
  repo = createRepository({ name: uniqueDatabaseName(), dependencies: fakeIndexedDB })
})

afterEach(async () => {
  await repo.destroy()
})

describe('installPendingDecks', () => {
  it('does nothing, not even fetch the deck list, when nothing is queued', async () => {
    const fetch = fakeFetch([grepDeck()])
    expect(await installPendingDecks(repo, { fetch })).toEqual({ installed: [], remaining: [] })
    expect(fetch.calls).toEqual([])
  })

  it('installs queued decks with their settings and keeps unknown ones queued', async () => {
    const changed = useDecksChanged()
    const before = changed.value
    await repo.settings.set('pendingDeckInstalls', [
      { id: 'grep-gnu', deckVersion: 1, includeObscure: true },
      { id: 'gone-gnu', deckVersion: 1, includeObscure: false },
    ])
    const result = await installPendingDecks(repo, { fetch: fakeFetch([grepDeck()]) })
    expect(result.installed.map((d) => d.id)).toEqual(['grep-gnu'])
    expect(result.remaining.map((d) => d.id)).toEqual(['gone-gnu'])
    expect(await repo.decks.get('grep-gnu')).toMatchObject({ includeObscure: true })
    expect(await repo.settings.get('pendingDeckInstalls')).toEqual(result.remaining)
    expect(changed.value).toBe(before + 1)
  })

  it('keeps a deck queued when its download fails', async () => {
    await repo.settings.set('pendingDeckInstalls', [
      { id: 'sed-gnu', deckVersion: 1, includeObscure: false },
    ])
    const serving = fakeFetch([sedDeck('gnu')])
    const failing = Object.assign(
      async (input: string) =>
        input.endsWith('index.json') ? serving(input) : new Response('', { status: 500 }),
      { calls: [] },
    )
    const result = await installPendingDecks(repo, { fetch: failing })
    expect(result.remaining.map((d) => d.id)).toEqual(['sed-gnu'])
    expect(await repo.decks.get('sed-gnu')).toBeUndefined()
  })

  it('shares one run between overlapping calls', async () => {
    await repo.settings.set('pendingDeckInstalls', [
      { id: 'grep-gnu', deckVersion: 1, includeObscure: false },
    ])
    const fetch = fakeFetch([grepDeck()])
    const [a, b] = await Promise.all([
      installPendingDecks(repo, { fetch }),
      installPendingDecks(repo, { fetch }),
    ])
    expect(a).toBe(b)
    expect(fetch.calls.filter((url) => url.endsWith('grep-gnu.json'))).toHaveLength(1)
  })
})
