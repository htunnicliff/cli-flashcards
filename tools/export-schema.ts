/**
 * Writes the JSON Schemas generated from the Zod schemas.
 *
 *   pnpm schema:export          write schemas/*.schema.json
 *   pnpm schema:export --check  fail if a committed file is out of date
 */
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { jsonSchemaFiles } from '../src/schema/json-schema'

const check = process.argv.includes('--check')
let stale = false

for (const { path, text } of jsonSchemaFiles()) {
  const target = resolve(process.cwd(), path)
  if (check) {
    const current = await readFile(target, 'utf8').catch(() => '')
    if (current !== text) {
      console.error(`${path} is out of date. Run \`pnpm schema:export\`.`)
      stale = true
    } else {
      console.log(`${path} is up to date.`)
    }
  } else {
    await mkdir(dirname(target), { recursive: true })
    await writeFile(target, text)
    console.log(`Wrote ${path}`)
  }
}

if (stale) process.exit(1)
