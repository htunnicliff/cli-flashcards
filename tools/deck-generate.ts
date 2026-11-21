/**
 * Generates a deck from a tool's manpage(s).
 *
 *   pnpm deck:generate rg
 *   pnpm deck:generate git --pages git-log,git-commit
 *
 * Options:
 *   --pages a,b,c      manpages to read (default: the tool's own page). Pages
 *                      named `<tool>-<sub>` tag their options with subcommand `<sub>`.
 *   --variant NAME     deck variant (default: `default`)
 *   --sections A,B     only read these manpage sections
 *   --license SPDX     license of the source text
 *   --attribution TXT  attribution line for the deck
 *   --out PATH         output file (default: decks/<tool>/<variant>.generated.json)
 *
 * Needs `man` on PATH to locate pages. The parser itself is pure; see
 * tools/deck/generate.ts.
 */
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { mkdir, writeFile } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { parseArgs } from 'node:util'
import { gunzipSync } from 'node:zlib'
import { format } from 'prettier'
import { DeckValidationError, generateDeck, type PageInput } from './deck/generate'

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    pages: { type: 'string' },
    variant: { type: 'string', default: 'default' },
    sections: { type: 'string' },
    license: { type: 'string' },
    attribution: { type: 'string' },
    out: { type: 'string' },
  },
})

const tool = positionals[0]
if (!tool) {
  console.error('Usage: pnpm deck:generate <tool> [--pages a,b] [--variant name] [--out path]')
  process.exit(2)
}

/** Reads a manpage file, gunzipping and following `.so` includes. */
export function readManpage(path: string, depth = 0): string {
  const raw = readFileSync(path)
  const text = (path.endsWith('.gz') ? gunzipSync(raw) : raw).toString('utf8')
  const include = /^\.so\s+(\S+)\s*$/m.exec(text)
  if (include && text.trim().split('\n').length === 1 && depth < 3) {
    // `.so man1/foo.1` is relative to the man root (the parent of man1/).
    const root = dirname(dirname(path))
    const target = [join(root, include[1]!), `${join(root, include[1]!)}.gz`].find(existsSync)
    if (target) return readManpage(target, depth + 1)
  }
  return text
}

const MAN_DIRS = ['/usr/share/man', '/usr/local/share/man', '/opt/homebrew/share/man', '/usr/man']

function locate(page: string): string {
  try {
    const found = execFileSync('man', ['-w', page], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    })
      .trim()
      .split('\n')[0]
    if (found && existsSync(found)) return found
  } catch {
    // Fall through to searching the usual directories.
  }
  for (const dir of MAN_DIRS) {
    for (const section of ['1', '8', '6']) {
      for (const ext of ['', '.gz']) {
        const candidate = join(dir, `man${section}`, `${page}.${section}${ext}`)
        if (existsSync(candidate)) return candidate
      }
    }
  }
  throw new Error(`Could not find a manpage for "${page}". Is it installed? (man -w ${page})`)
}

function toolVersion(command: string): string {
  try {
    const output = execFileSync(command, ['--version'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 5000,
    })
    const match = /\d+(?:\.\d+)+[\w.+-]*/.exec(output.split('\n')[0] ?? '')
    return match?.[0] ?? 'unknown'
  } catch {
    return 'unknown'
  }
}

const pageNames = values.pages ? values.pages.split(',').map((name) => name.trim()) : [tool]
const sections = values.sections?.split(',').map((section) => section.trim().toUpperCase())
const pages: PageInput[] = pageNames.map((name) => {
  const path = locate(name)
  const subcommand =
    values.pages && name.startsWith(`${tool}-`) ? name.slice(tool.length + 1) : undefined
  return {
    name,
    path,
    source: readManpage(path),
    ...(subcommand ? { subcommand } : {}),
    ...(sections ? { sections } : {}),
  }
})

try {
  const { deck, warnings } = generateDeck({
    tool,
    variant: values.variant!,
    toolVersion: toolVersion(tool),
    pages,
    ...(values.license ? { license: values.license } : {}),
    ...(values.attribution ? { attribution: values.attribution } : {}),
  })
  const out = resolve(values.out ?? join('decks', tool, `${values.variant}.generated.json`))
  const schemaPath = join('..', '..', 'schemas', 'deck.schema.json')
  const json = JSON.stringify({ $schema: schemaPath, ...deck })
  await mkdir(dirname(out), { recursive: true })
  await writeFile(out, await format(json, { parser: 'json', printWidth: 100 }))
  for (const warning of warnings) console.warn(`warning: ${warning}`)
  console.log(`Wrote ${deck.options.length} options to ${out}`)
} catch (error) {
  if (error instanceof DeckValidationError) {
    console.error(error.message)
    process.exit(1)
  }
  throw error
}
