import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import type { Deck } from '../../src/schema/deck'

const decksDir = new URL('../fixtures/decks/', import.meta.url)

/** A fixture deck as the app would fetch it from `decks/`. */
export function fixtureDeck(file = 'ripgrep-fixture.json'): Deck {
  return JSON.parse(readFileSync(fileURLToPath(new URL(file, decksDir)), 'utf8')) as Deck
}
