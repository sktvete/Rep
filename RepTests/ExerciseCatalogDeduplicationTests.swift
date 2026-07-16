import Foundation
import SwiftData
import Testing
@testable import Rep

@Suite("Exercise catalog deduplication", .serialized)
@MainActor
struct ExerciseCatalogDeduplicationTests {
    @Test("A normal rope curl stays distinct from a neutral-grip rope hammer curl")
    func preservesDistinctRopeCurlMovements() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let canonical = Exercise(
            name: "Rope Biceps Curl",
            primaryMuscleGroup: .biceps,
            equipment: .cable,
            searchAliases: ["Rope Bicep Curl"]
        )
        let providerDuplicate = Exercise(
            name: "Cable Hammer Curl (With Rope)",
            primaryMuscleGroup: .biceps,
            equipment: .cable,
            instructions: "Keep the upper arms still.",
            externalCatalogID: "HPlPoQA",
            mediaURLString: "https://static.exercisedb.dev/media/HPlPoQA.gif"
        )
        let routineItem = RoutineExercise(exercise: providerDuplicate)
        let routine = Routine(name: "Arms", exercises: [routineItem])
        let workoutItem = WorkoutExercise(
            exercise: canonical,
            substitutionForExerciseID: providerDuplicate.id
        )
        let workout = WorkoutSession(name: "Arms", exercises: [workoutItem])
        context.insert(canonical)
        context.insert(providerDuplicate)
        context.insert(routine)
        context.insert(workout)
        try context.save()

        let summary = try ExerciseCatalogDeduplicationService.reconcile(in: context)
        let remaining = try context.fetch(FetchDescriptor<Exercise>())

        #expect(remaining.count == 2)
        #expect(remaining.allSatisfy { !$0.isArchived })
        #expect(canonical.mediaURLString == nil)
        #expect(providerDuplicate.mediaURLString == "https://static.exercisedb.dev/media/HPlPoQA.gif")
        #expect(routineItem.exercise?.id == providerDuplicate.id)
        #expect(workoutItem.exercise?.id == canonical.id)
        #expect(workoutItem.substitutionForExerciseID == providerDuplicate.id)
        #expect(!summary.didChange)
    }

    @Test("Distinct provider IDs stay archived so sync cannot reinsert a visible duplicate")
    func archivesDistinctProviderIdentity() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let first = Exercise(
            name: "Cable Rope Overhead Triceps Extension",
            primaryMuscleGroup: .triceps,
            equipment: .cable,
            externalCatalogID: "provider-one",
            mediaURLString: "https://example.com/one.gif"
        )
        let second = Exercise(
            name: "Triceps Overhead Extension with Rope",
            primaryMuscleGroup: .triceps,
            equipment: .cable,
            externalCatalogID: "provider-two"
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let summary = try ExerciseCatalogDeduplicationService.reconcile(in: context)
        let remaining = try context.fetch(FetchDescriptor<Exercise>())

        #expect(remaining.count == 2)
        #expect(remaining.filter { !$0.isArchived }.count == 1)
        #expect(remaining.filter(\.isArchived).count == 1)
        #expect(summary.archivedRecords == 1)
    }
}
