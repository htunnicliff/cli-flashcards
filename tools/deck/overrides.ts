/**
 * Applies a curator's overrides to a generated deck. Order: merges, then
 * per-option patches (so a patch can target a merged option), then additions.
 */
import type { Deck, OptionInput } from '../../src/schema/deck'
import { deriveOptionId, normalizeFlags } from '../../src/schema/flags'
import type { Overrides } from '../../src/schema/overrides'

export interface ApplyResult {
  /** Not yet validated; run it through `DeckSchema`. */
  deck: Omit<Deck, 'options'> & { options: OptionInput[] }
  /** Overrides that name option IDs the generated deck no longer has. */
  stale: string[]
}

function unique<T>(items: T[]): T[] {
  return [...new Set(items)]
}

export function applyOverrides(generated: Deck, overrides: Overrides): ApplyResult {
  const stale: string[] = []
  let options: OptionInput[] = generated.options.map((option) => ({
    ...option,
    flags: [...option.flags],
    examples: [...option.examples],
    tags: [...option.tags],
  }))
  const byId = () => new Map(options.map((option) => [option.id, option]))

  for (const [index, merge] of overrides.merge.entries()) {
    const ids = byId()
    const into = ids.get(merge.into)
    if (!into) {
      stale.push(`merge[${index}].into: no option "${merge.into}"`)
      continue
    }
    const removed = new Set<string>()
    for (const id of merge.from) {
      const from = ids.get(id)
      if (!from) {
        stale.push(`merge[${index}].from: no option "${id}"`)
        continue
      }
      into.flags = normalizeFlags(unique([...into.flags, ...from.flags]))
      into.examples = [...(into.examples ?? []), ...(from.examples ?? [])]
      into.tags = unique([...(into.tags ?? []), ...(from.tags ?? [])])
      into.argument ??= from.argument
      removed.add(id)
    }
    options = options.filter((option) => !removed.has(option.id))
  }

  const ids = byId()
  for (const [id, patch] of Object.entries(overrides.options)) {
    const option = ids.get(id)
    if (!option) {
      stale.push(`options.${id}: no option "${id}"`)
      continue
    }
    if (patch.summary !== undefined) option.summary = patch.summary
    if (patch.description !== undefined) option.description = patch.description
    if (patch.tier !== undefined) option.tier = patch.tier
    if (patch.primary !== undefined) option.primary = patch.primary
    if (patch.hidden !== undefined) option.hidden = patch.hidden
    if (patch.argument === null) delete option.argument
    else if (patch.argument !== undefined) option.argument = patch.argument
    if (patch.examples) option.examples = [...(option.examples ?? []), ...patch.examples]
    if (patch.tags) option.tags = unique([...(option.tags ?? []), ...patch.tags])
  }

  for (const added of overrides.add) {
    const flags = normalizeFlags(added.flags)
    const baseId = deriveOptionId(flags)
    options.push({
      ...added,
      flags,
      id: added.id ?? (added.subcommand ? `${added.subcommand}.${baseId}` : baseId),
    })
  }

  return {
    deck: {
      ...generated,
      ...(overrides.deck ?? {}),
      options,
    },
    stale,
  }
}
