/**
 * Prints a deck's tier counts and its most-used options, so a curator can
 * sanity-check the generated tiers before writing overrides.
 *
 *   pnpm deck:report rg
 *   pnpm deck:report sed --variant bsd --top 30
 */
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { parseArgs } from 'node:util'
import { DeckSchema, TIERS } from '../src/schema/deck'
import { tldrUsage } from './deck/tldr'
import { loadTldrPages } from './deck/tldr-files'
import { copiedSummaries, coreWithoutExamples } from './deck/review'

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    variant: { type: 'string', default: 'default' },
    top: { type: 'string', default: '20' },
  },
})
const tool = positionals[0]
if (!tool) {
  console.error('Usage: pnpm deck:report <tool> [--variant name] [--top N]')
  process.exit(2)
}
const variant = values.variant!
const built = join('public', 'decks', `${tool}-${variant}.json`)
const generated = join('decks', tool, `${variant}.generated.json`)
const path = existsSync(built) ? built : generated
if (!existsSync(path)) {
  console.error(`No deck at ${built} or ${generated}. Run pnpm deck:generate ${tool} first.`)
  process.exit(1)
}
const deck = DeckSchema.parse(JSON.parse(readFileSync(path, 'utf8')))
const pages = (deck.sourcePages ?? []).map((page) => ({
  name: page.name,
  subcommand: page.name.startsWith(`${tool}-`) ? page.name.slice(tool.length + 1) : undefined,
}))
const { counts } = tldrUsage(deck.options, loadTldrPages(pages, variant))

console.log(`${deck.id} v${deck.deckVersion} (${path}): ${deck.options.length} options`)
for (const tier of TIERS) {
  const options = deck.options.filter((option) => option.tier === tier)
  const hidden = options.filter((option) => option.hidden).length
  console.log(
    `  ${tier.padEnd(8)} ${String(options.length).padStart(4)}${hidden ? `  (${hidden} hidden)` : ''}`,
  )
}

const copied = copiedSummaries(deck)
if (copied.length > 0) {
  console.log(`\nCore summaries still copied from the manpage (${copied.length}):`)
  console.log(`  ${copied.join(', ')}`)
}

const bare = coreWithoutExamples(deck)
if (bare.length > 0) {
  console.log(`\nCore options with no example (${bare.length}):`)
  console.log(`  ${bare.join(', ')}`)
}

const top = Number(values.top)
const ranked = [...deck.options]
  .sort(
    (a, b) =>
      (counts.get(b.id) ?? 0) - (counts.get(a.id) ?? 0) ||
      TIERS.indexOf(a.tier) - TIERS.indexOf(b.tier),
  )
  .slice(0, top)
console.log(`\nTop ${ranked.length} options (tldr examples · tier · flags · summary):`)
for (const option of ranked) {
  const flags = option.flags.join(', ')
  console.log(
    `  ${String(counts.get(option.id) ?? 0).padStart(3)}  ${option.tier.padEnd(7)} ${flags.padEnd(28)} ${option.summary.slice(0, 70)}`,
  )
}
