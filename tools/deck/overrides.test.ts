import { describe, expect, it } from 'vitest'
import { DeckSchema } from '../../pipeline/schema/deck'
import { makeDeck, makeOption } from '../../pipeline/schema/fixtures'
import { OverridesSchema, type OverridesInput } from '../../pipeline/schema/overrides'
import { applyOverrides } from './overrides'

const generated = DeckSchema.parse(
  makeDeck([
    makeOption(['-i', '--ignore-case'], { examples: [{ command: 'grep -i foo' }] }),
    makeOption(['--color'], { argument: { name: 'WHEN', optional: true } }),
    makeOption(['--colour'], { tags: ['alias'] }),
    makeOption(['-v', '--invert-match']),
  ]),
)

function apply(overrides: OverridesInput) {
  return applyOverrides(generated, OverridesSchema.parse(overrides))
}
const find = (result: ReturnType<typeof apply>, id: string) =>
  result.deck.options.find((option) => option.id === id)

describe('applyOverrides', () => {
  it('replaces summary, description, tier and primary', () => {
    const result = apply({
      options: {
        'ignore-case': {
          summary: 'Match case-insensitively',
          description: 'Longer text.',
          tier: 'core',
          primary: '--ignore-case',
        },
      },
    })
    expect(find(result, 'ignore-case')).toMatchObject({
      summary: 'Match case-insensitively',
      description: 'Longer text.',
      tier: 'core',
      primary: '--ignore-case',
    })
    expect(result.stale).toEqual([])
  })

  it('adds examples and tags instead of replacing them', () => {
    const result = apply({
      options: {
        'ignore-case': { examples: [{ command: 'grep -i bar' }], tags: ['search', 'search'] },
      },
    })
    expect(find(result, 'ignore-case')).toMatchObject({
      examples: [{ command: 'grep -i foo' }, { command: 'grep -i bar' }],
      tags: ['search'],
    })
  })

  it('replaces the generated examples with replaceExamples', () => {
    const result = apply({
      options: {
        'ignore-case': { replaceExamples: true, examples: [{ command: 'grep -i bar' }] },
      },
    })
    expect(find(result, 'ignore-case')?.examples).toEqual([{ command: 'grep -i bar' }])
  })

  it('hides options and can drop an argument', () => {
    const result = apply({ options: { color: { hidden: true, argument: null } } })
    expect(find(result, 'color')?.hidden).toBe(true)
    expect(find(result, 'color')?.argument).toBeUndefined()
  })

  it('merges options', () => {
    const result = apply({
      merge: [{ into: 'color', from: ['colour'] }],
      options: { color: { summary: 'Colour output' } },
    })
    expect(find(result, 'colour')).toBeUndefined()
    expect(find(result, 'color')).toMatchObject({
      flags: ['--color', '--colour'],
      tags: ['alias'],
      summary: 'Colour output',
      argument: { name: 'WHEN', optional: true },
    })
  })

  it('adds options the parser missed', () => {
    const result = apply({
      add: [{ flags: ['--null', '-0'], summary: 'NUL after file names' }],
    })
    expect(find(result, 'null')).toMatchObject({ flags: ['-0', '--null'], tier: 'common' })
    expect(DeckSchema.safeParse(result.deck).success).toBe(true)
  })

  it('applies deck-level fields', () => {
    expect(apply({ deck: { license: 'MIT' } }).deck.license).toBe('MIT')
  })

  it('reports stale overrides', () => {
    const result = apply({
      options: { gone: { tier: 'core' } },
      merge: [
        { into: 'missing', from: ['color'] },
        { into: 'color', from: ['nope'] },
      ],
    })
    expect(result.stale).toEqual([
      'merge[0].into: no option "missing"',
      'merge[1].from: no option "nope"',
      'options.gone: no option "gone"',
    ])
  })

  it('does not modify the generated deck', () => {
    apply({ options: { 'ignore-case': { tags: ['x'], tier: 'core' } } })
    expect(generated.options[0]).toMatchObject({ tags: [], tier: 'common' })
  })

  it('rejects unknown fields', () => {
    expect(OverridesSchema.safeParse({ options: { x: { summry: 'typo' } } }).success).toBe(false)
  })
})
