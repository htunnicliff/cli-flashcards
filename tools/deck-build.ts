/**
 * Builds every deck the app ships:
 *
 *   decks/<tool>/<variant>.generated.json   (from `pnpm deck:generate`)
 * + decks/<tool>/<variant>.overrides.yaml   (hand-written, optional)
 * → public/decks/<tool>-<variant>.json      (what the app loads)
 * + public/decks/index.json                 (manifest of all decks)
 *
 *   pnpm deck:build           build and write
 *   pnpm deck:build --check   fail if the built files are out of date or any
 *                             override is stale (used in CI)
 *
 * Stale overrides (naming option IDs the generated deck no longer has) are
 * warnings locally and errors with --check or when CI is set.
 */
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { mkdir, rm, writeFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { parseArgs } from 'node:util'
import { format } from 'prettier'
import { parse as parseYaml } from 'yaml'
import { MANIFEST_VERSION, type DeckManifest } from '../src/schema/manifest'
import { buildDeck, manifestEntry } from './deck/build'
import { DeckValidationError } from './deck/generate'

const { values } = parseArgs({ options: { check: { type: 'boolean', default: false } } })
const check = values.check!
const strict = check || Boolean(process.env.CI)

const root = process.cwd()
const decksDir = resolve(root, 'decks')
const outDir = resolve(root, 'public', 'decks')

function readJson(path: string): unknown {
  return existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : undefined
}

interface Source {
  tool: string
  variant: string
  generated: string
  overrides: string
}

function findSources(): Source[] {
  if (!existsSync(decksDir)) return []
  return readdirSync(decksDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .flatMap((dir) =>
      readdirSync(join(decksDir, dir.name))
        .filter((file) => file.endsWith('.generated.json'))
        .map((file) => {
          const variant = file.replace(/\.generated\.json$/, '')
          return {
            tool: dir.name,
            variant,
            generated: join(decksDir, dir.name, file),
            overrides: join(decksDir, dir.name, `${variant}.overrides.yaml`),
          }
        }),
    )
    .sort((a, b) => `${a.tool}-${a.variant}`.localeCompare(`${b.tool}-${b.variant}`))
}

const outputs = new Map<string, string>()
const manifest: DeckManifest = { manifestVersion: MANIFEST_VERSION, decks: [] }
let failed = false

for (const source of findSources()) {
  const label = `${source.tool}/${source.variant}`
  const overridesText = existsSync(source.overrides)
    ? readFileSync(source.overrides, 'utf8')
    : undefined
  try {
    const generated = readJson(source.generated)
    const id = (generated as { id?: string } | undefined)?.id ?? `${source.tool}-${source.variant}`
    const file = `${id}.json`
    const { deck, stale } = buildDeck(
      {
        generated,
        overrides: overridesText === undefined ? undefined : (parseYaml(overridesText) ?? {}),
        previous: readJson(join(outDir, file)),
      },
      label,
    )
    for (const message of stale) {
      console[strict ? 'error' : 'warn'](
        `${strict ? 'error' : 'warning'}: ${label}: stale override: ${message}`,
      )
    }
    if (stale.length > 0 && strict) failed = true
    const text = `${JSON.stringify(deck)}\n`
    outputs.set(file, text)
    manifest.decks.push(manifestEntry(deck, file, Buffer.byteLength(text)))
  } catch (error) {
    if (!(error instanceof DeckValidationError)) throw error
    console.error(error.message)
    failed = true
  }
}

outputs.set(
  'index.json',
  await format(JSON.stringify(manifest), { parser: 'json', printWidth: 100 }),
)

if (check) {
  const existing = existsSync(outDir) ? readdirSync(outDir).filter((f) => f.endsWith('.json')) : []
  for (const [file, text] of outputs) {
    const path = join(outDir, file)
    if (!existsSync(path) || readFileSync(path, 'utf8') !== text) {
      console.error(`error: public/decks/${file} is out of date. Run \`pnpm deck:build\`.`)
      failed = true
    }
  }
  for (const file of existing) {
    if (!outputs.has(file)) {
      console.error(`error: public/decks/${file} has no source deck. Run \`pnpm deck:build\`.`)
      failed = true
    }
  }
  if (!failed) console.log(`${manifest.decks.length} deck(s) up to date.`)
} else if (!failed) {
  await mkdir(outDir, { recursive: true })
  for (const file of readdirSync(outDir).filter((f) => f.endsWith('.json'))) {
    if (!outputs.has(file)) await rm(join(outDir, file))
  }
  for (const [file, text] of outputs) await writeFile(join(outDir, file), text)
  for (const entry of manifest.decks) {
    console.log(`Built ${entry.file}: ${entry.optionCount} options, v${entry.deckVersion}`)
  }
}

if (failed) process.exit(1)
