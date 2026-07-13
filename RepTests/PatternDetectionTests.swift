import Foundation
import Testing
@testable import Rep

@Suite("Deterministic pattern detection")
struct PatternDetectionTests {
    private let calendar = TestFixtures.calendar

    @Test("Weekday routine detection explains supporting observations")
    func weekdayRoutine() {
        let push = TestFixtures.routine("Push")
        let pull = TestFixtures.routine("Pull")
        let unique = TestFixtures.routine("Upper")
        let reference = TestFixtures.date("2026-07-14")
        let tuesdays = [
            "2026-05-19", "2026-05-26", "2026-06-02", "2026-06-09",
            "2026-06-16", "2026-06-23", "2026-06-30", "2026-07-07"
        ].map(TestFixtures.date)
        let sessions = tuesdays.enumerated().map { index, date in
            TestFixtures.completedSession(routine: index < 2 ? pull : push, at: date)
        } + [TestFixtures.completedSession(routine: unique, at: TestFixtures.date("2026-07-13"))]

        let result = PatternDetectionService(calendar: calendar).suggestion(
            for: reference,
            sessions: sessions,
            routines: [push, pull, unique]
        )

        #expect(result?.routineID == push.id)
        #expect(result?.type == .weekdayRoutine)
        #expect(result?.observationCount == 6)
        #expect(result?.explanation.contains("6 of your last 8 Tuesdays") == true)
    }

    @Test("Routine transition detects the likely next routine")
    func routineTransition() {
        let push = TestFixtures.routine("Push")
        let pull = TestFixtures.routine("Pull")
        let reference = TestFixtures.date("2026-07-15")
        let sessions = alternating([push, pull, push, pull, push, pull, push, pull, push], endingAt: reference)

        let result = PatternDetectionService(calendar: calendar).suggestion(
            for: reference,
            sessions: sessions,
            routines: [push, pull]
        )

        #expect(result?.routineID == pull.id)
        #expect(result?.observationCount == 4)
        #expect(result?.explanation.contains("after Push") == true)
    }

    @Test("Fewer than three observations produces no suggestion")
    func insufficientData() {
        let push = TestFixtures.routine("Push")
        let pull = TestFixtures.routine("Pull")
        let reference = TestFixtures.date("2026-07-15")
        let sessions = alternating([push, pull, push, pull, push], endingAt: reference)

        let result = PatternDetectionService(calendar: calendar).suggestion(
            for: reference,
            sessions: sessions,
            routines: [push, pull]
        )
        #expect(result == nil)
    }

    @Test("Recent transitions outweigh stale competing history")
    func recencyWeighting() {
        let push = TestFixtures.routine("Push")
        let pull = TestFixtures.routine("Pull")
        let legs = TestFixtures.routine("Legs")
        let reference = TestFixtures.date("2026-07-15")
        var sessions: [WorkoutSession] = []

        for offset in [280, 260, 240, 220] {
            let start = calendar.date(byAdding: .day, value: -offset, to: reference)!
            sessions.append(TestFixtures.completedSession(routine: push, at: start))
            sessions.append(TestFixtures.completedSession(routine: legs, at: calendar.date(byAdding: .day, value: 1, to: start)!))
        }
        for offset in [28, 18, 8] {
            let start = calendar.date(byAdding: .day, value: -offset, to: reference)!
            sessions.append(TestFixtures.completedSession(routine: push, at: start))
            sessions.append(TestFixtures.completedSession(routine: pull, at: calendar.date(byAdding: .day, value: 1, to: start)!))
        }
        sessions.append(TestFixtures.completedSession(routine: push, at: calendar.date(byAdding: .day, value: -1, to: reference)!))

        let result = PatternDetectionService(calendar: calendar).suggestion(
            for: reference,
            sessions: sessions,
            routines: [push, pull, legs]
        )
        #expect(result?.routineID == pull.id)
    }

    @Test("A dismissal lowers confidence")
    func dismissalPenalty() {
        let (service, routines, sessions, reference) = stableTransitionFixture()
        let initial = service.suggestion(for: reference, sessions: sessions, routines: routines)!
        let persisted = service.learnedPattern(from: initial)
        persisted.dismissedCount = 1

        let reduced = service.suggestion(
            for: reference,
            sessions: sessions,
            routines: routines,
            learnedPatterns: [persisted]
        )
        #expect(reduced != nil)
        #expect(reduced!.confidence < initial.confidence)
    }

    @Test("Suppressed patterns are not surfaced")
    func suppressedSuggestion() {
        let (service, routines, sessions, reference) = stableTransitionFixture()
        let initial = service.suggestion(for: reference, sessions: sessions, routines: routines)!
        let persisted = service.learnedPattern(from: initial)
        persisted.isSuppressed = true

        let result = service.suggestion(
            for: reference,
            sessions: sessions,
            routines: routines,
            learnedPatterns: [persisted]
        )
        #expect(result == nil)
    }

    @Test("Competing transitions reduce confidence and the stronger pattern wins")
    func competingPatterns() {
        let push = TestFixtures.routine("Push")
        let pull = TestFixtures.routine("Pull")
        let legs = TestFixtures.routine("Legs")
        let reference = TestFixtures.date("2026-07-15")
        let sequence = [push, legs, push, pull, push, legs, push, pull, push, pull, push, pull, push]
        let sessions = alternating(sequence, endingAt: reference)

        let result = PatternDetectionService(calendar: calendar).suggestion(
            for: reference,
            sessions: sessions,
            routines: [push, pull, legs]
        )
        #expect(result?.routineID == pull.id)
        #expect((result?.confidence ?? 1) < 0.9)
    }

    @Test("Repeated rotation sequences infer the next routine")
    func rotationSequence() {
        let push = TestFixtures.routine("Push")
        let pull = TestFixtures.routine("Pull")
        let legs = TestFixtures.routine("Legs")
        let reference = TestFixtures.date("2026-07-15")
        let sequence = Array(repeating: [push, pull, legs], count: 4).flatMap { $0 } + [push, pull]
        let sessions = alternating(sequence, endingAt: reference)

        let result = PatternDetectionService(calendar: calendar).suggestion(
            for: reference,
            sessions: sessions,
            routines: [push, pull, legs]
        )
        #expect(result?.routineID == legs.id)
        #expect(result?.type == .rotation)
    }

    private func alternating(_ routines: [Routine], endingAt reference: Date) -> [WorkoutSession] {
        routines.enumerated().map { index, routine in
            let daysAgo = routines.count - index
            return TestFixtures.completedSession(
                routine: routine,
                at: calendar.date(byAdding: .day, value: -daysAgo, to: reference)!
            )
        }
    }

    private func stableTransitionFixture() -> (
        PatternDetectionService, [Routine], [WorkoutSession], Date
    ) {
        let push = TestFixtures.routine("Push")
        let pull = TestFixtures.routine("Pull")
        let reference = TestFixtures.date("2026-07-15")
        let service = PatternDetectionService(calendar: calendar)
        let sessions = alternating([push, pull, push, pull, push, pull, push, pull, push], endingAt: reference)
        return (service, [push, pull], sessions, reference)
    }
}
