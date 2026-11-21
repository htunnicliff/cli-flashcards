import { createEmptyCard, fsrs, State, type Card as FsrsCard, type FSRS, type Grade } from 'ts-fsrs'

import type { CardPhase, FsrsState, Rating } from '../storage'

export interface FsrsOptions {
  desiredRetention: number
}

const PHASE_BY_STATE: Record<State, CardPhase> = {
  [State.New]: 'new',
  [State.Learning]: 'learning',
  [State.Review]: 'review',
  [State.Relearning]: 'relearning',
}

const STATE_BY_PHASE: Record<CardPhase, State> = {
  new: State.New,
  learning: State.Learning,
  review: State.Review,
  relearning: State.Relearning,
}

export function fromFsrsCard(card: FsrsCard): FsrsState {
  return {
    phase: PHASE_BY_STATE[card.state],
    due: card.due.getTime(),
    stability: card.stability,
    difficulty: card.difficulty,
    elapsedDays: card.elapsed_days,
    scheduledDays: card.scheduled_days,
    learningSteps: card.learning_steps,
    reps: card.reps,
    lapses: card.lapses,
    ...(card.last_review ? { lastReview: card.last_review.getTime() } : {}),
  }
}

export function toFsrsCard(state: FsrsState): FsrsCard {
  return {
    state: STATE_BY_PHASE[state.phase],
    due: new Date(state.due),
    stability: state.stability,
    difficulty: state.difficulty,
    elapsed_days: state.elapsedDays,
    scheduled_days: state.scheduledDays,
    learning_steps: state.learningSteps,
    reps: state.reps,
    lapses: state.lapses,
    ...(state.lastReview === undefined ? {} : { last_review: new Date(state.lastReview) }),
  }
}

/** A card that has never been reviewed, due immediately. */
export function newFsrsState(now: number): FsrsState {
  return fromFsrsCard(createEmptyCard(new Date(now)))
}

const engines = new Map<number, FSRS>()

/**
 * FSRS with default weights and learning steps (1m, 10m; relearning 10m).
 * Fuzz is off so a card's state is a pure function of its review log, which
 * is what lets the log be replayed.
 */
function engine({ desiredRetention }: FsrsOptions): FSRS {
  let instance = engines.get(desiredRetention)
  if (!instance) {
    instance = fsrs({
      request_retention: desiredRetention,
      enable_fuzz: false,
      enable_short_term: true,
    })
    engines.set(desiredRetention, instance)
  }
  return instance
}

/** The state after grading. `before` is `null` for a card never seen. */
export function nextState(
  before: FsrsState | null,
  rating: Rating,
  now: number,
  options: FsrsOptions,
): FsrsState {
  const card = before ? toFsrsCard(before) : createEmptyCard(new Date(now))
  return fromFsrsCard(engine(options).next(card, new Date(now), rating as Grade).card)
}

/** Probability the card is recalled at `now`, 0–1. New cards report 0. */
export function retrievability(state: FsrsState, now: number, options: FsrsOptions): number {
  if (state.phase === 'new') return 0
  return engine(options).get_retrievability(toFsrsCard(state), new Date(now), false)
}

/** Rebuilds a card's state by replaying its grades, oldest first. */
export function replay(
  reviews: readonly { reviewedAt: number; rating: Rating }[],
  options: FsrsOptions,
): FsrsState | null {
  let state: FsrsState | null = null
  for (const review of reviews) state = nextState(state, review.rating, review.reviewedAt, options)
  return state
}
