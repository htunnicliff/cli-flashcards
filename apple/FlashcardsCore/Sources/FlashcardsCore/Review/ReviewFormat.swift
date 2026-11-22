// Review-screen text helpers, ported from `src/core/review/index.ts`.

import Foundation

private let minuteMs = 60_000
private let hourMs = 60 * minuteMs
private let dayMs = 24 * hourMs

/// JS `Math.round`.
private func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

private func trim(_ v: Double) -> String {
    if v >= 10 { return "\(jsRound(v))" }
    let s = String(format: "%.1f", v)
    return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
}

/// Short interval label for a grade button: "<1m", "10m", "3h", "4d", "2.5mo", "1.2y".
public func formatInterval(_ ms: Int) -> String {
    if ms < minuteMs { return "<1m" }
    if ms < hourMs { return "\(jsRound(Double(ms) / Double(minuteMs)))m" }
    if ms < dayMs { return "\(jsRound(Double(ms) / Double(hourMs)))h" }
    let days = Double(ms) / Double(dayMs)
    if days < 30 { return "\(jsRound(days))d" }
    if days < 365 { return "\(trim(days / 30))mo" }
    return "\(trim(days / 365))y"
}

private let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
private let months = [
    "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
    "November", "December",
]

/// When a later card is due, in words: "in 12 minutes", "tomorrow at 9:00 AM".
public func formatNextDue(_ due: Millis, now: Millis, timeZone: TimeZone = .current) -> String {
    let diff = due - now
    if diff < hourMs {
        let minutes = min(max(jsRound(Double(diff) / Double(minuteMs)), 1), 60)
        return "in \(minutes) minute\(minutes == 1 ? "" : "s")"
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let d = Date(timeIntervalSince1970: Double(due) / 1000)
    let n = Date(timeIntervalSince1970: Double(now) / 1000)
    let dayCount = calendar.dateComponents([.day], from: calendar.startOfDay(for: n), to: calendar.startOfDay(for: d)).day ?? 0
    let parts = calendar.dateComponents([.hour, .minute, .weekday, .month, .day], from: d)
    let hour = parts.hour!, h12 = hour % 12 == 0 ? 12 : hour % 12
    let time = "\(h12):\(String(format: "%02d", parts.minute!)) \(hour < 12 ? "AM" : "PM")"
    if dayCount == 0 { return "today at \(time)" }
    if dayCount == 1 { return "tomorrow at \(time)" }
    if dayCount < 7 { return "\(weekdays[parts.weekday! - 1]) at \(time)" }
    return "on \(months[parts.month! - 1]) \(parts.day!)"
}

public enum PartKind: String, Sendable { case tool, flag, arg, blank }

public struct CommandPart: Hashable, Sendable {
    public var kind: PartKind
    public var text: String
}

/// Splits a command into parts for display.
public func commandParts(_ command: String) -> [CommandPart] {
    let words = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    return words.enumerated().map { i, word in
        if let range = word.range(of: clozeBlank) {
            var text = word
            text.removeSubrange(range)
            return CommandPart(kind: .blank, text: text)
        }
        if i == 0 { return CommandPart(kind: .tool, text: word) }
        let chars = Array(word)
        let isFlag = chars.count >= 2 && chars[0] == "-" && (
            (chars[1] != "-" && !chars[1].isWhitespace) ||
            (chars[1] == "-" && chars.count >= 3 && chars[2] != "-" && !chars[2].isWhitespace)
        )
        if isFlag { return CommandPart(kind: .flag, text: word) }
        if word.count > 2 && word.hasPrefix("<") && word.hasSuffix(">") { return CommandPart(kind: .arg, text: word) }
        return CommandPart(kind: .tool, text: word)
    }
}
