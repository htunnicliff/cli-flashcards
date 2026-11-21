/**
 * Generates a deck from a tool's manpage(s) or `--help` output.
 *
 *   pnpm deck:generate rg
 *   pnpm deck:generate git --pages git-log,git-commit
 *   pnpm deck:generate sed --variant bsd --file path/to/bsd/sed.1
 *   pnpm deck:generate ruff --source help --pages check,format
 *
 * Options:
 *   --source manpage|help  where options come from (default: manpage)
 *   --pages a,b,c      manpage source: manpages to read (default: the tool's own
 *                      page); pages named `<tool>-<sub>` tag their options with
 *                      subcommand `<sub>`. help source: subcommands to run
 *                      `<tool> <sub> --help` for.
 *   --file a,b         read these files instead of locating pages or running the
 *                      tool, e.g. a BSD manpage on Linux or saved --help output
 *   --variant NAME     deck variant, e.g. gnu or bsd (default: `default`)
 *   --tool-version V   tool version to record (default: `<tool> --version`,
 *                      or `unknown` with --file)
 *   --sections A,B     only read these sections
 *   --license SPDX     license of the source text
 *   --attribution TXT  attribution line for the deck
 *   --out PATH         output file (default: decks/<tool>/<variant>.generated.json)
 *   --no-tldr          don't use vendored tldr-pages for tiers and examples
 *
 * The variant is always an explicit input; nothing is auto-detected. The
 * parsers themselves are pure; see tools/deck/generate.ts.
 */
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { mkdir, writeFile } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { parseArgs } from 'node:util'
import { gunzipSync } from 'node:zlib'
import { format } from 'prettier'
import { DeckValidationError, generateDeck, type PageInput } from './deck/generate'
import { loadTldrPages } from './deck/tldr-files'

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    source: { type: 'string', default: 'manpage' },
    pages: { type: 'string' },
    file: { type: 'string' },
    'tool-version': { type: 'string' },
    variant: { type: 'string', default: 'default' },
    sections: { type: 'string' },
    license: { type: 'string' },
    attribution: { type: 'string' },
    out: { type: 'string' },
    'no-tldr': { type: 'boolean', default: false },
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

const source = values.source
if (source !== 'manpage' && source !== 'help') {
  console.error('--source must be "manpage" or "help"')
  process.exit(2)
}
const list = (value: string | undefined) =>
  value
    ?.split(',')
    .map((item) => item.trim())
    .filter(Boolean)
const sections = list(values.sections)?.map((section) => section.toUpperCase())
const files = list(values.file)
const pageArgs = list(values.pages)

function helpText(args: string[]): string {
  const run = (flag: string) =>
    execFileSync(tool!, [...args, flag], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 10000,
    })
  try {
    return run('--help')
  } catch {
    return run('-h')
  }
}

function subcommandOf(name: string): string | undefined {
  return name.startsWith(`${tool}-`) ? name.slice(tool!.length + 1) : undefined
}

let pages: PageInput[]
if (files) {
  // Page names come from --pages when given, else from the file name (`git-log.1` → git-log).
  pages = files.map((path, index) => {
    const name = pageArgs?.[index] ?? path.split('/').pop()!.split('.')[0]!
    const subcommand = files.length > 1 || pageArgs ? subcommandOf(name) : undefined
    return {
      name,
      path,
      format: source,
      source: source === 'help' ? readFileSync(path, 'utf8') : readManpage(path),
      ...(subcommand ? { subcommand } : {}),
      ...(sections ? { sections } : {}),
    }
  })
} else if (source === 'help') {
  pages = (pageArgs ?? ['']).map((sub) => ({
    name: sub ? `${tool}-${sub}` : tool,
    format: 'help' as const,
    source: helpText(sub ? [sub] : []),
    ...(sub ? { subcommand: sub } : {}),
    ...(sections ? { sections } : {}),
  }))
} else {
  pages = (pageArgs ?? [tool]).map((name) => {
    const path = locate(name)
    const subcommand = pageArgs ? subcommandOf(name) : undefined
    return {
      name,
      path,
      source: readManpage(path),
      ...(subcommand ? { subcommand } : {}),
      ...(sections ? { sections } : {}),
    }
  })
}

try {
  const { deck, warnings } = generateDeck({
    tool,
    variant: values.variant!,
    toolVersion: values['tool-version'] ?? (files ? 'unknown' : toolVersion(tool)),
    pages,
    tldr: values['no-tldr'] ? [] : loadTldrPages(pages, values.variant!),
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
