import { describe, expect, it } from 'vitest'
import { DeckSchema, type Deck } from '../../schema'
import { makeDeck, makeOption } from '../../schema/fixtures'
import type { DeckManifestEntry } from '../../schema/manifest'
import type { CardState, FsrsState } from '../storage'
import {
  defaultVariant,
  describeChanges,
  diffDecks,
  groupByTool,
  isUpdateAvailable,
  optionStatuses,
  searchOptions,
} from '.'

const entry = (tool: string, variant: string, deckVersion = 1): DeckManifestEntry => ({
  id: `${tool}-${variant}`,
  tool,
  variant,
  toolVersion: '1',
  deckVersion,
  source: 'manpage',
  license: 'MIT',
  file: `${tool}-${variant}.json`,
  bytes: 100,
  optionCount: 1,
  tiers: { core: 1, common: 0, obscure: 0 },
})

const deck = (options: ReturnType<typeof makeOption>[]): Deck => DeckSchema.parse(makeDeck(options))

describe('groupByTool', () => {
  it('groups variants under their tool', () => {
    const groups = groupByTool([entry('sed', 'gnu'), entry('rg', 'default'), entry('sed', 'bsd')])
    expect(groups.map((g) => [g.tool, g.variants.map((v) => v.variant)])).toEqual([
      ['rg', ['default']],
      ['sed', ['bsd', 'gnu']],
    ])
  })
})

describe('defaultVariant', () => {
  const mac = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15'
  const linux = 'Mozilla/5.0 (X11; Linux x86_64) Chrome/131.0'
  it.each([
    [['bsd', 'gnu'], mac, 'bsd'],
    [['bsd', 'gnu'], linux, 'gnu'],
    [['gnu'], mac, 'gnu'],
    [['default'], linux, 'default'],
    [[], linux, undefined],
  ])('%j on %s → %s', (variants, ua, expected) => {
    expect(defaultVariant(variants, ua)).toBe(expected)
  })
})

describe('updates', () => {
  it('detects newer versions', () => {
    expect(isUpdateAvailable({ deckVersion: 1 }, { deckVersion: 2 })).toBe(true)
    expect(isUpdateAvailable({ deckVersion: 2 }, { deckVersion: 2 })).toBe(false)
  })

  it('diffs visible options', () => {
    const before = deck([
      makeOption(['-a']),
      makeOption(['-b']),
      makeOption(['-h'], { hidden: true }),
    ])
    const after = deck([makeOption(['-a']), makeOption(['-c']), makeOption(['-h'])])
    const changes = diffDecks(before, after)
    expect(changes.added.map((o) => o.id)).toEqual(['short-c', 'short-h'])
    expect(changes.removed.map((o) => o.id)).toEqual(['short-b'])
    expect(describeChanges(changes)).toBe('2 options added, 1 removed')
    expect(describeChanges({ added: [], removed: changes.removed })).toBe('1 option removed')
    expect(describeChanges({ added: [], removed: [] })).toBe('No options added or removed')
  })
})

describe('optionStatuses', () => {
  const d = deck([makeOption(['-a']), makeOption(['-b']), makeOption(['-c']), makeOption(['-d'])])
  const fsrs = (phase: FsrsState['phase']): FsrsState => ({
    phase,
    due: 0,
    stability: 1,
    difficulty: 5,
    elapsedDays: 0,
    scheduledDays: 0,
    learningSteps: 0,
    reps: 1,
    lapses: 0,
  })
  const state = (
    optionId: string,
    type: string,
    phase: FsrsState['phase'],
    suspended = false,
  ): CardState => ({
    cardId: `grep:gnu:${optionId}:${type}`,
    deckId: 'grep-gnu',
    optionId,
    fsrs: fsrs(phase),
    suspended,
  })

  it('summarises card states per option', () => {
    const statuses = optionStatuses(d, [
      state('short-b', 'flag-to-meaning', 'review'),
      state('short-c', 'flag-to-meaning', 'review'),
      state('short-c', 'meaning-to-flag', 'learning'),
      state('short-d', 'flag-to-meaning', 'review', true),
      state('short-d', 'meaning-to-flag', 'new', true),
    ])
    expect(Object.fromEntries(statuses)).toEqual({
      'short-a': 'new',
      'short-b': 'review',
      'short-c': 'learning',
      'short-d': 'suspended',
    })
  })
})

describe('searchOptions', () => {
  const options = deck([
    makeOption(['-i', '--ignore-case'], { summary: 'Match case-insensitively' }),
    makeOption(['-v', '--invert-match'], { summary: 'Select lines that do not match' }),
    makeOption(['--color'], { summary: 'Colour output', tags: ['display'] }),
  ]).options

  it('matches flags by prefix first, then text', () => {
    expect(searchOptions(options, '--i').map((o) => o.id)).toEqual(['ignore-case', 'invert-match'])
    expect(searchOptions(options, 'match').map((o) => o.id)).toEqual([
      'ignore-case',
      'invert-match',
    ])
    expect(searchOptions(options, 'DISPLAY').map((o) => o.id)).toEqual(['color'])
    expect(searchOptions(options, '  ')).toHaveLength(3)
  })
})
