import Foundation
import Testing
@testable import Rep

@Suite("Progress calculations")
struct ProgressCalculatorTests {
    @Test("Epley estimated one-repetition maximum")
    func epley() {
        let result = ProgressCalculator.estimatedOneRepMax(weight: 100, repetitions: 10)
        #expect(result != nil)
        #expect(abs(result! - 133.333_333) < 0.001)
        #expect(ProgressCalculator.estimatedOneRepMax(weight: 100, repetitions: 1) == 100)
    }

    @Test("Estimated 1RM rejects invalid and unsuitable repetitions")
    func invalidOneRepMax() {
        #expect(ProgressCalculator.estimatedOneRepMax(weight: 100, repetitions: 0) == nil)
        #expect(ProgressCalculator.estimatedOneRepMax(weight: 100, repetitions: -2) == nil)
        #expect(ProgressCalculator.estimatedOneRepMax(weight: 100, repetitions: 16) == nil)
        #expect(ProgressCalculator.estimatedOneRepMax(weight: 0, repetitions: 5) == nil)
    }

    @Test("Volume is only calculated for applicable measurement types")
    func volume() {
        #expect(ProgressCalculator.volume(weight: 80, repetitions: 5, measurementType: .weightAndRepetitions) == 400)
        #expect(ProgressCalculator.volume(weight: 80, repetitions: 5, measurementType: .bodyweightAndRepetitions) == nil)
        #expect(ProgressCalculator.volume(weight: 20, repetitions: 10, measurementType: .assistedBodyweight) == nil)
        #expect(ProgressCalculator.volume(weight: 80, repetitions: 0, measurementType: .weightAndRepetitions) == nil)
    }

    @Test("Personal records include weight, repetitions, 1RM, set volume, and workout volume")
    func personalRecords() {
        let exercise = Exercise(name: "Bench Press", primaryMuscleGroup: .chest, equipment: .barbell)
        let routine = TestFixtures.routine("Push")
        let first = WorkoutExercise(exercise: exercise, sets: [
            WorkoutSet(weight: 80, repetitions: 10, isCompleted: true),
            WorkoutSet(orderIndex: 1, weight: 90, repetitions: 5, isCompleted: true)
        ])
        let second = WorkoutExercise(exercise: exercise, sets: [
            WorkoutSet(weight: 95, repetitions: 3, isCompleted: true),
            WorkoutSet(orderIndex: 1, weight: 80, repetitions: 12, isCompleted: true),
            WorkoutSet(orderIndex: 2, weight: 100, repetitions: 1, isCompleted: false)
        ])
        let sessions = [
            TestFixtures.completedSession(routine: routine, at: TestFixtures.date("2026-05-01"), exercises: [first]),
            TestFixtures.completedSession(routine: routine, at: TestFixtures.date("2026-06-01"), exercises: [second])
        ]

        let result = ProgressCalculator.personalRecords(for: sessions, exerciseID: exercise.id)
        #expect(result.highestWeight == 95)
        #expect(result.mostRepetitionsAtWeight == RepetitionRecord(weight: 80, repetitions: 12))
        #expect(abs((result.highestEstimatedOneRepMax ?? 0) - 112) < 0.001)
        #expect(result.highestSetVolume == 960)
        #expect(result.highestWorkoutVolume == 1_250)
    }

    @Test("Bodyweight exercise does not report misleading volume records")
    func bodyweightRecords() {
        let exercise = Exercise(
            name: "Pull-Up",
            primaryMuscleGroup: .back,
            equipment: .bodyweight,
            measurementType: .bodyweightAndRepetitions
        )
        let routine = TestFixtures.routine("Pull")
        let item = WorkoutExercise(exercise: exercise, sets: [WorkoutSet(weight: 80, repetitions: 10, isCompleted: true)])
        let session = TestFixtures.completedSession(routine: routine, at: TestFixtures.date("2026-06-01"), exercises: [item])

        let result = ProgressCalculator.personalRecords(for: [session], exerciseID: exercise.id)
        #expect(result.highestSetVolume == nil)
        #expect(result.highestWorkoutVolume == nil)
        #expect(result.highestEstimatedOneRepMax == nil)
    }

    @Test("Date range filtering uses an injected reference date")
    func dateFiltering() {
        let routine = TestFixtures.routine("Full Body")
        let reference = TestFixtures.date("2026-07-01")
        let sessions = [10, 40, 100, 400].map { daysAgo in
            TestFixtures.completedSession(
                routine: routine,
                at: TestFixtures.calendar.date(byAdding: .day, value: -daysAgo, to: reference)!
            )
        }
        #expect(ProgressCalculator.filter(sessions: sessions, range: .thirtyDays, relativeTo: reference).count == 1)
        #expect(ProgressCalculator.filter(sessions: sessions, range: .ninetyDays, relativeTo: reference).count == 2)
        #expect(ProgressCalculator.filter(sessions: sessions, range: .allTime, relativeTo: reference).count == 4)
    }

    @Test("Weekly streak counts consecutive active weeks")
    func weeklyStreak() {
        let routine = TestFixtures.routine("Full Body")
        let calendar = TestFixtures.calendar
        let reference = TestFixtures.date("2026-07-13")

        let consecutive = [
            TestFixtures.date("2026-07-13"),
            TestFixtures.date("2026-07-06"),
            TestFixtures.date("2026-06-29")
        ].map { TestFixtures.completedSession(routine: routine, at: $0) }

        #expect(
            ProgressCalculator.weeklyStreak(
                sessions: consecutive,
                relativeTo: reference,
                calendar: calendar
            ) == 3
        )

        let withGap = consecutive + [TestFixtures.completedSession(routine: routine, at: TestFixtures.date("2026-06-08"))]
        #expect(
            ProgressCalculator.weeklyStreak(
                sessions: withGap,
                relativeTo: reference,
                calendar: calendar
            ) == 3
        )

        #expect(
            ProgressCalculator.weeklyStreak(
                sessions: [],
                relativeTo: reference,
                calendar: calendar
            ) == 0
        )
    }

    @Test("Weekly streak keeps prior weeks while the current week is still open")
    func weeklyStreakGracePeriod() {
        let routine = TestFixtures.routine("Full Body")
        let calendar = TestFixtures.calendar
        let reference = TestFixtures.date("2026-07-13")
        let sessions = [
            TestFixtures.completedSession(routine: routine, at: TestFixtures.date("2026-07-06")),
            TestFixtures.completedSession(routine: routine, at: TestFixtures.date("2026-06-29"))
        ]

        #expect(
            ProgressCalculator.weeklyStreak(
                sessions: sessions,
                relativeTo: reference,
                calendar: calendar
            ) == 2
        )
    }

    @Test("Daily best chart points collapse same-day sessions while keeping time")
    func dailyBestChartPoints() {
        let calendar = TestFixtures.calendar
        let morning = TestFixtures.date("2026-07-01")
        let evening = calendar.date(byAdding: .hour, value: 10, to: morning)!
        let morningID = UUID()
        let eveningID = UUID()

        let points = [
            ExerciseProgressPoint(
                sessionID: morningID,
                date: morning,
                estimatedOneRepMax: 100,
                bestWeight: 80,
                completedSetCount: 3
            ),
            ExerciseProgressPoint(
                sessionID: eveningID,
                date: evening,
                estimatedOneRepMax: 110,
                bestWeight: 90,
                completedSetCount: 4
            )
        ]

        let chartPoints = ExerciseProgressModel.dailyBestPoints(from: points, calendar: calendar)
        #expect(chartPoints.count == 1)
        #expect(chartPoints[0].sessionID == eveningID)
        #expect(chartPoints[0].date == evening)
        #expect(chartPoints[0].estimatedOneRepMax == 110)
    }

    @Test("Nice Y domain pads and rounds chart bounds")
    func niceYDomain() {
        let domain = ProgressChartScale.niceYDomain(for: [82, 88, 95], minimumPadding: 2.5)
        #expect(domain != nil)
        #expect(domain!.lowerBound < 82)
        #expect(domain!.upperBound > 95)
        #expect(domain!.upperBound - domain!.lowerBound < 30)
    }

    @Test("Day stride adapts to chart span")
    func dayStride() {
        let calendar = TestFixtures.calendar
        let start = TestFixtures.date("2026-07-01")
        let end = calendar.date(byAdding: .day, value: 45, to: start)!
        #expect(ProgressChartScale.dayStride(for: [start, end], calendar: calendar) == 7)
    }
}
