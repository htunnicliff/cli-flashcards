/**
 * Reads tldr-pages markdown and matches its example commands against deck
 * options. The number of examples an option appears in is the usage signal
 * for relevance tiers, and the examples themselves are attached to options.
 */
import type { Example, OptionInput } from '../../pipeline/schema/deck'
import { isShortFlag } from '../../pipeline/schema/flags'
import { primaryFlag } from '../../pipeline/schema/cards'

export interface TldrExample {
  description: string
  /** The command with tldr placeholders resolved (`{{path}}` → `path`). */
  command: string
}

export interface TldrPage {
  /** Page name, e.g. `rg` or `git-log`. */
  name: string
  markdown: string
  /** Options matched against this page must have this subcommand. */
  subcommand?: string
}

/**
 * Resolves tldr placeholders: `{{[-i|--ignore-case]}}` becomes `-i` (the first
 * spelling; options are matched by any spelling anyway) and `{{path/to/file}}`
 * becomes `path/to/file`.
 */
export function resolvePlaceholders(command: string): string {
  return command
    .replace(/\{\{\[([^\]|]*)(?:\|[^\]]*)?\]\}\}/g, '$1')
    .replace(/\{\{(.*?)\}\}/g, '$1')
}

export function parseTldr(markdown: string): TldrExample[] {
  const examples: TldrExample[] = []
  let description: string | undefined
  for (const line of markdown.split('\n')) {
    const item = /^- (.+?):?\s*$/.exec(line)
    if (item) {
      description = item[1]!.trim()
      continue
    }
    const code = /^`(.+)`\s*$/.exec(line)
    if (code && description !== undefined) {
      examples.push({ description, command: resolvePlaceholders(code[1]!) })
      description = undefined
    }
  }
  return examples
}

interface Token {
  text: string
  start: number
}

function tokens(command: string): Token[] {
  const out: Token[] = []
  const re = /\S+/g
  let match: RegExpExecArray | null
  while ((match = re.exec(command))) out.push({ text: match[0], start: match.index })
  return out
}

/** Index from flag spelling to option, for one subcommand scope. */
function flagIndex(options: readonly OptionInput[], subcommand: string | undefined) {
  const index = new Map<string, OptionInput>()
  for (const option of options) {
    if ((option.subcommand ?? undefined) !== subcommand) continue
    for (const flag of option.flags) index.set(flag, option)
  }
  return index
}

interface Match {
  option: OptionInput
  token: Token
  /** The flag as written, without any `=value`. */
  flag: string
  /** Part of a combined short-flag token such as `-rn`. */
  combined?: boolean
  value?: string
}

/**
 * Finds the options a command uses. Tokens are matched by flag spelling
 * (`--glob=x` matches `--glob`). A single-dash token that is not itself a
 * flag, such as `-rn`, counts as each of its letters when every letter is a
 * known short flag.
 */
export function matchOptions(
  command: string,
  options: readonly OptionInput[],
  subcommand?: string,
): Match[] {
  const index = flagIndex(options, subcommand)
  const matches: Match[] = []
  for (const token of tokens(command)) {
    if (!token.text.startsWith('-') || token.text === '-' || token.text === '--') continue
    const eq = token.text.indexOf('=')
    const flag = eq === -1 ? token.text : token.text.slice(0, eq)
    const option = index.get(flag)
    if (option) {
      matches.push({
        option,
        token,
        flag,
        ...(eq === -1 ? {} : { value: token.text.slice(eq + 1) }),
      })
      continue
    }
    if (/^-[^-]{2,}$/.test(token.text)) {
      const letters = [...token.text.slice(1)].map((c) => index.get(`-${c}`))
      if (letters.every((o) => o !== undefined)) {
        for (const o of letters)
          matches.push({ option: o!, token, flag: token.text, combined: true })
      }
    }
  }
  return matches
}

/**
 * Rewrites long spellings to the option's primary flag when that is a short
 * flag, so examples match what is being learned:
 * `rg --files-with-matches x` → `rg -l x`, `rg --glob=*.ts` → `rg -g *.ts`.
 */
export function rewriteToPrimary(
  command: string,
  options: readonly OptionInput[],
  subcommand?: string,
): string {
  let out = ''
  let last = 0
  for (const match of matchOptions(command, options, subcommand)) {
    if (match.combined) continue
    const primary = primaryFlag({ flags: match.option.flags, primary: match.option.primary })
    if (match.flag === primary || !isShortFlag(primary) || isShortFlag(match.flag)) continue
    const replacement = match.value === undefined ? primary : `${primary} ${match.value}`
    out += command.slice(last, match.token.start) + replacement
    last = match.token.start + match.token.text.length
  }
  return out + command.slice(last)
}

export interface Usage {
  /** Option ID → number of tldr examples using it. */
  counts: Map<string, number>
  /** Option ID → examples that use it, simplest first. */
  examples: Map<string, Example[]>
}

/** Counts and collects tldr examples per option. */
export function tldrUsage(
  options: readonly OptionInput[],
  pages: readonly TldrPage[],
  maxExamples = 3,
): Usage {
  const counts = new Map<string, number>()
  const found = new Map<string, { example: Example; flags: number }[]>()
  for (const page of pages) {
    for (const example of parseTldr(page.markdown)) {
      const matches = matchOptions(example.command, options, page.subcommand)
      const ids = [...new Set(matches.map((match) => match.option.id))]
      for (const id of ids) {
        counts.set(id, (counts.get(id) ?? 0) + 1)
        const command = rewriteToPrimary(example.command, options, page.subcommand)
        const list = found.get(id) ?? []
        if (!list.some((entry) => entry.example.command === command)) {
          list.push({ example: { command, description: example.description }, flags: ids.length })
        }
        found.set(id, list)
      }
    }
  }
  const examples = new Map<string, Example[]>()
  for (const [id, list] of found) {
    examples.set(
      id,
      [...list]
        .sort((a, b) => a.flags - b.flags)
        .slice(0, maxExamples)
        .map((entry) => entry.example),
    )
  }
  return { counts, examples }
}

/** Flags mentioned in free text such as a SYNOPSIS or EXAMPLES section. */
export function mentionedFlags(text: string): Set<string> {
  const flags = new Set<string>()
  for (const match of text.matchAll(/(?:^|[\s[(|{,])(--?[A-Za-z0-9?.@#][\w.?#@+-]*)/g)) {
    const flag = match[1]!
    flags.add(flag.length > 2 ? flag.replace(/[.,]+$/, '') : flag)
  }
  return flags
}
