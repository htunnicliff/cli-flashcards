import { z } from 'zod'
import { DeckSchema } from './deck'
import { OverridesSchema } from './overrides'

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

/** Where `pnpm schema:export` writes the overrides JSON Schema. */
export const OVERRIDES_JSON_SCHEMA_PATH = 'schemas/overrides.schema.json'

/** JSON Schema for `decks/<tool>/<variant>.overrides.yaml`, for editor completion. */
export function overridesJsonSchema(): Record<string, unknown> {
  return {
    ...z.toJSONSchema(OverridesSchema, { io: 'input', target: 'draft-2020-12' }),
    $id: 'https://github.com/htunnicliff/cli-flashcards/schemas/overrides.schema.json',
    title: 'CLI Flashcards deck overrides',
  }
}

export function overridesJsonSchemaText(): string {
  return `${JSON.stringify(overridesJsonSchema(), null, 2)}\n`
}

/** Every exported schema file and its contents. */
export function jsonSchemaFiles(): { path: string; text: string }[] {
  return [
    { path: DECK_JSON_SCHEMA_PATH, text: deckJsonSchemaText() },
    { path: OVERRIDES_JSON_SCHEMA_PATH, text: overridesJsonSchemaText() },
  ]
}
