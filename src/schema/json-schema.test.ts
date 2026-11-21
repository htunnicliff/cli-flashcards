import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { DECK_JSON_SCHEMA_PATH, deckJsonSchema, deckJsonSchemaText } from './json-schema'

describe('deck JSON Schema', () => {
  it('matches the committed file (run `pnpm schema:export` if this fails)', () => {
    const committed = readFileSync(resolve(__dirname, '../..', DECK_JSON_SCHEMA_PATH), 'utf8')
    expect(committed).toBe(deckJsonSchemaText())
  })

  it('treats defaulted fields as optional', () => {
    const schema = deckJsonSchema() as {
      required: string[]
      properties: { options: { items: { required: string[] } } }
    }
    expect(schema.required).toContain('options')
    expect(schema.properties.options.items.required.sort()).toEqual([
      'flags',
      'id',
      'summary',
      'tier',
    ])
  })
})
