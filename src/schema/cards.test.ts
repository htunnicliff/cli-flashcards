import fc from 'fast-check'
import { describe, expect, it } from 'vitest'
import { type Card, answerFlags, cardId, deriveCards, primaryFlag } from './cards'
import { type Deck, DeckSchema, type OptionInput } from './deck'
import { deriveOptionId } from './flags'
import { deckArbitrary, makeDeck, makeOption } from './fixtures'

const parse = (...options: OptionInput[]): Deck => DeckSchema.parse(makeDeck(options))
const ids = (cards: Card[]) => cards.map((card) => card.id)

describe('primaryFlag', () => {
  it('returns the first short flag', () => {
    expect(primaryFlag({ flags: ['-i', '-y', '--ignore-case'] })).toBe('-i')
  })

  it('falls back to the long flag when there is no short form', () => {
    expect(primaryFlag({ flags: ['--oneline'] })).toBe('--oneline')
  })

  it('honours a primary override', () => {
    const option = { flags: ['-y', '--ignore-case'], primary: '--ignore-case' }
    expect(primaryFlag(option)).toBe('--ignore-case')
    expect(answerFlags(option)).toEqual(['--ignore-case', '-y'])
  })
})

describe('deriveCards', () => {
  it('builds IDs as tool:variant:optionId:cardType', () => {
    const deck = parse(
      makeOption(['-i', '--ignore-case'], { examples: [{ command: 'grep -i foo' }] }),
    )
    expect(ids(deriveCards(deck))).toEqual([
      'grep:gnu:ignore-case:flag-to-meaning',
      'grep:gnu:ignore-case:meaning-to-flag',
      'grep:gnu:ignore-case:cloze',
    ])
    expect(cardId(deck, 'short-0', 'cloze')).toBe('grep:gnu:short-0:cloze')
  })

  it('skips cloze when there is no example', () => {
    expect(ids(deriveCards(parse(makeOption(['-0']))))).toEqual([
      'grep:gnu:short-0:flag-to-meaning',
      'grep:gnu:short-0:meaning-to-flag',
    ])
  })

  it('skips cloze when no example contains the flag', () => {
    const deck = parse(makeOption(['-i'], { examples: [{ command: 'grep -rn foo' }] }))
    expect(deriveCards(deck).map((card) => card.type)).not.toContain('cloze')
  })

  it('skips hidden options', () => {
    expect(deriveCards(parse(makeOption(['-i'], { hidden: true })))).toEqual([])
  })

  it('leads with the primary flag and accepts every spelling', () => {
    const [card] = deriveCards(
      parse(makeOption(['-i', '--ignore-case'], { description: 'Long text' })),
    )
    expect(card).toMatchObject({
      flag: '-i',
      answers: ['-i', '--ignore-case'],
      detail: 'Long text',
      deckId: 'grep-gnu',
      optionId: 'ignore-case',
    })
  })

  it('blanks the flag in the example, keeping an attached value', () => {
    const deck = parse(
      makeOption(['--color'], {
        argument: { name: 'WHEN', optional: true },
        examples: [{ command: 'grep --color=always -n foo  log.txt', description: 'Force colour' }],
      }),
    )
    const cloze = deriveCards(deck).find((card) => card.type === 'cloze')
    expect(cloze).toMatchObject({
      cloze: 'grep ____=always -n foo  log.txt',
      command: 'grep --color=always -n foo  log.txt',
      blanked: '--color',
      exampleDescription: 'Force colour',
    })
  })

  it('prefers an example using the primary flag', () => {
    const deck = parse(
      makeOption(['-i', '--ignore-case'], {
        examples: [{ command: 'grep --ignore-case foo' }, { command: 'grep -i foo' }],
      }),
    )
    const cloze = deriveCards(deck).find((card) => card.type === 'cloze')
    expect(cloze).toMatchObject({ cloze: 'grep ____ foo', blanked: '-i' })
  })

  it('does not blank a flag that is a prefix of another token', () => {
    const deck = parse(
      makeOption(['--color'], { examples: [{ command: 'ls --colorize --color' }] }),
    )
    const cloze = deriveCards(deck).find((card) => card.type === 'cloze')
    expect(cloze).toMatchObject({ cloze: 'ls --colorize ____' })
  })
})

describe('ID stability (properties)', () => {
  const shuffledDeck = deckArbitrary.chain((input) =>
    fc.tuple(
      fc.constant(input),
      fc
        .shuffledSubarray(input.options, {
          minLength: input.options.length,
          maxLength: input.options.length,
        })
        .map((options) => ({ ...input, options })),
    ),
  )

  it('shuffling options never changes any option or card ID', () => {
    fc.assert(
      fc.property(shuffledDeck, ([original, shuffled]) => {
        const optionIds = (deck: typeof original) =>
          deck.options.map((option) => deriveOptionId(option.flags)).sort()
        expect(optionIds(shuffled)).toEqual(optionIds(original))

        const a = deriveCards(DeckSchema.parse(original))
        const b = deriveCards(DeckSchema.parse(shuffled))
        expect(ids(b).sort()).toEqual(ids(a).sort())
        // Each card keeps its content too, not only its ID.
        const byId = new Map(a.map((card) => [card.id, card]))
        for (const card of b) expect(card).toEqual(byId.get(card.id))
      }),
    )
  })

  it('deriveCards is deterministic and never produces duplicate IDs', () => {
    fc.assert(
      fc.property(deckArbitrary, (input) => {
        const deck = DeckSchema.parse(input)
        const cards = deriveCards(deck)
        expect(deriveCards(DeckSchema.parse(structuredClone(input)))).toEqual(cards)
        expect(new Set(ids(cards)).size).toBe(cards.length)
        for (const card of cards) {
          expect(card.id).toBe(cardId(deck, card.optionId, card.type))
          expect(card.id.split(':')).toHaveLength(4)
        }
      }),
    )
  })
})
