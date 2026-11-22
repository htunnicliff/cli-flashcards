/**
 * Builds the deck the app loads: generated deck + curation overrides,
 * validated, with `deckVersion` bumped whenever the content changes.
 */
import { createHash } from 'node:crypto'
import { DeckSchema, type Deck } from '../../pipeline/schema/deck'
import { OverridesSchema } from '../../pipeline/schema/overrides'
import { DeckValidationError } from './generate'
import { applyOverrides } from './overrides'

export interface BuildInput {
  /** Parsed `<variant>.generated.json`. */
  generated: unknown
  /** Parsed `<variant>.overrides.yaml`, if there is one. */
  overrides?: unknown
  /** The previously built deck, used to carry `deckVersion` forward. */
  previous?: unknown
}

export interface BuildResult {
  deck: Deck
  /** Overrides that refer to options the generated deck no longer has. */
  stale: string[]
}

function issues(error: { issues: { path: PropertyKey[]; message: string }[] }): string[] {
  return error.issues.map(
    (issue) => `${issue.path.map(String).join('.') || '(root)'}: ${issue.message}`,
  )
}

/** Hash of everything that matters to the app, ignoring `deckVersion` and `$schema`. */
export function contentHash(deck: Deck): string {
  const content: Partial<Deck> = { ...deck }
  delete content.deckVersion
  delete content.$schema
  return createHash('sha256').update(JSON.stringify(content)).digest('hex')
}

/** Spellings that only print help or the version: no use as flashcards. */
const HELP_OR_VERSION = new Set(['-h', '-?', '-help', '--help', '-V', '-version', '--version'])

/**
 * True for an option whose every spelling only prints help or the version,
 * such as `-h, --help` or `-V, --version`. Options that reuse one of those
 * letters for something else (`grep -h, --no-filename`, `tar -V, --label`)
 * have a spelling outside the set, so they stay.
 */
export function isHelpOrVersion(flags: readonly string[]): boolean {
  return (
    flags.some((flag) => /^--?(help|version)$/.test(flag)) &&
    flags.every((flag) => HELP_OR_VERSION.has(flag))
  )
}

/** Hides help and version options before overrides, so a curator can still unhide one. */
function hideHelpAndVersion(deck: Deck): Deck {
  return {
    ...deck,
    options: deck.options.map((option) =>
      isHelpOrVersion(option.flags) ? { ...option, hidden: true } : option,
    ),
  }
}

export function buildDeck(input: BuildInput, label = 'deck'): BuildResult {
  const generated = DeckSchema.safeParse(input.generated)
  if (!generated.success) {
    throw new DeckValidationError(
      `${label}: the generated deck is invalid:`,
      issues(generated.error),
    )
  }
  const overrides = OverridesSchema.safeParse(input.overrides ?? {})
  if (!overrides.success) {
    throw new DeckValidationError(
      `${label}: the overrides file is invalid:`,
      issues(overrides.error),
    )
  }
  const { deck: merged, stale } = applyOverrides(hideHelpAndVersion(generated.data), overrides.data)
  const candidate: Partial<typeof merged> = { ...merged, deckVersion: 1 }
  delete candidate.$schema
  const result = DeckSchema.safeParse(candidate)
  if (!result.success) {
    throw new DeckValidationError(
      `${label}: the deck with overrides applied is invalid:`,
      issues(result.error),
    )
  }
  const deck = result.data
  const previous = DeckSchema.safeParse(input.previous)
  if (previous.success) {
    const changed = contentHash(previous.data) !== contentHash(deck)
    deck.deckVersion = previous.data.deckVersion + (changed ? 1 : 0)
  }
  return { deck, stale }
}

export { manifestEntry } from '../../pipeline/schema/manifest'
