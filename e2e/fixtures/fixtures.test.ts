import { readdirSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import { describe, expect, it } from 'vitest'

import { DeckSchema } from '../../src/schema/deck'
import { DeckManifestSchema } from '../../src/schema/manifest'

const dir = fileURLToPath(new URL('./decks/', import.meta.url))
const deckFiles = readdirSync(dir).filter((file) => file.endsWith('.json') && file !== 'index.json')

// Fixture decks must stay valid, or E2E failures would point at the fixture, not the app.
describe('E2E fixture decks', () => {
  it.each(deckFiles)('%s matches the deck schema', (file) => {
    const result = DeckSchema.safeParse(JSON.parse(readFileSync(dir + file, 'utf8')))
    expect(result.error?.issues ?? []).toEqual([])
  })

  it('index.json lists every fixture deck', () => {
    const index = DeckManifestSchema.parse(JSON.parse(readFileSync(dir + 'index.json', 'utf8')))
    expect(index.decks.map((deck) => deck.file).sort()).toEqual([...deckFiles].sort())
  })
})
