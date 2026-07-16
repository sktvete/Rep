import Foundation
import SwiftData
import WebKit

struct LegacyExerciseDBDataRemovalSummary: Equatable, Sendable {
    let convertedToBundledCatalog: Int
    let retainedCustomExercises: Int
    let clearedAmbiguousCustomNotes: Int
    let retainedUserReferences: Int
    let deletedUnreferencedExercises: Int
}

/// Removes catalog content that earlier builds persisted from ExerciseDB.
///
/// Exact-name matches are converted in place by ``BundledExerciseCatalogService``
/// before this migration runs. That preserves routine and workout relationships while
/// replacing their metadata with the licensed offline catalog. Remaining unreferenced
/// provider records are deleted. Referenced provider records keep relationships and
/// workout history, but their provider-derived names and metadata are replaced with a
/// neutral local placeholder.
@MainActor
enum LegacyExerciseDBDataRemovalService {
    static let unavailableLegacyExerciseName = "Unavailable legacy exercise"
    static let migrationKey = "rep.exerciseCatalog.removedExerciseDBData.v1"

    @discardableResult
    static func removeUnlicensedData(
        in context: ModelContext,
        defaults: UserDefaults = .standard,
        clearSharedCaches: Bool = true
    ) async throws -> LegacyExerciseDBDataRemovalSummary {
        guard !defaults.bool(forKey: migrationKey) else {
            return emptySummary
        }

        await clearProviderCheckpointsAndCaches(
            defaults: defaults,
            clearSharedCaches: clearSharedCaches
        )

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let legacy = exercises.filter(isLegacyExerciseDBRecord)
        guard !legacy.isEmpty else {
            defaults.set(true, forKey: migrationKey)
            return emptySummary
        }

        let routineExercises = try context.fetch(FetchDescriptor<RoutineExercise>())
        let workoutExercises = try context.fetch(FetchDescriptor<WorkoutExercise>())
        let referencedIDs = Set(
            routineExercises.compactMap { $0.exercise?.id }
                + workoutExercises.compactMap { $0.exercise?.id }
        )

        var convertedToBundledCatalog = 0
        var retainedCustomExercises = 0
        var clearedAmbiguousCustomNotes = 0
        var retainedUserReferences = 0
        var deletedUnreferencedExercises = 0

        do {
            for exercise in legacy {
                if exercise.isCustom {
                    let hadInstructions = !exercise.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    scrubProviderFields(from: exercise, clearAliases: true)
                    exercise.bundledCatalogID = nil
                    exercise.bundledCatalogVersion = nil
                    exercise.secondaryMuscleGroupRaws = []
                    exercise.touch()
                    retainedCustomExercises += 1
                    if hadInstructions {
                        clearedAmbiguousCustomNotes += 1
                    }
                } else if exercise.bundledCatalogID != nil,
                   exercise.bundledCatalogVersion != nil {
                    scrubProviderFields(from: exercise, clearAliases: false)
                    convertedToBundledCatalog += 1
                } else if ExerciseSeedService.restoreCuratedMetadataIfPresent(for: exercise) {
                    scrubProviderFields(from: exercise, clearAliases: false)
                    convertedToBundledCatalog += 1
                } else if referencedIDs.contains(exercise.id) {
                    scrubProviderFields(from: exercise, clearAliases: true)
                    exercise.name = Self.unavailableLegacyExerciseName
                    exercise.normalizedName = ExerciseNameNormalizer.normalize(Self.unavailableLegacyExerciseName)
                    exercise.bundledCatalogID = nil
                    exercise.bundledCatalogVersion = nil
                    exercise.isCustom = true
                    exercise.isArchived = true
                    exercise.primaryMuscleGroupRaw = MuscleGroup.other.rawValue
                    exercise.secondaryMuscleGroupRaws = []
                    exercise.equipmentRaw = Equipment.other.rawValue
                    exercise.measurementTypeRaw = MeasurementType.custom.rawValue
                    exercise.touch()
                    retainedUserReferences += 1
                } else {
                    context.delete(exercise)
                    deletedUnreferencedExercises += 1
                }
            }

            try context.save()
            defaults.set(true, forKey: migrationKey)
        } catch {
            context.rollback()
            throw error
        }

        return LegacyExerciseDBDataRemovalSummary(
            convertedToBundledCatalog: convertedToBundledCatalog,
            retainedCustomExercises: retainedCustomExercises,
            clearedAmbiguousCustomNotes: clearedAmbiguousCustomNotes,
            retainedUserReferences: retainedUserReferences,
            deletedUnreferencedExercises: deletedUnreferencedExercises
        )
    }

    private static var emptySummary: LegacyExerciseDBDataRemovalSummary {
        LegacyExerciseDBDataRemovalSummary(
            convertedToBundledCatalog: 0,
            retainedCustomExercises: 0,
            clearedAmbiguousCustomNotes: 0,
            retainedUserReferences: 0,
            deletedUnreferencedExercises: 0
        )
    }

    static func isLegacyExerciseDBRecord(_ exercise: Exercise) -> Bool {
        if exercise.externalCatalogID?.isEmpty == false { return true }
        if exercise.sourceName?.localizedCaseInsensitiveContains("ExerciseDB") == true { return true }
        if let value = exercise.sourceURLString,
           let host = URL(string: value)?.host?.lowercased(),
           host == "ascendapi.com" || host.hasSuffix(".ascendapi.com") {
            return true
        }
        guard let value = exercise.mediaURLString,
              let host = URL(string: value)?.host?.lowercased()
        else { return false }
        return host == "exercisedb.dev" || host.hasSuffix(".exercisedb.dev")
    }
}

private extension LegacyExerciseDBDataRemovalService {
    static func scrubProviderFields(from exercise: Exercise, clearAliases: Bool) {
        exercise.externalCatalogID = nil
        exercise.mediaURLString = nil
        exercise.instructions = ""
        exercise.sourceName = nil
        exercise.sourceURLString = nil
        if clearAliases {
            exercise.searchAliases = []
        }
        exercise.touch()
    }

    static func clearProviderCheckpointsAndCaches(
        defaults: UserDefaults,
        clearSharedCaches: Bool
    ) async {
        for suffix in [
            "isComplete",
            "nextCursor",
            "processedCount",
            "expectedCount",
            "storedRecordCount"
        ] {
            defaults.removeObject(forKey: "exerciseDB.catalog.v1.\(suffix)")
        }
        if clearSharedCaches {
            URLCache.shared.removeAllCachedResponses()

            let websiteDataStore = WKWebsiteDataStore.default()
            await withCheckedContinuation { continuation in
                websiteDataStore.removeData(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                    modifiedSince: .distantPast
                ) {
                    continuation.resume()
                }
            }
        }
    }
}
