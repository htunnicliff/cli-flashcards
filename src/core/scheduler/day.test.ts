import { describe, expect, it } from 'vitest'

import { nextStudyDayStart, studyDayStart } from './day'

const at = (day: number, hour: number, minute = 0) => new Date(2026, 0, day, hour, minute).getTime()

describe('study days', () => {
  it('start at the rollover hour', () => {
    expect(studyDayStart(at(10, 12), 4)).toBe(at(10, 4))
    expect(nextStudyDayStart(at(10, 12), 4)).toBe(at(11, 4))
  })

  it('put the small hours before rollover on the previous day', () => {
    expect(studyDayStart(at(10, 2), 4)).toBe(at(9, 4))
    expect(nextStudyDayStart(at(10, 2), 4)).toBe(at(10, 4))
    expect(studyDayStart(at(10, 4), 4)).toBe(at(10, 4))
  })

  it('treat a midnight rollover as calendar days', () => {
    expect(studyDayStart(at(10, 0, 30), 0)).toBe(at(10, 0))
    expect(studyDayStart(at(10, 23, 59), 0)).toBe(at(10, 0))
  })
})
