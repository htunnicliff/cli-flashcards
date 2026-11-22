/**
 * Writes fixtures the Swift (`apple/FlashcardsCore`) tests check their ports
 * against, so the app behaves exactly like the deck pipeline:
 *
 * - `fsrs_golden.json`: review sequences graded by ts-fsrs.
 * - `cards_golden.json`: cards derived from every built deck.
 * - `answers_golden.json`: typed answers and their verdicts.
 *
 * They live in `apple/FlashcardsCore/Tests/Fixtures/`.
 *
 * Run with `pnpm fixtures:golden` after changing scheduling, card or answer logic.
 */
import { readdirSync, readFileSync, writeFileSync } from 'node:fs'

import { checkAnswer } from '../pipeline/core/answers'
import { deriveCards, DeckSchema, type Deck } from '../pipeline/schema'

import { nextState, retrievability } from '../pipeline/core/fsrs'
import type { FsrsState, Rating } from '../pipeline/core/types'

// Small deterministic PRNG (mulberry32), so the fixture is stable.
function rng(seed: number) {
  return () => {
    seed |= 0
    seed = (seed + 0x6d2b79f5) | 0
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return (t >>> 0) / 4294967296
  }
}

const random = rng(20261121)
const MINUTE = 60_000
const sequences = []
for (let s = 0; s < 150; s++) {
  const desiredRetention = [0.7, 0.8, 0.85, 0.9, 0.95, 0.99][s % 6]!
  let now = Date.UTC(2026, 0, 1) + Math.floor(random() * 365 * 24 * 60) * MINUTE
  let state: FsrsState | null = null
  const steps = []
  const length = 2 + Math.floor(random() * 18)
  for (let i = 0; i < length; i++) {
    // Mostly on time, sometimes early or late, sometimes within the same minute.
    if (state) {
      const wait = Math.max(0, state.due - now)
      const factor = [0, 0.5, 1, 1, 1, 1.5, 3][Math.floor(random() * 7)]!
      now += Math.round(wait * factor) + Math.floor(random() * 120) * MINUTE
    }
    const roll = random()
    const rating = (roll < 0.15 ? 1 : roll < 0.3 ? 2 : roll < 0.9 ? 3 : 4) as Rating
    state = nextState(state, rating, now, { desiredRetention })
    const later = now + Math.floor(random() * 60 * 24 * 60) * MINUTE
    steps.push({
      now,
      rating,
      after: state,
      retrievabilityAt: later,
      retrievability: retrievability(state, later, { desiredRetention }),
    })
  }
  sequences.push({ desiredRetention, steps })
}

const fixture = (name: string) =>
  new URL(`../apple/FlashcardsCore/Tests/Fixtures/${name}`, import.meta.url)
const write = (name: string, data: object) =>
  writeFileSync(
    fixture(name),
    JSON.stringify({ generatedBy: 'tools/fixtures-golden.ts', ...data }) + '\n',
  )

write('fsrs_golden.json', { sequences })

const deckDir = new URL('../public/data/decks/', import.meta.url)
const decks: Deck[] = readdirSync(deckDir)
  .filter((file) => file.endsWith('.json') && file !== 'index.json')
  .sort()
  .map((file) => DeckSchema.parse(JSON.parse(readFileSync(new URL(file, deckDir), 'utf8'))))

const cards = Object.fromEntries(
  decks.map((deck) => [
    deck.id,
    deriveCards(deck, { flagPairs: true }).map((card) => ({
      id: card.id,
      flag: card.flag,
      answers: card.answers,
      ...('cloze' in card ? { cloze: card.cloze, blanked: card.blanked } : {}),
      ...('shown' in card ? { shown: card.shown, targets: card.targets } : {}),
    })),
  ]),
)
write('cards_golden.json', { cards })

// Answers: for sampled options, try spellings that should and shouldn't count.
const answers = []
for (const deck of decks) {
  const visible = deck.options.filter((o) => !o.hidden)
  for (let i = 0; i < 25 && visible.length; i++) {
    const option = visible[Math.floor(random() * visible.length)]!
    const other = visible[Math.floor(random() * visible.length)]!
    const flag = option.flags[Math.floor(random() * option.flags.length)]!
    const inputs = [
      flag,
      `${deck.tool} ${flag} value`,
      `${flag}=x`,
      flag.startsWith('--')
        ? flag.slice(0, Math.max(3, flag.length - 2))
        : `${flag}${other.flags[0]!.slice(1)}`,
      `${flag} ${other.flags[0]}`,
      other.flags[0]!,
      flag.toUpperCase(),
      '',
    ]
    for (const input of inputs) {
      const result = checkAnswer(input, {
        option,
        options: deck.options,
        style: deck.parsingStyle,
      })
      answers.push({ deck: deck.id, option: option.id, input, ...result })
    }
  }
}
write('answers_golden.json', { answers })
console.log(
  `Wrote ${sequences.length} FSRS sequences, ${decks.length} decks of cards, ${answers.length} answers`,
)
