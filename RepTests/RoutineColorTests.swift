import Foundation
import SwiftData
import Testing
@testable import Rep

@Suite("Routine colors")
struct RoutineColorTests {
    @Test("Legacy routines without a stored color use blue")
    func legacyDefault() {
        let routine = Routine(name: "Legacy")
        routine.colorPresetRaw = nil

        #expect(routine.colorPreset == .blue)
    }

    @Test("A workout keeps the routine color as a history snapshot")
    func workoutSnapshot() {
        let routine = Routine(name: "Pull", colorPreset: .purple)
        let workout = WorkoutCreationService().startWorkout(
            from: routine,
            previousSessions: []
        )

        #expect(workout.routineColorPreset == .purple)
    }

    @Test("Invalid stored values fall back safely")
    func invalidValueFallback() {
        let routine = Routine(name: "Imported")
        routine.colorPresetRaw = "future-color"

        #expect(routine.colorPreset == .blue)
    }

    @Test("Startup backfill persists the current routine color on legacy workouts")
    @MainActor
    func startupBackfill() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let routine = Routine(name: "Pull", colorPreset: .purple)
        let legacyWorkout = WorkoutSession(routineID: routine.id, name: routine.name)

        context.insert(routine)
        context.insert(legacyWorkout)
        try context.save()

        #expect(try RoutineColorSnapshotBackfillService.backfill(in: context) == 1)
        #expect(legacyWorkout.routineColorPreset == .purple)

        let verificationContext = ModelContext(container)
        let storedSessions = try verificationContext.fetch(FetchDescriptor<WorkoutSession>())
        #expect(storedSessions.first(where: { $0.id == legacyWorkout.id })?.routineColorPreset == .purple)
    }

    @Test("Startup backfill preserves snapshots and ignores missing routines")
    @MainActor
    func safeBackfillBoundaries() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let routine = Routine(name: "Legs", colorPreset: .green)
        let existingSnapshot = WorkoutSession(
            routineID: routine.id,
            name: routine.name,
            routineColorPreset: .orange
        )
        let missingRoutine = WorkoutSession(routineID: UUID(), name: "Deleted routine")

        context.insert(routine)
        context.insert(existingSnapshot)
        context.insert(missingRoutine)
        try context.save()

        #expect(try RoutineColorSnapshotBackfillService.backfill(in: context) == 0)
        #expect(existingSnapshot.routineColorPreset == .orange)
        #expect(missingRoutine.routineColorPreset == nil)
    }
}
