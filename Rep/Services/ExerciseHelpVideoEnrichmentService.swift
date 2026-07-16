import Foundation
import SwiftData

struct ExerciseHelpVideoEnrichmentSummary: Equatable, Sendable {
    let catalogVersion: String
    let reviewedMappings: Int
    let updatedExercises: Int
    let skippedCustomExercises: Int
    let unmappedExercises: Int
}

@MainActor
enum ExerciseHelpVideoEnrichmentService {
    @discardableResult
    static func enrichAll(
        in context: ModelContext,
        catalog: ExerciseHelpVideoCatalog
    ) throws -> ExerciseHelpVideoEnrichmentSummary {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        var updatedExercises = 0
        var skippedCustomExercises = 0
        var unmappedExercises = 0

        for exercise in exercises {
            if exercise.isCustom {
                skippedCustomExercises += 1
                continue
            }
            if applyCatalogMapping(to: exercise, catalog: catalog) {
                updatedExercises += 1
            } else if exercise.helpYouTubeVideoID == nil {
                unmappedExercises += 1
            }
        }

        if updatedExercises > 0 {
            try context.save()
        }

        return ExerciseHelpVideoEnrichmentSummary(
            catalogVersion: catalog.payload.catalogVersion,
            reviewedMappings: catalog.mappedExerciseCount,
            updatedExercises: updatedExercises,
            skippedCustomExercises: skippedCustomExercises,
            unmappedExercises: unmappedExercises
        )
    }

    @discardableResult
    static func applyCatalogMapping(
        to exercise: Exercise,
        catalog: ExerciseHelpVideoCatalog
    ) -> Bool {
        guard !exercise.isCustom else { return false }
        guard let mapping = catalog.mapping(for: exercise) else {
            return clearHelpVideoMetadata(on: exercise)
        }
        return apply(mapping, to: exercise)
    }

    @discardableResult
    private static func apply(
        _ mapping: ExerciseHelpVideoMapping,
        to exercise: Exercise
    ) -> Bool {
        var changed = false
        changed = setIfChanged(exercise, \.helpYouTubeVideoID, mapping.youtubeVideoId) || changed
        changed = setIfChanged(exercise, \.helpVideoTitle, mapping.title) || changed
        changed = setIfChanged(exercise, \.helpVideoChannel, mapping.channel) || changed
        changed = setIfChanged(exercise, \.helpVideoVerifiedAt, mapping.verifiedAt) || changed
        if changed {
            exercise.touch()
        }
        return changed
    }

    @discardableResult
    private static func clearHelpVideoMetadata(on exercise: Exercise) -> Bool {
        var changed = false
        changed = setIfChanged(exercise, \.helpYouTubeVideoID, nil) || changed
        changed = setIfChanged(exercise, \.helpVideoTitle, nil) || changed
        changed = setIfChanged(exercise, \.helpVideoChannel, nil) || changed
        changed = setIfChanged(exercise, \.helpVideoVerifiedAt, nil) || changed
        if changed {
            exercise.touch()
        }
        return changed
    }

    private static func setIfChanged<T: Equatable>(
        _ exercise: Exercise,
        _ keyPath: ReferenceWritableKeyPath<Exercise, T>,
        _ value: T
    ) -> Bool {
        guard exercise[keyPath: keyPath] != value else { return false }
        exercise[keyPath: keyPath] = value
        return true
    }
}
