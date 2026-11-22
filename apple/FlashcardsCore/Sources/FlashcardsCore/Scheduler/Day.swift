// Study-day boundaries, ported from `src/core/scheduler/day.ts`.

import Foundation

/// Start of the study day containing `now`: the most recent local
/// `rolloverHour`:00 at or before it.
public func studyDayStart(_ now: Millis, rolloverHour: Int, timeZone: TimeZone = .current) -> Millis {
    shiftStudyDay(now, offset: 0, rolloverHour: rolloverHour, timeZone: timeZone)
}

/// Start of the next study day. Uses calendar dates, so it survives DST.
public func nextStudyDayStart(_ now: Millis, rolloverHour: Int, timeZone: TimeZone = .current) -> Millis {
    shiftStudyDay(now, offset: 1, rolloverHour: rolloverHour, timeZone: timeZone)
}

/// The study day `offset` days after the one containing `time`.
public func shiftStudyDay(_ time: Millis, offset: Int, rolloverHour: Int, timeZone: TimeZone = .current) -> Millis {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let date = Date(timeIntervalSince1970: Double(time) / 1000)
    let ymd = calendar.dateComponents([.year, .month, .day], from: date)

    func at(dayOffset: Int) -> Millis {
        // Step whole calendar days from local noon, then set the hour, like
        // JS `new Date(y, m, d + offset, hour)`.
        var noon = ymd
        noon.hour = 12
        let base = calendar.date(from: noon)!
        let shifted = calendar.date(byAdding: .day, value: dayOffset, to: base)!
        var parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        parts.hour = rolloverHour
        let start = calendar.date(from: parts)!
        return Millis((start.timeIntervalSince1970 * 1000).rounded())
    }

    let back = at(dayOffset: 0) > time ? -1 : 0
    return at(dayOffset: back + offset)
}

/// The study day `[start, end)` containing `now`.
public func studyDay(_ now: Millis, rolloverHour: Int, timeZone: TimeZone = .current) -> (start: Millis, end: Millis) {
    (
        studyDayStart(now, rolloverHour: rolloverHour, timeZone: timeZone),
        nextStudyDayStart(now, rolloverHour: rolloverHour, timeZone: timeZone)
    )
}
