import fc from 'fast-check'
import { describe, expect, it } from 'vitest'

import { contrastRatio, parseHex, relativeLuminance } from './contrast'

const hex = fc
  .tuple(fc.nat(255), fc.nat(255), fc.nat(255))
  .map((rgb) => '#' + rgb.map((c) => c.toString(16).padStart(2, '0')).join(''))

describe('contrast', () => {
  it('parses #rrggbb', () => {
    expect(parseHex('#2B54C9')).toEqual([0x2b, 0x54, 0xc9])
    expect(() => parseHex('#fff')).toThrow()
    expect(() => parseHex('blue')).toThrow()
  })

  it('matches the WCAG reference values', () => {
    expect(relativeLuminance('#000000')).toBe(0)
    expect(relativeLuminance('#FFFFFF')).toBe(1)
    expect(contrastRatio('#000000', '#FFFFFF')).toBe(21)
    expect(contrastRatio('#777777', '#FFFFFF')).toBeCloseTo(4.48, 2)
  })

  it('is symmetric and between 1 and 21', () => {
    fc.assert(
      fc.property(hex, hex, (a, b) => {
        const ratio = contrastRatio(a, b)
        expect(ratio).toBeCloseTo(contrastRatio(b, a), 10)
        expect(ratio).toBeGreaterThanOrEqual(1)
        expect(ratio).toBeLessThanOrEqual(21)
      }),
    )
  })

  it('is 1 for a colour against itself', () => {
    fc.assert(
      fc.property(hex, (a) => {
        expect(contrastRatio(a, a)).toBe(1)
      }),
    )
  })
})
