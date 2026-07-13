import Foundation
import SwiftData
import Testing
@testable import Rep

@Suite("Workout creation and durability", .serialized)
@MainActor
struct WorkoutBehaviorTests {
    @Test("Starting from a routine creates independent workout data")
    func independentWorkout() {
        let exercise = Exercise(name: "Bench Press", primaryMuscleGroup: .chest, equipment: .barbell)
        let routineItem = RoutineExercise(exercise: exercise, targetSetCount: 3, suggestedRepetitions: 8)
        let routine = Routine(name: "Push", exercises: [routineItem])

        let session = WorkoutCreationService().startWorkout(from: routine, previousSessions: [], startedAt: TestFixtures.date("2026-06-01"))
        let workoutItem = session.orderedExercises[0]
        workoutItem.sets[0].repetitions = 12
        workoutItem.notes = "Changed for today"

        #expect(workoutItem.id != routineItem.id)
        #expect(routineItem.suggestedRepetitions == 8)
        #expect(routineItem.notes.isEmpty)
        #expect(workoutItem.sets.count == 3)
    }

    @Test("Same-routine previous performance is prioritized over a newer other-routine performance")
    func previousPerformancePriority() {
        let exercise = Exercise(name: "Squat", primaryMuscleGroup: .quadriceps, equipment: .barbell)
        let routine = Routine(name: "Legs", exercises: [RoutineExercise(exercise: exercise)])
        let other = TestFixtures.routine("Full Body")
        let sameRoutineItem = WorkoutExercise(exercise: exercise, sets: [WorkoutSet(weight: 100, repetitions: 5, isCompleted: true)])
        let otherRoutineItem = WorkoutExercise(exercise: exercise, sets: [WorkoutSet(weight: 120, repetitions: 3, isCompleted: true)])
        let sameRoutine = TestFixtures.completedSession(
            routine: routine,
            at: TestFixtures.date("2026-05-01"),
            exercises: [sameRoutineItem]
        )
        let newerOtherRoutine = TestFixtures.completedSession(
            routine: other,
            at: TestFixtures.date("2026-05-20"),
            exercises: [otherRoutineItem]
        )

        let session = WorkoutCreationService().startWorkout(
            from: routine,
            previousSessions: [sameRoutine, newerOtherRoutine],
            startedAt: TestFixtures.date("2026-06-01")
        )
        #expect(session.orderedExercises[0].orderedSets[0].weight == 100)
        #expect(session.orderedExercises[0].orderedSets[0].repetitions == 5)
    }

    @Test("An extra set prefills from the previous current set")
    func extraSetPrefill() {
        let exercise = WorkoutExercise(sets: [WorkoutSet(weight: 82.5, repetitions: 8)])
        let set = WorkoutCreationService().makeExtraSet(for: exercise, createdAt: TestFixtures.date("2026-06-01"))
        #expect(set.orderIndex == 1)
        #expect(set.weight == 82.5)
        #expect(set.repetitions == 8)
        #expect(!set.isCompleted)
    }

    @Test("Set completion is saved and an active session can be restored")
    func completionAndRestoration() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let exercise = Exercise(name: "Row", primaryMuscleGroup: .back, equipment: .barbell)
        let routine = Routine(name: "Pull", exercises: [RoutineExercise(exercise: exercise)])
        context.insert(exercise)
        context.insert(routine)
        try context.save()

        let service = WorkoutService(context: context)
        let session = try service.startWorkout(from: routine, at: TestFixtures.date("2026-06-01"))
        let set = session.orderedExercises[0].orderedSets[0]
        try service.completeSet(set, in: session.orderedExercises[0], at: TestFixtures.date("2026-06-01").addingTimeInterval(300))

        let restored = try service.activeSession()
        #expect(restored?.id == session.id)
        #expect(restored?.orderedExercises[0].orderedSets[0].isCompleted == true)
        #expect(restored?.orderedExercises[0].orderedSets[0].completedAt != nil)
    }

    @Test("Finishing moves a workout from active recovery to history")
    func completedHistory() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let service = WorkoutService(context: context)
        let session = try service.startEmptyWorkout(at: TestFixtures.date("2026-06-01"))
        try service.finish(session, at: TestFixtures.date("2026-06-01").addingTimeInterval(3_600))

        #expect(try service.activeSession() == nil)
        let repository = SwiftDataWorkoutRepository(context: context)
        let completed = try repository.completedSessions()
        #expect(completed.map(\.id).contains(session.id))
        #expect(session.state == .completed)
    }
}
