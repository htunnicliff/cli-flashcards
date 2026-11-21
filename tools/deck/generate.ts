/**
 * Turns parsed manpages into a deck. Pure: text in, deck out. The CLI in
 * `tools/deck-generate.ts` finds the files and writes the result.
 */
import { DeckSchema, SCHEMA_VERSION, type Deck, type OptionInput } from '../../src/schema/deck'
import { deriveOptionId } from '../../src/schema/flags'
import { parseManpage } from './manpage'
import type { RawEntry } from './manpage/types'
import { firstSentence } from './manpage/text'
import { parseTag } from './tag'
import { mentionedFlags, tldrUsage, type TldrPage } from './tldr'

/** Sections that describe the tool rather than list its options. */
const SKIPPED_SECTIONS = new Set([
  'NAME',
  'SYNOPSIS',
  'EXAMPLES',
  'EXAMPLE',
  'SEE ALSO',
  'ENVIRONMENT',
  'ENVIRONMENT VARIABLES',
  'FILES',
  'EXIT STATUS',
  'EXIT CODES',
  'RETURN VALUE',
  'DIAGNOSTICS',
  'BUGS',
  'AUTHOR',
  'AUTHORS',
  'REPORTING BUGS',
  'COPYRIGHT',
  'HISTORY',
  'CONFIGURATION',
  'STANDARDS',
  'CAVEATS',
  'SECURITY CONSIDERATIONS',
  'GIT',
])

export const TLDR_ATTRIBUTION =
  ' Examples adapted from tldr-pages (https://github.com/tldr-pages/tldr), CC BY 4.0.'

export interface PageInput {
  /** Page name, e.g. `rg` or `git-log`. */
  name: string
  /** The page's roff source (man or mdoc). */
  source: string
  /** Where it was read from, recorded in the deck. */
  path?: string
  /** Tag options from this page with a subcommand (`git log`). */
  subcommand?: string
  /** Only read these sections (upper case). Default: every section that lists options. */
  sections?: string[]
}

export interface GenerateInput {
  tool: string
  variant: string
  toolVersion: string
  pages: PageInput[]
  license?: string
  attribution?: string
  deckVersion?: number
  /**
   * tldr-pages for the tool. Options used in their examples become `core` and
   * get those examples attached. Without them, tiers come from the manpage alone.
   */
  tldr?: TldrPage[]
}

/** Manpage sections whose flag mentions make an option `common`. */
const MENTION_SECTIONS = ['SYNOPSIS', 'EXAMPLES', 'EXAMPLE']

/**
 * Default tiers: used in a tldr example → `core`; mentioned in the manpage's
 * SYNOPSIS or EXAMPLES → `common`; everything else → `obscure`. Curation
 * overrides can change any of them.
 */
export function assignTiers(
  options: OptionInput[],
  mentions: Map<string, Set<string>>,
  tldr: readonly TldrPage[],
): { usage: Map<string, number> } {
  const { counts, examples } = tldrUsage(options, tldr)
  for (const option of options) {
    const scope = mentions.get(option.subcommand ?? '') ?? new Set<string>()
    const used = (counts.get(option.id) ?? 0) > 0
    option.tier = used
      ? 'core'
      : option.flags.some((flag) => scope.has(flag))
        ? 'common'
        : 'obscure'
    const found = examples.get(option.id)
    if (found) option.examples = [...(option.examples ?? []), ...found]
  }
  return { usage: counts }
}

/** Flags mentioned in the SYNOPSIS/EXAMPLES text, with `-abc` clusters split into letters. */
function collectMentions(text: string, known: Set<string>): Set<string> {
  const out = new Set<string>()
  for (const flag of mentionedFlags(text)) {
    out.add(flag)
    if (!known.has(flag) && /^-[^-]{2,}$/.test(flag)) {
      for (const c of flag.slice(1)) out.add(`-${c}`)
    }
  }
  return out
}

export interface GenerateResult {
  deck: Deck
  /** Things a curator may want to look at: skipped tags, duplicate flags. */
  warnings: string[]
}

export class DeckValidationError extends Error {
  constructor(
    message: string,
    readonly issues: string[],
  ) {
    super(`${message}\n${issues.map((issue) => `  - ${issue}`).join('\n')}`)
    this.name = 'DeckValidationError'
  }
}

function wantedSection(entry: RawEntry, sections: string[] | undefined): boolean {
  if (sections) return sections.includes(entry.section)
  return !SKIPPED_SECTIONS.has(entry.section)
}

export function generateDeck(input: GenerateInput): GenerateResult {
  const warnings: string[] = []
  const options: OptionInput[] = []
  const ids = new Set<string>()
  /** `subcommand flag` → option ID that owns it. */
  const owners = new Map<string, string>()
  const sourcePages: NonNullable<Deck['sourcePages']> = []

  const parsedPages: { scope: string; text: string }[] = []

  for (const page of input.pages) {
    const parsed = parseManpage(page.source)
    parsedPages.push({
      scope: page.subcommand ?? '',
      text: MENTION_SECTIONS.map((name) => parsed.sectionText[name] ?? '').join('\n'),
    })
    sourcePages.push({
      name: page.name,
      ...(parsed.section ? { section: parsed.section } : {}),
      ...(page.path ? { path: page.path } : {}),
    })
    const where = (entry: RawEntry) => `${page.name}: ${entry.section}: "${entry.tag}"`
    for (const entry of parsed.entries) {
      if (!wantedSection(entry, page.sections)) continue
      const tag = parseTag(entry.tag)
      if (!tag) {
        warnings.push(`${where(entry)}: no flags recognised, skipped`)
        continue
      }
      const scope = page.subcommand ?? ''
      // Pages sometimes list an option twice (an overview, then the details).
      // Keep one option and the fuller description.
      const repeat = options.find(
        (option) =>
          (option.subcommand ?? '') === scope &&
          option.flags.length === tag.flags.length &&
          option.flags.every((flag) => tag.flags.includes(flag)),
      )
      if (repeat) {
        if (entry.description.length > (repeat.description ?? '').length) {
          repeat.description = entry.description
          repeat.summary = firstSentence(entry.description) || repeat.summary
        }
        continue
      }
      const flags = tag.flags.filter((flag) => {
        const owner = owners.get(`${scope} ${flag}`)
        if (owner) warnings.push(`${where(entry)}: ${flag} already belongs to "${owner}", dropped`)
        return !owner
      })
      if (flags.length === 0) continue
      const baseId = deriveOptionId(flags)
      const id = page.subcommand ? `${page.subcommand}.${baseId}` : baseId
      if (ids.has(id)) {
        warnings.push(`${where(entry)}: duplicate option ID "${id}", skipped`)
        continue
      }
      ids.add(id)
      for (const flag of flags) owners.set(`${scope} ${flag}`, id)
      const summary = firstSentence(entry.description) || `The ${flags.at(-1)} option.`
      options.push({
        id,
        flags,
        ...(tag.argument ? { argument: tag.argument } : {}),
        summary,
        description: entry.description,
        tier: 'obscure', // set by assignTiers below
        tags: page.subcommand ? [page.subcommand] : [],
        ...(page.subcommand ? { subcommand: page.subcommand } : {}),
      })
    }
  }

  const known = new Set(options.flatMap((option) => option.flags))
  const mentions = new Map<string, Set<string>>()
  for (const { scope, text } of parsedPages) {
    const set = mentions.get(scope) ?? new Set<string>()
    for (const flag of collectMentions(text, known)) set.add(flag)
    mentions.set(scope, set)
  }
  const tldr = input.tldr ?? []
  assignTiers(options, mentions, tldr)
  const usesTldr = options.some((option) => (option.examples ?? []).length > 0) && tldr.length > 0

  const pageList = sourcePages
    .map((page) => (page.section ? `${page.name}(${page.section})` : page.name))
    .join(', ')
  const candidate = {
    schemaVersion: SCHEMA_VERSION,
    id: `${input.tool}-${input.variant}`,
    tool: input.tool,
    variant: input.variant,
    toolVersion: input.toolVersion,
    deckVersion: input.deckVersion ?? 1,
    source: 'manpage' as const,
    license: input.license ?? 'NOASSERTION',
    attribution:
      (input.attribution ??
        `Generated from the ${pageList} manual page${sourcePages.length > 1 ? 's' : ''}.`) +
      (usesTldr ? TLDR_ATTRIBUTION : ''),
    sourcePages,
    options,
  }
  const result = DeckSchema.safeParse(candidate)
  if (!result.success) {
    throw new DeckValidationError(
      `The generated ${candidate.id} deck does not match the deck schema:`,
      result.error.issues.map((issue) => `${issue.path.join('.') || '(deck)'}: ${issue.message}`),
    )
  }
  return { deck: result.data, warnings }
}
