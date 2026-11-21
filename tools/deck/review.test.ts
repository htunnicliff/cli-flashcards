import { describe, expect, it } from 'vitest'
import { DeckSchema, type DeckInput } from '../../src/schema/deck'
import {
  attributionsMarkdown,
  copiedSummaries,
  coreWithoutExamples,
  isCopiedSummary,
} from './review'

const description =
  'Ignore case distinctions in patterns and input data, so that characters that differ only in case match each other.'

describe('isCopiedSummary', () => {
  it('flags a summary that is the opening of the description', () => {
    expect(isCopiedSummary({ summary: 'Ignore case distinctions in patterns', description })).toBe(
      true,
    )
  })

  it('flags a lightly reworded first sentence', () => {
    expect(
      isCopiedSummary({
        summary: 'Ignore case distinctions in input data and patterns',
        description,
      }),
    ).toBe(true)
  })

  it('accepts a summary in our own words', () => {
    expect(
      isCopiedSummary({ summary: 'Match regardless of upper or lower case', description }),
    ).toBe(false)
  })

  it('ignores very short summaries and missing descriptions', () => {
    expect(isCopiedSummary({ summary: 'Ignore case', description })).toBe(false)
    expect(
      isCopiedSummary({ summary: 'Ignore case distinctions in patterns', description: '' }),
    ).toBe(false)
  })
})

const deck: DeckInput = {
  schemaVersion: 1,
  id: 'grep-gnu',
  tool: 'grep',
  variant: 'gnu',
  toolVersion: '3.11',
  deckVersion: 1,
  source: 'manpage',
  license: 'GPL-3.0-or-later',
  attribution: 'GNU grep manual page.',
  sourcePages: [{ name: 'grep', section: '1' }],
  options: [
    {
      id: 'ignore-case',
      flags: ['-i', '--ignore-case'],
      summary: 'Ignore case distinctions in patterns and input data',
      description,
      tier: 'core',
    },
    {
      id: 'count',
      flags: ['-c', '--count'],
      summary: 'Suppress normal output; instead print a count of matching lines',
      description:
        'Suppress normal output; instead print a count of matching lines for each input file.',
      tier: 'common',
    },
  ],
}

describe('copiedSummaries', () => {
  it('reports only core options', () => {
    expect(copiedSummaries(DeckSchema.parse(deck))).toEqual(['ignore-case'])
  })
})

describe('coreWithoutExamples', () => {
  it('reports core options that have no example', () => {
    expect(coreWithoutExamples(DeckSchema.parse(deck))).toEqual(['ignore-case'])
  })

  it('does not count combined short flags', () => {
    const combined = structuredClone(deck)
    combined.options[0]!.examples = [{ command: 'grep -ri foo .' }]
    expect(coreWithoutExamples(DeckSchema.parse(combined))).toEqual(['ignore-case'])
    combined.options[0]!.examples = [{ command: 'grep -r -i foo .' }]
    expect(coreWithoutExamples(DeckSchema.parse(combined))).toEqual([])
  })
})

describe('attributionsMarkdown', () => {
  it('lists each deck with its license and attribution', () => {
    const markdown = attributionsMarkdown([DeckSchema.parse(deck)])
    expect(markdown).toContain('## grep (gnu)')
    expect(markdown).toContain('- Source pages: grep(1)')
    expect(markdown).toContain('- License: GPL-3.0-or-later')
    expect(markdown).toContain('- Attribution: GNU grep manual page.')
  })
})
