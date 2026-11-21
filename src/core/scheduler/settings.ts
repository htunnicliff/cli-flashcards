import type { Settings } from '../storage'

export type SchedulingSettingKey =
  'desiredRetention' | 'newCardsPerDay' | 'maxReviewsPerDay' | 'dayRolloverHour' | 'leechThreshold'

export interface SettingLimits {
  min: number
  max: number
  step: number
}

/** Allowed range for each scheduling setting, shared by validation and the Settings form. */
export const SCHEDULING_LIMITS: Record<SchedulingSettingKey, SettingLimits> = {
  // FSRS behaves badly at the extremes: below 0.7 cards are forgotten too
  // often to be useful, above 0.99 the review load explodes.
  desiredRetention: { min: 0.7, max: 0.99, step: 0.01 },
  newCardsPerDay: { min: 0, max: 999, step: 1 },
  maxReviewsPerDay: { min: 0, max: 9999, step: 1 },
  dayRolloverHour: { min: 0, max: 23, step: 1 },
  leechThreshold: { min: 2, max: 99, step: 1 },
}

/**
 * Brings a typed-in value into range and onto its step, or returns `undefined`
 * when it isn't a number at all.
 */
export function normalizeSchedulingSetting<K extends SchedulingSettingKey>(
  key: K,
  value: number,
): Settings[K] | undefined {
  if (!Number.isFinite(value)) return undefined
  const { min, max, step } = SCHEDULING_LIMITS[key]
  const stepped = Math.round(value / step) * step
  const clamped = Math.min(max, Math.max(min, stepped))
  // Undo float noise such as 0.9000000000000001.
  return Number(clamped.toFixed(2)) as Settings[K]
}
