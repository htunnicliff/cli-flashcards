import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { deckJsonSchema, jsonSchemaFiles } from './json-schema'

describe('deck JSON Schema', () => {
  it.each(jsonSchemaFiles())(
    '$path matches the committed file (run `pnpm schema:export` if this fails)',
    ({ path, text }) => {
      const committed = readFileSync(resolve(__dirname, '../..', path), 'utf8')
      expect(committed).toBe(text)
    },
  )

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
