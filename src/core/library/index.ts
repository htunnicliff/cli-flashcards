/**
 * Deck library logic: grouping the manifest, picking a default variant,
 * diffing deck versions and summarising learning status. Framework-free.
 */
import type { DeckManifestEntry } from '../../schema/manifest'
import { deriveCards, type Deck, type Option } from '../../schema'
import type { CardState } from '../storage'

export interface ToolDecks {
  tool: string
  /** Every variant of the tool in the manifest, sorted by name. */
  variants: DeckManifestEntry[]
}

/** Groups manifest entries by tool, tools in alphabetical order. */
export function groupByTool(entries: readonly DeckManifestEntry[]): ToolDecks[] {
  const groups = new Map<string, DeckManifestEntry[]>()
  for (const entry of entries) {
    groups.set(entry.tool, [...(groups.get(entry.tool) ?? []), entry])
  }
  return [...groups.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([tool, variants]) => ({
      tool,
      variants: [...variants].sort((a, b) => a.variant.localeCompare(b.variant)),
    }))
}

/** True for macOS and iOS user agents, whose command-line tools are BSD flavoured. */
export function isApplePlatform(userAgent: string): boolean {
  return /Mac OS X|Macintosh|iPhone|iPad|Darwin/i.test(userAgent)
}

/**
 * The variant to preselect: BSD on macOS, GNU elsewhere, falling back to the
 * first variant the tool has.
 */
export function defaultVariant(variants: readonly string[], userAgent: string): string | undefined {
  const preferred = isApplePlatform(userAgent) ? ['bsd', 'macos'] : ['gnu', 'linux']
  return preferred.find((name) => variants.includes(name)) ?? variants[0]
}

export function isUpdateAvailable(
  installed: { deckVersion: number },
  entry: Pick<DeckManifestEntry, 'deckVersion'>,
): boolean {
  return entry.deckVersion > installed.deckVersion
}

export interface DeckChanges {
  added: Option[]
  removed: Option[]
}

/** Visible options added and removed between two versions of a deck, by option ID. */
export function diffDecks(before: Deck, after: Deck): DeckChanges {
  const visible = (deck: Deck) =>
    new Map(deck.options.filter((o) => !o.hidden).map((o) => [o.id, o]))
  const old = visible(before)
  const next = visible(after)
  return {
    added: [...next.values()].filter((option) => !old.has(option.id)),
    removed: [...old.values()].filter((option) => !next.has(option.id)),
  }
}

/** One-line description of a deck update, e.g. "2 options added, 1 removed". */
export function describeChanges(changes: DeckChanges): string {
  const parts: string[] = []
  if (changes.added.length) {
    parts.push(`${changes.added.length} option${changes.added.length === 1 ? '' : 's'} added`)
  }
  if (changes.removed.length) {
    parts.push(
      changes.added.length
        ? `${changes.removed.length} removed`
        : `${changes.removed.length} option${changes.removed.length === 1 ? '' : 's'} removed`,
    )
  }
  return parts.length ? parts.join(', ') : 'No options added or removed'
}

export type OptionStatus = 'new' | 'learning' | 'review' | 'suspended'

/**
 * Learning status per option, from its cards' states: `suspended` when every
 * card is suspended, `learning` when any card is in a learning step, `review`
 * when any card has graduated, otherwise `new`.
 */
export function optionStatuses(
  deck: Deck,
  states: readonly CardState[],
): Map<string, OptionStatus> {
  const byCard = new Map(states.map((state) => [state.cardId, state]))
  const cardsByOption = new Map<string, string[]>()
  for (const card of deriveCards(deck)) {
    cardsByOption.set(card.optionId, [...(cardsByOption.get(card.optionId) ?? []), card.id])
  }
  const result = new Map<string, OptionStatus>()
  for (const option of deck.options) {
    const cardStates = (cardsByOption.get(option.id) ?? [])
      .map((id) => byCard.get(id))
      .filter((state): state is CardState => state !== undefined)
    const cards = cardsByOption.get(option.id) ?? []
    let status: OptionStatus = 'new'
    if (
      cards.length > 0 &&
      cardStates.length === cards.length &&
      cardStates.every((s) => s.suspended)
    ) {
      status = 'suspended'
    } else if (
      cardStates.some((s) => s.fsrs.phase === 'learning' || s.fsrs.phase === 'relearning')
    ) {
      status = 'learning'
    } else if (cardStates.some((s) => s.fsrs.phase === 'review')) {
      status = 'review'
    }
    result.set(option.id, status)
  }
  return result
}

/**
 * Filters options by a search query: flags match by prefix (`--ign` finds
 * `--ignore-case`), everything else by substring in the summary, argument and
 * tags. Flag matches sort first. An empty query returns every option.
 */
export function searchOptions(options: readonly Option[], query: string): Option[] {
  const q = query.trim().toLowerCase()
  if (!q) return [...options]
  const flagHits: Option[] = []
  const textHits: Option[] = []
  for (const option of options) {
    if (option.flags.some((flag) => flag.toLowerCase().startsWith(q))) {
      flagHits.push(option)
      continue
    }
    const haystack = [
      option.summary,
      option.argument?.name ?? '',
      option.subcommand ?? '',
      ...option.tags,
      ...option.flags,
    ]
      .join(' ')
      .toLowerCase()
    if (haystack.includes(q)) textHits.push(option)
  }
  return [...flagHits, ...textHits]
}
