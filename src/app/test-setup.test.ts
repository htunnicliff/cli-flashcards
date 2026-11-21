import { describe, expect, it } from 'vitest'

describe('test setup', () => {
  it('forces prefers-reduced-motion: reduce', () => {
    expect(matchMedia('(prefers-reduced-motion: reduce)').matches).toBe(true)
    expect(matchMedia('(prefers-reduced-motion: no-preference)').matches).toBe(false)
  })
})
