import fc from 'fast-check'
import { describe, expect, it } from 'vitest'

import { DeckSchema, primaryFlag, type Option, type ParsingStyle } from '../../schema'
import { deckArbitrary, makeDeck, makeOption } from '../../schema/fixtures'
import { checkAnswer, diffChars, optionsNamedBy } from '.'

const deck = DeckSchema.parse(
  makeDeck([
    makeOption(['-i', '--ignore-case']),
    makeOption(['-w', '--word-regexp']),
    makeOption(['-l', '--files-with-matches']),
    makeOption(['-L', '--files-without-match']),
    makeOption(['-m', '--max-count'], { argument: { name: 'NUM', optional: false } }),
    makeOption(['--color'], { argument: { name: 'WHEN', optional: true } }),
    makeOption(['--colour']),
    makeOption(['-name']),
    makeOption(['--oneline'], { subcommand: 'log' }),
    makeOption(['-i'], { id: 'log.short-i', subcommand: 'log' }),
  ]),
)
const byId = (id: string) => deck.options.find((o) => o.id === id)!

function check(input: string, id: string, style?: ParsingStyle) {
  return checkAnswer(input, { option: byId(id), options: deck.options, style })
}

describe('checkAnswer', () => {
  it.each([
    // [typed, option, style]
    ['-i', 'ignore-case', undefined],
    ['--ignore-case', 'ignore-case', undefined],
    ['  -i  ', 'ignore-case', undefined],
    ['grep -i', 'ignore-case', undefined],
    ['-iw', 'ignore-case', undefined],
    ['-wi', 'ignore-case', undefined],
    ['-iw', 'word-regexp', undefined],
    ['--ignore', 'ignore-case', undefined],
    ['--ign', 'ignore-case', undefined],
    ['--ig', 'ignore-case', undefined],
    ['--files-with-', 'files-with-matches', undefined],
    ['--files-witho', 'files-without-match', undefined],
    ['-m 5', 'max-count', undefined],
    ['-m5', 'max-count', undefined],
    ['--max-count=5', 'max-count', undefined],
    ['--max-count 5', 'max-count', undefined],
    ['--max-count', 'max-count', undefined],
    ['-im5', 'max-count', undefined],
    ['--color', 'color', undefined],
    ['--color=WHEN', 'color', undefined],
    ['--color=always', 'color', undefined],
    ['-name', 'name', undefined],
    ['-iw', 'ignore-case', 'posix'],
    ['--ignore-case', 'ignore-case', 'strict'],
    ['--oneline', 'oneline', undefined],
    ['-i', 'log.short-i', undefined],
  ] as const)('accepts %s for %s (%s)', (typed, id, style) => {
    expect(check(typed, id, style).correct).toBe(true)
  })

  it.each([
    ['', 'ignore-case', undefined],
    ['i', 'ignore-case', undefined],
    ['-w', 'ignore-case', undefined],
    ['--word-regexp', 'ignore-case', undefined],
    ['-i -w', 'ignore-case', undefined],
    ['-I', 'ignore-case', undefined],
    ['-ix', 'ignore-case', undefined],
    ['-mi', 'ignore-case', undefined], // `i` is -m's value
    ['--files', 'files-with-matches', undefined], // ambiguous prefix
    ['--col', 'color', undefined], // --color or --colour
    ['--ignore', 'ignore-case', 'posix'],
    ['-iw', 'ignore-case', 'strict'],
    ['-n', 'name', undefined],
    ['--oneline', 'ignore-case', undefined],
  ] as const)('rejects %j for %s (%s)', (typed, id, style) => {
    expect(check(typed, id, style).correct).toBe(false)
  })

  it('expects the primary flag and suggests it when another spelling was typed', () => {
    expect(check('-i', 'ignore-case')).toEqual({
      correct: true,
      expected: '-i',
      matched: '-i',
    })
    expect(check('--ign', 'ignore-case')).toEqual({
      correct: true,
      expected: '-i',
      matched: '--ignore-case',
      preferred: '-i',
    })
    expect(check('-iw', 'word-regexp')).toMatchObject({ matched: '-w', preferred: '-w' })
    expect(check('-w', 'ignore-case')).toEqual({ correct: false, expected: '-i' })
  })
})

describe('optionsNamedBy', () => {
  it('reads combined short flags in order', () => {
    expect(optionsNamedBy('-wil', deck.options).map((n) => n.flag)).toEqual(['-w', '-i', '-l'])
  })
  it('ignores words that are not flags', () => {
    expect(optionsNamedBy('foo', deck.options)).toEqual([])
    expect(optionsNamedBy('--', deck.options)).toEqual([])
  })
})

describe('diffChars', () => {
  it.each([
    ['-l', '-l', [{ kind: 'same', text: '-l' }]],
    [
      '-k',
      '-l',
      [
        { kind: 'same', text: '-' },
        { kind: 'added', text: 'l' },
        { kind: 'removed', text: 'k' },
      ],
    ],
    [
      '--files',
      '--files-with-matches',
      [
        { kind: 'same', text: '--files' },
        { kind: 'added', text: '-with-matches' },
      ],
    ],
    ['', '-i', [{ kind: 'added', text: '-i' }]],
  ] as const)('diffs %j against %j', (from, to, parts) => {
    expect(diffChars(from, to)).toEqual(parts)
  })

  it('keeps both strings recoverable', () => {
    fc.assert(
      fc.property(fc.string(), fc.string(), (a, b) => {
        const parts = diffChars(a, b)
        const join = (kinds: string[]) =>
          parts
            .filter((p) => kinds.includes(p.kind))
            .map((p) => p.text)
            .join('')
        expect(join(['same', 'removed'])).toBe(a)
        expect(join(['same', 'added'])).toBe(b)
      }),
    )
  })
})

/** Every spelling the tool itself would read as `option`, under GNU rules. */
function validSpellings(option: Option, options: readonly Option[]): string[] {
  const all = options.flatMap((o) => o.flags)
  const others = options.filter((o) => o !== option)
  const spellings = [...option.flags]
  for (const flag of option.flags) {
    if (flag.startsWith('--')) {
      spellings.push(`${flag}=value`, `${flag} value`)
      for (let length = 3; length < flag.length; length++) {
        const prefix = flag.slice(0, length)
        const clash = others.some((o) =>
          o.flags.some((f) => f.startsWith('--') && f.startsWith(prefix)),
        )
        if (!clash && !all.includes(prefix)) spellings.push(prefix)
      }
    }
    if (flag.length === 2) {
      // Combine with another short flag that takes no argument.
      for (const other of others) {
        const short = other.flags.find((f) => f.length === 2)
        if (!short) continue
        for (const combined of [`${short}${flag[1]}`, `-${flag[1]}${short[1]}`]) {
          if (!all.includes(combined)) spellings.push(combined)
        }
      }
    }
  }
  return spellings
}

describe('checkAnswer properties', () => {
  it('accepts every valid spelling and rejects other options’ flags', () => {
    fc.assert(
      fc.property(deckArbitrary, (input) => {
        const { options } = DeckSchema.parse(input)
        for (const option of options) {
          for (const spelling of validSpellings(option, options)) {
            const result = checkAnswer(spelling, { option, options })
            if (!result.correct) throw new Error(`rejected ${spelling} for ${option.id}`)
            expect(result.expected).toBe(primaryFlag(option))
          }
          for (const other of options) {
            if (other === option) continue
            for (const flag of other.flags) {
              if (checkAnswer(flag, { option, options }).correct) {
                throw new Error(`accepted ${flag} (${other.id}) for ${option.id}`)
              }
            }
          }
        }
      }),
      { numRuns: 200 },
    )
  })
})
