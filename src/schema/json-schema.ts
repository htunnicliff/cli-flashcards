import { z } from 'zod'
import { DeckSchema } from './deck'

/** Where `pnpm schema:export` writes the deck JSON Schema, relative to the repo root. */
export const DECK_JSON_SCHEMA_PATH = 'schemas/deck.schema.json'

/**
 * JSON Schema for deck files. It describes the input shape, so fields with
 * defaults (`hidden`, `tags`, …) are optional. Cross-field rules (short-first
 * ordering, unique IDs and flags) are only enforced by `DeckSchema.parse`.
 */
export function deckJsonSchema(): Record<string, unknown> {
  return {
    ...z.toJSONSchema(DeckSchema, { io: 'input', target: 'draft-2020-12' }),
    $id: 'https://github.com/htunnicliff/cli-flashcards/schemas/deck.schema.json',
    title: 'CLI Flashcards deck',
  }
}

export function deckJsonSchemaText(): string {
  return `${JSON.stringify(deckJsonSchema(), null, 2)}\n`
}
