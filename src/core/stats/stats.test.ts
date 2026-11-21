import { describe, expect, it } from 'vitest'

import { DeckSchema } from '../../schema'
import { makeDeck, makeOption } from '../../schema/fixtures'
import type { StoredDeck } from '../storage'
import { makeCardState, makeFsrsState, makeLogEntry } from '../storage/test-utils'
import {
  cardCountsByDeck,
  computeStats,
  currentStreak,
  dueForecast,
  heatLevel,
  reviewHistory,
  reviewsByDay,
  shiftStudyDay,
  trueRetention,
} from './stats'

const ROLLOVER = 4
const at = (day: number, hour = 12) => new Date(2026, 0, day, hour).getTime()
const dayStart = (day: number) => new Date(2026, 0, day, ROLLOVER).getTime()

const deck: StoredDeck = {
  id: 'grep-gnu',
  deckVersion: 1,
  installedAt: 0,
  updatedAt: 0,
  includeObscure: false,
  deck: DeckSchema.parse(
    makeDeck([makeOption(['-i', '--ignore-case']), makeOption(['-v', '--invert-match'])]),
  ),
}
const card = (option: string, type = 'flag-to-meaning') => `grep:gnu:${option}:${type}`
const log = (...times: number[]) =>
  times.map((reviewedAt) => makeLogEntry(card('ignore-case'), { reviewedAt }))

describe('streak', () => {
  it('counts consecutive study days ending today', () => {
    const byDay = reviewsByDay(log(at(8), at(9), at(10), at(10, 15)), ROLLOVER)
    expect(currentStreak(byDay, at(10, 20), ROLLOVER)).toBe(3)
  })

  it('keeps yesterday’s streak until today ends, and breaks on a gap', () => {
    const byDay = reviewsByDay(log(at(6), at(8), at(9)), ROLLOVER)
    expect(currentStreak(byDay, at(10), ROLLOVER)).toBe(2)
    expect(currentStreak(byDay, at(11), ROLLOVER)).toBe(0)
  })

  it('counts 2 AM toward the previous study day', () => {
    const byDay = reviewsByDay(log(at(9), at(11, 2)), ROLLOVER)
    expect(currentStreak(byDay, at(11, 3), ROLLOVER)).toBe(2)
  })
})

describe('cardCountsByDeck', () => {
  it('sorts each derived card into one state', () => {
    const states = [
      makeCardState(card('ignore-case'), { fsrs: makeFsrsState({ phase: 'review' }) }),
      makeCardState(card('ignore-case', 'meaning-to-flag'), {
        fsrs: makeFsrsState({ phase: 'relearning' }),
      }),
      makeCardState(card('invert-match'), { suspended: true }),
      makeCardState('grep:gnu:gone:cloze', { fsrs: makeFsrsState({ phase: 'review' }) }),
    ]
    expect(cardCountsByDeck([deck], states)).toEqual([
      { deckId: 'grep-gnu', new: 1, learning: 1, review: 1, suspended: 1 },
    ])
  })
})

describe('trueRetention', () => {
  const mature = makeFsrsState({ phase: 'review', scheduledDays: 30 })
  const young = makeFsrsState({ phase: 'review', scheduledDays: 5 })
  const entry = (day: number, rating: 1 | 3, before = mature) =>
    makeLogEntry(card('ignore-case'), { reviewedAt: at(day), rating, before })

  it('is the share of mature reviews in the last 30 days not rated Again', () => {
    const result = trueRetention(
      [
        entry(20, 3),
        entry(21, 3),
        entry(22, 3),
        entry(23, 1),
        entry(23, 1, young),
        entry(23, 3, null as never),
      ],
      at(30),
      ROLLOVER,
    )
    expect(result).toEqual({ passed: 3, total: 4, rate: 0.75 })
  })

  it('ignores reviews older than the window', () => {
    expect(trueRetention([entry(1, 1)], at(31), ROLLOVER)).toEqual({ passed: 0, total: 0 })
    expect(trueRetention([entry(2, 1)], at(31), ROLLOVER).total).toBe(1)
  })
})

describe('dueForecast', () => {
  it('buckets due cards by study day, overdue into today', () => {
    const states = [
      makeCardState(card('ignore-case'), { fsrs: makeFsrsState({ due: at(1) }) }),
      makeCardState(card('ignore-case', 'meaning-to-flag'), {
        fsrs: makeFsrsState({ due: at(11, 2) }),
      }),
      makeCardState(card('invert-match'), { fsrs: makeFsrsState({ due: at(12) }) }),
      makeCardState(card('invert-match', 'meaning-to-flag'), {
        fsrs: makeFsrsState({ due: at(12) }),
        suspended: true,
      }),
      makeCardState('grep:gnu:gone:cloze', { fsrs: makeFsrsState({ due: at(12) }) }),
    ]
    const forecast = dueForecast([deck], states, at(10), ROLLOVER, 5)
    expect(forecast.map((d) => d.day)).toEqual([10, 11, 12, 13, 14].map(dayStart))
    expect(forecast.map((d) => d.count)).toEqual([2, 0, 1, 0, 0])
  })

  it('leaves out cards due past the window', () => {
    const states = [makeCardState(card('ignore-case'), { fsrs: makeFsrsState({ due: at(20) }) })]
    expect(dueForecast([deck], states, at(10), ROLLOVER, 5).every((d) => d.count === 0)).toBe(true)
  })
})

describe('reviewHistory and heatLevel', () => {
  it('lists every day up to today, oldest first', () => {
    const history = reviewHistory(
      reviewsByDay(log(at(8), at(10), at(10)), ROLLOVER),
      at(10),
      ROLLOVER,
      3,
    )
    expect(history).toEqual([
      { day: dayStart(8), count: 1 },
      { day: dayStart(9), count: 0 },
      { day: dayStart(10), count: 2 },
    ])
  })

  it('shades relative to the busiest day', () => {
    expect([0, 1, 5, 10, 20].map((n) => heatLevel(n, 20))).toEqual([0, 1, 1, 2, 4])
    expect(heatLevel(3, 0)).toBe(0)
  })

  it('shifts study days across month ends', () => {
    expect(shiftStudyDay(at(31), 1, ROLLOVER)).toBe(new Date(2026, 1, 1, ROLLOVER).getTime())
  })
})

it('computeStats puts it together', () => {
  const stats = computeStats({
    decks: [deck],
    states: [],
    log: log(at(9), at(10), at(10)),
    now: at(10),
    rolloverHour: ROLLOVER,
  })
  expect(stats).toMatchObject({ reviewsToday: 2, streak: 2, retention: { total: 0 } })
  expect(stats.forecast).toHaveLength(30)
  expect(stats.history).toHaveLength(365)
})
