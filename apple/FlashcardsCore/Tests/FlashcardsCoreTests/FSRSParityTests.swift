import Foundation
import Testing
@testable import FlashcardsCore

private struct GoldenStep: Decodable {
    var now: Millis
    var rating: Int
    var after: FsrsState
    var retrievabilityAt: Millis
    var retrievability: Double
}

private struct GoldenSequence: Decodable {
    var desiredRetention: Double
    var steps: [GoldenStep]
}

private struct FsrsGolden: Decodable {
    var sequences: [GoldenSequence]
}

@Suite struct FSRSParityTests {
    @Test func matchesTsFsrsOnEveryGoldenSequence() throws {
        let golden = try Repo.fixture("fsrs_golden.json", as: FsrsGolden.self)
        var checked = 0
        for (i, sequence) in golden.sequences.enumerated() {
            var state: FsrsState?
            for (j, step) in sequence.steps.enumerated() {
                let next = nextState(
                    state, try #require(Rating(rawValue: step.rating)), now: step.now,
                    desiredRetention: sequence.desiredRetention
                )
                #expect(next == step.after, "sequence \(i) step \(j)")
                let r = retrievability(next, now: step.retrievabilityAt)
                #expect(abs(r - step.retrievability) < 1e-12, "retrievability, sequence \(i) step \(j)")
                state = next
                checked += 1
            }
        }
        #expect(checked > 1000)
    }

    @Test func aNewCardIsDueNowAndReportsZeroRetrievability() {
        let state = newFsrsState(1000)
        #expect(state.phase == .new)
        #expect(state.due == 1000)
        #expect(retrievability(state, now: 5000) == 0)
    }

    @Test func replayRebuildsTheStateFromGrades() {
        let t: Millis = 1_767_225_600_000
        let reviews: [(reviewedAt: Millis, rating: Rating)] = [
            (t, .good), (t + 600_000, .good), (t + 3 * 86_400_000, .again),
        ]
        var state = nextState(nil, .good, now: t, desiredRetention: 0.9)
        state = nextState(state, .good, now: t + 600_000, desiredRetention: 0.9)
        state = nextState(state, .again, now: t + 3 * 86_400_000, desiredRetention: 0.9)
        #expect(replay(reviews, desiredRetention: 0.9) == state)
        #expect(state.phase == .relearning)
        #expect(state.lapses == 1)
    }
}

@Suite struct StudyDayTests {
    let newYork = TimeZone(identifier: "America/New_York")!

    @Test func startsAtTheRolloverHour() {
        // 2026-03-10 02:00 local is before the 4am rollover, so the day began on the 9th.
        let t: Millis = 1_773_122_400_000 // 2026-03-10T06:00:00Z = 02:00 EDT
        let start = studyDayStart(t, rolloverHour: 4, timeZone: newYork)
        #expect(start == 1_773_043_200_000) // 2026-03-09T08:00:00Z = 04:00 EDT
    }

    @Test func survivesDaylightSavingTime() {
        // DST starts 2026-03-08 in New York, so that study day is 23 hours long.
        let t: Millis = 1_772_935_200_000 // 2026-03-08T02:00:00Z = 2026-03-07 21:00 EST
        let day = studyDay(t, rolloverHour: 4, timeZone: newYork)
        #expect(day.end - day.start == 23 * 3_600_000)
    }
}
