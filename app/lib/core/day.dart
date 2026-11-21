/// Study-day boundaries, ported from `src/core/scheduler/day.ts`.
library;

/// Start of the study day containing [now]: the most recent local
/// [rolloverHour]:00 at or before it.
int studyDayStart(int now, int rolloverHour) =>
    shiftStudyDay(now, 0, rolloverHour);

/// Start of the next study day. Uses calendar dates, so it survives DST.
int nextStudyDayStart(int now, int rolloverHour) =>
    shiftStudyDay(now, 1, rolloverHour);

/// The study day [offset] days after the one containing [time].
int shiftStudyDay(int time, int offset, int rolloverHour) {
  final t = DateTime.fromMillisecondsSinceEpoch(time);
  var start = DateTime(t.year, t.month, t.day, rolloverHour);
  var day = t.day;
  if (start.millisecondsSinceEpoch > time) day -= 1;
  start = DateTime(t.year, t.month, day + offset, rolloverHour);
  return start.millisecondsSinceEpoch;
}

/// The study day `[start, end)` containing [now].
({int start, int end}) studyDay(int now, int rolloverHour) => (
  start: studyDayStart(now, rolloverHour),
  end: nextStudyDayStart(now, rolloverHour),
);
