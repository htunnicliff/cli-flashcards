/**
 * Writes the deck JSON Schema generated from the Zod schema.
 *
 *   pnpm schema:export          write schemas/deck.schema.json
 *   pnpm schema:export --check  fail if the committed file is out of date
 */
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { DECK_JSON_SCHEMA_PATH, deckJsonSchemaText } from '../src/schema/json-schema'

const target = resolve(process.cwd(), DECK_JSON_SCHEMA_PATH)
const text = deckJsonSchemaText()

if (process.argv.includes('--check')) {
  const current = await readFile(target, 'utf8').catch(() => '')
  if (current !== text) {
    console.error(`${DECK_JSON_SCHEMA_PATH} is out of date. Run \`pnpm schema:export\`.`)
    process.exit(1)
  }
  console.log(`${DECK_JSON_SCHEMA_PATH} is up to date.`)
} else {
  await mkdir(dirname(target), { recursive: true })
  await writeFile(target, text)
  console.log(`Wrote ${DECK_JSON_SCHEMA_PATH}`)
}
