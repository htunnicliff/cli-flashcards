import { describe, expect, it } from 'vitest'
import { makeDeck, makeOption } from '../../src/schema/fixtures'
import { buildDeck, contentHash, manifestEntry } from './build'
import { DeckValidationError } from './generate'

const generated = makeDeck([
  makeOption(['-i', '--ignore-case'], { tier: 'core' }),
  makeOption(['-v', '--invert-match']),
  makeOption(['--obscure'], { tier: 'obscure', hidden: true }),
])

describe('buildDeck', () => {
  it('starts at deckVersion 1', () => {
    expect(buildDeck({ generated }).deck.deckVersion).toBe(1)
  })

  it('keeps the version when nothing changed and bumps it when content changed', () => {
    const first = buildDeck({ generated }).deck
    const previous = { ...first, deckVersion: 4 }
    expect(buildDeck({ generated, previous }).deck.deckVersion).toBe(4)
    const changed = buildDeck({
      generated,
      previous,
      overrides: { options: { 'invert-match': { summary: 'Select non-matching lines' } } },
    }).deck
    expect(changed.deckVersion).toBe(5)
  })

  it('ignores $schema and deckVersion when hashing', () => {
    const deck = buildDeck({ generated }).deck
    expect(contentHash({ ...deck, deckVersion: 9, $schema: 'x' })).toBe(contentHash(deck))
  })

  it('fails on duplicate flag spellings in the built deck', () => {
    expect(() =>
      buildDeck({ generated, overrides: { add: [{ flags: ['-i'], summary: 'Clash' }] } }),
    ).toThrow(/Flag "-i" also belongs to options\[0\]/)
  })

  it('reports readable errors for bad overrides', () => {
    try {
      buildDeck(
        { generated, overrides: { options: { 'ignore-case': { tier: 'top' } } } },
        'grep/gnu',
      )
      expect.unreachable()
    } catch (error) {
      expect(error).toBeInstanceOf(DeckValidationError)
      expect((error as Error).message).toMatch(/grep\/gnu: the overrides file is invalid/)
      expect((error as Error).message).toMatch(/options\.ignore-case\.tier/)
    }
  })

  it('reports stale overrides without failing', () => {
    const { stale } = buildDeck({ generated, overrides: { options: { gone: { hidden: true } } } })
    expect(stale).toEqual(['options.gone: no option "gone"'])
  })
})

describe('manifestEntry', () => {
  it('counts visible options per tier', () => {
    const { deck } = buildDeck({ generated })
    expect(manifestEntry(deck, 'grep-gnu.json', 123)).toEqual({
      id: 'grep-gnu',
      tool: 'grep',
      variant: 'gnu',
      toolVersion: '3.11',
      deckVersion: 1,
      source: 'manpage',
      license: 'GPL-3.0-or-later',
      file: 'grep-gnu.json',
      bytes: 123,
      optionCount: 2,
      tiers: { core: 1, common: 1, obscure: 0 },
    })
  })
})
