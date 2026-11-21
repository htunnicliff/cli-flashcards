import { describe, expect, it } from 'vitest'
import { commandParts, formatInterval, formatNextDue } from '.'

const MINUTE = 60_000
const DAY = 24 * 60 * MINUTE

describe('formatInterval', () => {
  it.each([
    [30_000, '<1m'],
    [10 * MINUTE, '10m'],
    [3 * 60 * MINUTE, '3h'],
    [4 * DAY, '4d'],
    [75 * DAY, '2.5mo'],
    [400 * DAY, '1.1y'],
    [4000 * DAY, '11y'],
  ])('%d → %s', (ms, label) => {
    expect(formatInterval(ms)).toBe(label)
  })
})

describe('formatNextDue', () => {
  const now = new Date(2026, 0, 10, 12, 0).getTime()
  it('uses minutes within the hour', () => {
    expect(formatNextDue(now + 12 * MINUTE, now)).toBe('in 12 minutes')
    expect(formatNextDue(now + 10_000, now)).toBe('in 1 minute')
  })
  it('names today, tomorrow and later days', () => {
    expect(formatNextDue(new Date(2026, 0, 10, 18, 0).getTime(), now, 'en-US')).toBe(
      'today at 6:00 PM',
    )
    expect(formatNextDue(new Date(2026, 0, 11, 9, 0).getTime(), now, 'en-US')).toBe(
      'tomorrow at 9:00 AM',
    )
    expect(formatNextDue(new Date(2026, 1, 20).getTime(), now, 'en-US')).toBe('on February 20')
  })
})

describe('commandParts', () => {
  it('marks tools, flags, arguments and the cloze blank', () => {
    expect(commandParts('rg ____ TODO src/')).toEqual([
      { kind: 'tool', text: 'rg' },
      { kind: 'blank', text: '' },
      { kind: 'tool', text: 'TODO' },
      { kind: 'tool', text: 'src/' },
    ])
    expect(commandParts('git log --oneline -n <count>')).toEqual([
      { kind: 'tool', text: 'git' },
      { kind: 'tool', text: 'log' },
      { kind: 'flag', text: '--oneline' },
      { kind: 'flag', text: '-n' },
      { kind: 'arg', text: '<count>' },
    ])
  })
})
