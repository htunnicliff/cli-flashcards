import fc from 'fast-check'
import { describe, expect, it } from 'vitest'

import { clamp } from './clamp'

describe('clamp', () => {
  it('leaves values inside the range unchanged', () => {
    expect(clamp(5, 0, 10)).toBe(5)
  })

  it('pins values outside the range to the nearest bound', () => {
    expect(clamp(-3, 0, 10)).toBe(0)
    expect(clamp(42, 0, 10)).toBe(10)
  })

  it('rejects an inverted range', () => {
    expect(() => clamp(1, 10, 0)).toThrow(RangeError)
  })

  it('always returns a value within [min, max]', () => {
    fc.assert(
      fc.property(
        fc.double({ noNaN: true }),
        fc.double({ noNaN: true }),
        fc.double({ noNaN: true }),
        (value, a, b) => {
          const [min, max] = a <= b ? [a, b] : [b, a]
          const result = clamp(value, min, max)
          expect(result).toBeGreaterThanOrEqual(min)
          expect(result).toBeLessThanOrEqual(max)
        },
      ),
    )
  })
})
