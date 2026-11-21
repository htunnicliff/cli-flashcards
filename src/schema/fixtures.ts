import fc from 'fast-check'
import { type DeckInput, type OptionInput, SCHEMA_VERSION } from './deck'
import { deriveOptionId, normalizeFlags } from './flags'

export function makeDeck(options: OptionInput[], overrides: Partial<DeckInput> = {}): DeckInput {
  return {
    schemaVersion: SCHEMA_VERSION,
    id: 'grep-gnu',
    tool: 'grep',
    variant: 'gnu',
    toolVersion: '3.11',
    deckVersion: 1,
    source: 'manpage',
    license: 'GPL-3.0-or-later',
    attribution: 'GNU grep manual, Free Software Foundation',
    options,
    ...overrides,
  }
}

export function makeOption(flags: string[], overrides: Partial<OptionInput> = {}): OptionInput {
  return {
    id: deriveOptionId(flags),
    flags,
    summary: `Summary for ${flags.join(', ')}`,
    tier: 'common',
    ...overrides,
  }
}

const shortFlag = fc
  .constantFrom(...'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789?#'.split(''))
  .map((c) => `-${c}`)
const longName = fc.stringMatching(/^[a-z][a-z0-9-]{0,14}$/)
const longFlag = fc.oneof(
  { arbitrary: longName.map((n) => `--${n}`), weight: 4 },
  { arbitrary: longName.filter((n) => n.length > 1).map((n) => `-${n}`), weight: 1 },
)
const flagSet = fc
  .uniqueArray(fc.oneof(shortFlag, longFlag), { minLength: 1, maxLength: 4 })
  .map(normalizeFlags)

/** A valid deck: unique flags across options and unique derived option IDs. */
export const deckArbitrary = fc
  .uniqueArray(flagSet, {
    maxLength: 25,
    selector: (flags) => deriveOptionId(flags),
  })
  .filter((sets) => new Set(sets.flat()).size === sets.flat().length)
  .chain((sets) =>
    fc.tuple(
      ...sets.map((flags) =>
        fc
          .record({
            hidden: fc.boolean(),
            withExample: fc.boolean(),
            exampleFlag: fc.constantFrom(...flags),
          })
          .map(({ hidden, withExample, exampleFlag }) =>
            makeOption(flags, {
              hidden,
              examples: withExample ? [{ command: `grep ${exampleFlag} foo file.txt` }] : [],
            }),
          ),
      ),
    ),
  )
  .map((options) => makeDeck(options))
