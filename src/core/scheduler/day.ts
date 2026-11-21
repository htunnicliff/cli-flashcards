/**
 * Start of the study day containing `now`: the most recent local
 * `rolloverHour`:00 at or before it. With a 4 AM rollover, 2 AM on the 10th
 * still belongs to the 9th.
 */
export function studyDayStart(now: number, rolloverHour: number): number {
  const start = new Date(now)
  start.setHours(rolloverHour, 0, 0, 0)
  if (start.getTime() > now) start.setDate(start.getDate() - 1)
  return start.getTime()
}

/** Start of the next study day. Uses calendar dates, so it survives DST changes. */
export function nextStudyDayStart(now: number, rolloverHour: number): number {
  const next = new Date(studyDayStart(now, rolloverHour))
  next.setDate(next.getDate() + 1)
  return next.getTime()
}
