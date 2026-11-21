import fc from 'fast-check'
import { describe, expect, it } from 'vitest'
import { canonicalFlag, deriveOptionId, isShortFirst, isShortFlag, normalizeFlags } from './flags'

describe('deriveOptionId', () => {
  it.each([
    [['-i', '--ignore-case'], 'ignore-case'],
    [['--ignore-case', '-i'], 'ignore-case'],
    [['-0'], 'short-0'],
    [['-C'], 'short-C'],
    [['-c'], 'short-c'],
    [['-?'], 'short-?'],
    [['--oneline'], 'oneline'],
    [['-name'], 'name'],
    [['-E', '--extended-regexp'], 'extended-regexp'],
    [['-r', '--recursive', '--rec'], 'recursive'],
  ])('%j → %s', (flags, id) => {
    expect(deriveOptionId(flags)).toBe(id)
  })

  it('breaks length ties by code point, not by position', () => {
    expect(deriveOptionId(['--colour', '--colorx'])).toBe('colorx')
    expect(deriveOptionId(['--colorx', '--colour'])).toBe('colorx')
  })

  it('throws for an option with no flags', () => {
    expect(() => canonicalFlag([])).toThrow()
  })

  it('does not depend on flag order (property)', () => {
    const flags = fc.uniqueArray(fc.stringMatching(/^--?[a-z0-9][a-z0-9-]{0,8}$/), {
      minLength: 1,
      maxLength: 5,
    })
    fc.assert(
      fc.property(
        flags.chain((f) =>
          fc.tuple(
            fc.constant(f),
            fc.shuffledSubarray(f, { minLength: f.length, maxLength: f.length }),
          ),
        ),
        ([original, shuffled]) => {
          expect(deriveOptionId(shuffled)).toBe(deriveOptionId(original))
          expect(deriveOptionId(normalizeFlags(shuffled))).toBe(deriveOptionId(original))
        },
      ),
    )
  })
})

describe('short-first ordering', () => {
  it('classifies short and long flags', () => {
    expect(isShortFlag('-i')).toBe(true)
    expect(isShortFlag('-0')).toBe(true)
    expect(isShortFlag('--i')).toBe(false)
    expect(isShortFlag('-name')).toBe(false)
  })

  it('moves short flags first and keeps relative order', () => {
    expect(normalizeFlags(['--ignore-case', '-i', '-y'])).toEqual(['-i', '-y', '--ignore-case'])
    expect(isShortFirst(['-i', '--ignore-case'])).toBe(true)
    expect(isShortFirst(['--ignore-case', '-i'])).toBe(false)
    expect(isShortFirst(['--oneline'])).toBe(true)
  })
})
