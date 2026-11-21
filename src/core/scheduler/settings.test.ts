import { describe, expect, it } from 'vitest'

import { SETTING_DEFAULTS } from '../storage'
import {
  normalizeSchedulingSetting,
  SCHEDULING_LIMITS,
  type SchedulingSettingKey,
} from './settings'

describe('normalizeSchedulingSetting', () => {
  it('keeps every default as is', () => {
    for (const key of Object.keys(SCHEDULING_LIMITS) as SchedulingSettingKey[]) {
      expect(normalizeSchedulingSetting(key, SETTING_DEFAULTS[key])).toBe(SETTING_DEFAULTS[key])
    }
  })

  it('clamps to the allowed range', () => {
    expect(normalizeSchedulingSetting('desiredRetention', 0.5)).toBe(0.7)
    expect(normalizeSchedulingSetting('desiredRetention', 1)).toBe(0.99)
    expect(normalizeSchedulingSetting('dayRolloverHour', 24)).toBe(23)
    expect(normalizeSchedulingSetting('newCardsPerDay', -3)).toBe(0)
  })

  it('rounds onto the step', () => {
    expect(normalizeSchedulingSetting('desiredRetention', 0.876)).toBe(0.88)
    expect(normalizeSchedulingSetting('newCardsPerDay', 12.6)).toBe(13)
  })

  it('rejects non-numbers', () => {
    expect(normalizeSchedulingSetting('maxReviewsPerDay', Number.NaN)).toBeUndefined()
  })
})
