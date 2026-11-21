import { DeckSchema, type Deck } from '@/schema'
import { makeDeck, makeOption } from '@/schema/fixtures'
import { manifestEntry, type DeckManifest } from '@/schema/manifest'

import type { FetchLike } from './catalog'

export function grepDeck(version = 1, extra: Parameters<typeof makeOption>[] = []): Deck {
  return DeckSchema.parse(
    makeDeck(
      [
        makeOption(['-i', '--ignore-case'], { tier: 'core', summary: 'Match case-insensitively' }),
        makeOption(['-v', '--invert-match'], {
          tier: 'common',
          summary: 'Select non-matching lines',
        }),
        ...extra.map((args) => makeOption(...args)),
      ],
      { deckVersion: version },
    ),
  )
}

export function sedDeck(variant: 'gnu' | 'bsd'): Deck {
  return DeckSchema.parse(
    makeDeck([makeOption(['-n', '--quiet'], { tier: 'core' })], {
      id: `sed-${variant}`,
      tool: 'sed',
      variant,
    }),
  )
}

/** A fetch that serves the given decks and a manifest listing them. */
export function fakeFetch(decks: Deck[]): FetchLike & { calls: string[] } {
  const calls: string[] = []
  const files = new Map(decks.map((deck) => [`${deck.id}.json`, JSON.stringify(deck)]))
  const manifest: DeckManifest = {
    manifestVersion: 1,
    decks: decks.map((deck) =>
      manifestEntry(deck, `${deck.id}.json`, files.get(`${deck.id}.json`)!.length),
    ),
  }
  const fn = async (input: string) => {
    calls.push(input)
    const name = input.split('/').pop()!
    if (name === 'index.json') return new Response(JSON.stringify(manifest))
    const body = files.get(name)
    return body ? new Response(body) : new Response('missing', { status: 404 })
  }
  return Object.assign(fn, { calls })
}
