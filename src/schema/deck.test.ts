import { describe, expect, it } from 'vitest'
import { DeckSchema, OptionSchema } from './deck'
import { makeDeck, makeOption } from './fixtures'

describe('OptionSchema', () => {
  it('fills defaults', () => {
    const option = OptionSchema.parse(makeOption(['-i', '--ignore-case']))
    expect(option).toMatchObject({ description: '', examples: [], tags: [], hidden: false })
  })

  it('accepts an argument', () => {
    const option = OptionSchema.parse(
      makeOption(['--color'], { argument: { name: 'WHEN', optional: true } }),
    )
    expect(option.argument).toEqual({ name: 'WHEN', optional: true })
    expect(
      OptionSchema.parse(makeOption(['-e'], { argument: { name: 'PATTERN' } })).argument,
    ).toEqual({ name: 'PATTERN', optional: false })
  })

  it('rejects long flags listed before short flags', () => {
    const result = OptionSchema.safeParse(makeOption(['--ignore-case', '-i']))
    expect(result.success).toBe(false)
    expect(result.error?.issues[0]?.message).toMatch(/short flags before long/)
  })

  it('rejects a primary flag that is not one of the flags', () => {
    expect(OptionSchema.safeParse(makeOption(['-i'], { primary: '--ignore-case' })).success).toBe(
      false,
    )
    expect(
      OptionSchema.safeParse(makeOption(['-i', '--ignore-case'], { primary: '--ignore-case' }))
        .success,
    ).toBe(true)
  })

  it.each(['i', '---x', '--', '-', '--a b', '--color=WHEN', '-a:b'])(
    'rejects malformed flag %j',
    (flag) => {
      expect(OptionSchema.safeParse(makeOption(['-x'], { flags: [flag] })).success).toBe(false)
    },
  )

  it('rejects duplicate flags and IDs containing ":"', () => {
    expect(OptionSchema.safeParse(makeOption(['-i', '-i'])).success).toBe(false)
    expect(OptionSchema.safeParse(makeOption(['-i'], { id: 'a:b' })).success).toBe(false)
  })
})

describe('DeckSchema', () => {
  it('parses a valid deck', () => {
    const deck = DeckSchema.parse(makeDeck([makeOption(['-i', '--ignore-case'])]))
    expect(deck.options).toHaveLength(1)
  })

  it('requires the current schema version', () => {
    expect(DeckSchema.safeParse(makeDeck([], { schemaVersion: 2 as 1 })).success).toBe(false)
  })

  it('rejects duplicate option IDs', () => {
    const result = DeckSchema.safeParse(makeDeck([makeOption(['--name']), makeOption(['-name'])]))
    expect(result.success).toBe(false)
    expect(result.error?.issues[0]?.message).toMatch(/Duplicate option ID "name"/)
  })

  it('rejects a flag shared by two options', () => {
    const result = DeckSchema.safeParse(
      makeDeck([
        makeOption(['-i', '--ignore-case']),
        makeOption(['-i', '--invert'], { id: 'invert' }),
      ]),
    )
    expect(result.success).toBe(false)
    expect(result.error?.issues[0]?.message).toMatch(/"-i" also belongs to options\[0\]/)
  })

  it('allows the same flag in different subcommands', () => {
    const deck = makeDeck([
      makeOption(['-n', '--max-count'], { id: 'log.max-count', subcommand: 'log' }),
      makeOption(['-n', '--no-verify'], { id: 'commit.no-verify', subcommand: 'commit' }),
    ])
    expect(DeckSchema.safeParse(deck).success).toBe(true)
  })

  it('records source pages', () => {
    const deck = DeckSchema.parse(
      makeDeck([], { sourcePages: [{ name: 'grep', section: '1', path: 'grep.1' }] }),
    )
    expect(deck.sourcePages).toEqual([{ name: 'grep', section: '1', path: 'grep.1' }])
  })

  it('rejects slugs with capitals or spaces', () => {
    expect(DeckSchema.safeParse(makeDeck([], { tool: 'Grep' })).success).toBe(false)
    expect(DeckSchema.safeParse(makeDeck([], { variant: 'g nu' })).success).toBe(false)
  })
})
