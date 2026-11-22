import Foundation
import Testing
@testable import FlashcardsCore

@Suite struct LibraryAndFormatTests {
    @Test func formatsIntervals() {
        #expect(formatInterval(30_000) == "<1m")
        #expect(formatInterval(10 * minute) == "10m")
        #expect(formatInterval(3 * 3_600_000) == "3h")
        #expect(formatInterval(4 * day) == "4d")
        #expect(formatInterval(75 * day) == "2.5mo")
        #expect(formatInterval(438 * day) == "1.2y")
    }

    @Test func formatsNextDue() {
        #expect(formatNextDue(noon + 12 * minute, now: noon, timeZone: testZone) == "in 12 minutes")
        #expect(formatNextDue(noon + 3 * 3_600_000, now: noon, timeZone: testZone) == "today at 3:00 PM")
        #expect(formatNextDue(noon + day - 3 * 3_600_000, now: noon, timeZone: testZone) == "tomorrow at 9:00 AM")
    }

    @Test func splitsCommandParts() {
        #expect(commandParts("rg ____ <pattern> src").map(\.kind) == [.tool, .blank, .arg, .tool])
        #expect(commandParts("grep --count -i x").map(\.kind) == [.tool, .flag, .flag, .tool])
    }

    @Test func flavorAndVariants() {
        #expect(variantForFlavor(["bsd", "gnu"], .bsd) == "bsd")
        #expect(variantForFlavor(["default"], .gnu) == "default")
        #expect(resolveFlavor(nil, ["gnu", "gnu", "bsd"], .bsd) == .gnu)
        #expect(resolveFlavor(nil, [String](), .bsd) == .bsd)
    }

    @Test func searchPutsFlagPrefixMatchesFirst() {
        let options = [option("count", ["-c", "--count"]), option("ignore-case", ["-i", "--ignore-case"])]
        #expect(searchOptions(options, "--ign").map(\.id) == ["ignore-case"])
        #expect(searchOptions(options, "summary").count == 2)
    }

    @Test func describesChanges() {
        let a = deck([option("a", ["-a"])])
        let b = deck([option("b", ["-b"]), option("c", ["-c"])])
        #expect(describeChanges(diffDecks(a, b)) == "2 options added, 1 removed")
    }

    @Test func settingLimitsClampAndStep() {
        #expect(SettingLimits.desiredRetention.normalize(0.5) == 0.7)
        #expect(SettingLimits.desiredRetention.normalize(0.904) == 0.9)
        #expect(SettingLimits.newCardsPerDay.normalize(12.6) == 13)
    }

    @Test func streakCountsThroughYesterdayBeforeTodaysFirstReview() {
        let log = [1, 2, 4].map {
            ReviewLogEntry(cardId: "x", deckId: "d", reviewedAt: noon - $0 * day, rating: .good, durationMs: 0, before: nil, after: anyFsrs)
        }
        let byDay = reviewsByDay(log, rolloverHour: 4, timeZone: testZone)
        #expect(currentStreak(byDay, now: noon, rolloverHour: 4, timeZone: testZone) == 2)
        #expect(heatLevel(3, max: 12) == 1)
        #expect(heatLevel(12, max: 12) == 4)
    }
}
