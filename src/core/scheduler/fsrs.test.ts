import fc from 'fast-check'
import { describe, expect, it } from 'vitest'

import type { FsrsState, Rating } from '../storage'
import { newFsrsState, nextState, replay, retrievability } from './fsrs'

const options = { desiredRetention: 0.9 }
const DAY = 24 * 60 * 60 * 1000
const START = new Date(2026, 0, 1, 9).getTime()

const rating = fc.constantFrom<Rating>(1, 2, 3, 4)
/** A history of grades, each some minutes to months after the last. */
const history = fc.array(fc.record({ rating, gap: fc.integer({ min: 0, max: 120 * DAY }) }), {
  minLength: 1,
  maxLength: 15,
})

function play(steps: { rating: Rating; gap: number }[]) {
  let now = START
  let state: FsrsState | null = null
  const reviews: { rating: Rating; reviewedAt: number }[] = []
  for (const step of steps) {
    now += step.gap
    state = nextState(state, step.rating, now, options)
    reviews.push({ rating: step.rating, reviewedAt: now })
  }
  return { state: state!, now, reviews }
}

describe('nextState', () => {
  it('puts a new card graded Good into learning, due in minutes', () => {
    const state = nextState(null, 3, START, options)
    expect(state).toMatchObject({ phase: 'learning', reps: 1, lapses: 0, lastReview: START })
    expect(state.due - START).toBe(10 * 60 * 1000)
  })

  it('graduates a card and lapses it back to relearning on Again', () => {
    let state = nextState(null, 3, START, options)
    state = nextState(state, 3, state.due, options)
    expect(state.phase).toBe('review')
    const reviewAt = state.due
    state = nextState(state, 1, reviewAt, options)
    expect(state).toMatchObject({ phase: 'relearning', lapses: 1 })
    expect(state.due).toBeGreaterThan(reviewAt)
  })

  it('starts new cards at zero retrievability', () => {
    expect(retrievability(newFsrsState(START), START, options)).toBe(0)
    const state = nextState(nextState(null, 3, START, options), 4, START + DAY, options)
    expect(retrievability(state, state.lastReview!, options)).toBeCloseTo(1)
  })

  it('never schedules a card in the past', () => {
    fc.assert(
      fc.property(history, (steps) => {
        const { state, now } = play(steps)
        expect(state.due).toBeGreaterThanOrEqual(now)
      }),
    )
  })

  it('orders intervals Again ≤ Hard ≤ Good ≤ Easy for the same card', () => {
    fc.assert(
      fc.property(
        fc.option(history, { nil: undefined }),
        fc.integer({ min: 0, max: 60 * DAY }),
        (steps, wait) => {
          const before = steps ? play(steps) : { state: null, now: START }
          const now = before.now + wait
          const dues = ([1, 2, 3, 4] as const).map(
            (r) => nextState(before.state, r, now, options).due,
          )
          for (let i = 1; i < dues.length; i++) expect(dues[i]).toBeGreaterThanOrEqual(dues[i - 1]!)
        },
      ),
    )
  })

  it('is reproduced by replaying the grades', () => {
    fc.assert(
      fc.property(history, (steps) => {
        const { state, reviews } = play(steps)
        expect(replay(reviews, options)).toEqual(state)
      }),
    )
  })
})
