import Foundation
import Testing
@testable import FlashcardsCore

@Suite struct SchedulerTests {
    let scheduler: Scheduler

    init() throws {
        let repo = Repository.inMemory()
        try repo.installDeck(deck([
            option("ignore-case", ["-i", "--ignore-case"]),
            option("word-regexp", ["-w", "--word-regexp"]),
            option("count", ["-c", "--count"], tier: .common),
            option("pre", ["--pre"], tier: .obscure),
        ]), now: noon)
        try repo.updateSettings { $0.flagPairs = false }
        scheduler = Scheduler(repository: repo, timeZone: testZone)
    }

    @Test func newCardsComeOnePerOptionCoreTierFirstObscureLeftOut() {
        let queue = scheduler.queue(now: noon)
        #expect(queue.items.map(\.card.id) == [
            "rg:default:ignore-case:flag-to-meaning",
            "rg:default:word-regexp:flag-to-meaning",
            "rg:default:count:flag-to-meaning",
        ])
        #expect(queue.items.allSatisfy { $0.kind == .new })
        #expect(queue.today.newLeft == 20)
    }

    @Test func gradingANewCardStartsItsLearningStepsAndBuriesSiblings() throws {
        let id = "rg:default:ignore-case:flag-to-meaning"
        let result = try scheduler.grade(id, .good, now: noon)
        #expect(result.state.fsrs.phase == .learning)
        #expect(result.entry.id != nil)

        let later = scheduler.queue(now: noon + 11 * minute)
        #expect(later.items.first?.card.id == id)
        #expect(later.items.first?.kind == .learning)
        #expect(later.items.filter { $0.card.optionId == "ignore-case" }.count == 1)
        #expect(later.today.newDone == 1)
    }

    @Test func dailyNewCardLimitCountsGradesFromToday() throws {
        try scheduler.repository.updateSettings { $0.newCardsPerDay = 1 }
        #expect(scheduler.queue(now: noon).items.count == 1)
        try scheduler.grade("rg:default:ignore-case:flag-to-meaning", .easy, now: noon)
        let queue = scheduler.queue(now: noon + minute)
        #expect(!queue.items.contains { $0.kind == .new })
        #expect(queue.today.newLeft == 0)
    }

    @Test func aCardThatLapsesEnoughTimesBecomesASuspendedLeech() throws {
        try scheduler.repository.updateSettings { $0.leechThreshold = 2 }
        let id = "rg:default:count:meaning-to-flag"
        var t = noon
        try scheduler.grade(id, .easy, now: t)
        var last: GradeResult?
        for _ in 0..<2 {
            t = scheduler.repository.cardState(id)!.fsrs.due + minute
            try scheduler.grade(id, .again, now: t)
            t += 11 * minute
            last = try scheduler.grade(id, .easy, now: t)
        }
        let state = try #require(scheduler.repository.cardState(id))
        #expect(state.leech)
        #expect(state.suspended)
        #expect(last?.becameLeech == false)
    }

    @Test func buryHidesACardUntilTheNextStudyDayAndRestorePutsItBack() throws {
        let id = "rg:default:ignore-case:flag-to-meaning"
        let previous = try scheduler.setAside([id], .bury, now: noon)
        #expect(scheduler.repository.cardState(id)?.buriedUntil == nextStudyDayStart(noon, rolloverHour: 4, timeZone: testZone))
        #expect(!scheduler.queue(now: noon).items.map(\.card.id).contains(id))
        try scheduler.restore(previous)
        #expect(scheduler.repository.cardState(id) == nil)
    }

    @Test func suspendAndUnsuspend() throws {
        let id = "rg:default:word-regexp:flag-to-meaning"
        try scheduler.setAside([id], .suspend, now: noon)
        #expect(scheduler.repository.cardState(id)?.suspended == true)
        try scheduler.unsuspend([id])
        #expect(scheduler.repository.cardState(id)?.suspended == false)
    }

    @Test func nextDueReportsTheEarliestStudiedCard() throws {
        try scheduler.grade("rg:default:ignore-case:flag-to-meaning", .again, now: noon)
        #expect(scheduler.nextDue(now: noon) == noon + minute)
    }

    @Test func undoRemovesTheGradeAndRestoresTheState() throws {
        let id = "rg:default:ignore-case:flag-to-meaning"
        let first = try scheduler.grade(id, .good, now: noon)
        let second = try scheduler.grade(id, .good, now: noon + 11 * minute)
        try scheduler.undo(second)
        #expect(scheduler.repository.cardState(id) == first.state)
        try scheduler.undo(first)
        #expect(scheduler.repository.cardState(id) == nil)
        #expect(scheduler.repository.reviewCount() == 0)
    }

    @Test func studyDaysRollOverAtTheConfiguredHour() {
        let twoAm = noon + day - 10 * 3_600_000 // 2026-03-03 02:00
        #expect(studyDayStart(twoAm, rolloverHour: 4, timeZone: testZone) == noon - 8 * 3_600_000)
        #expect(nextStudyDayStart(twoAm, rolloverHour: 4, timeZone: testZone) == noon + day - 8 * 3_600_000)
    }
}
