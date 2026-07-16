import Foundation
import SwiftData

struct ExerciseCatalogDeduplicationSummary: Equatable, Sendable {
    var repairedNormalizedNames = 0
    var deletedRecords = 0
    var archivedRecords = 0
    var reassignedRoutineItems = 0
    var reassignedWorkoutItems = 0
    var repairedSubstitutionReferences = 0
    var mergedMetadataRecords = 0

    var didChange: Bool {
        repairedNormalizedNames > 0
            || deletedRecords > 0
            || archivedRecords > 0
            || reassignedRoutineItems > 0
            || reassignedWorkoutItems > 0
            || repairedSubstitutionReferences > 0
            || mergedMetadataRecords > 0
    }
}

/// Reconciles duplicates without breaking routine or workout history.
///
/// Provider records with distinct stable IDs are archived, rather than deleted, so a
/// later catalog sync recognizes them and does not insert them again. Records whose
/// provider identity is preserved by the winner are deleted after every reference is
/// moved to that winner.
@MainActor
enum ExerciseCatalogDeduplicationService {
    @discardableResult
    static func reconcile(
        in context: ModelContext,
        saveChanges: Bool = true
    ) throws -> ExerciseCatalogDeduplicationSummary {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let routineItems = try context.fetch(FetchDescriptor<RoutineExercise>())
        let workoutItems = try context.fetch(FetchDescriptor<WorkoutExercise>())
        var summary = ExerciseCatalogDeduplicationSummary()

        for exercise in exercises {
            let repaired = ExerciseNameNormalizer.normalize(exercise.name)
            guard exercise.normalizedName != repaired else { continue }
            exercise.normalizedName = repaired
            exercise.touch()
            summary.repairedNormalizedNames += 1
        }

        let eligible = exercises.filter {
            !$0.isCustom && $0.name != LegacyExerciseDBDataRemovalService.unavailableLegacyExerciseName
        }
        let usage = Dictionary(grouping: workoutItems.compactMap { item in
            item.exercise.map { ($0.id, item) }
        }, by: \.0).mapValues(\.count)

        for group in ExerciseCatalogIdentity.duplicateGroups(in: eligible) where group.count > 1 {
            guard let winner = group.reduce(nil as Exercise?, { current, candidate in
                guard let current else { return candidate }
                return ExerciseCatalogIdentity.preferred(candidate, over: current, usage: usage)
                    ? candidate
                    : current
            }) else { continue }

            for loser in group where loser.id != winner.id {
                if mergeMetadata(from: loser, into: winner) {
                    summary.mergedMetadataRecords += 1
                }

                for item in routineItems where item.exercise?.id == loser.id {
                    item.exercise = winner
                    summary.reassignedRoutineItems += 1
                }
                for item in workoutItems {
                    if item.exercise?.id == loser.id {
                        item.exercise = winner
                        summary.reassignedWorkoutItems += 1
                    }
                    if item.substitutionForExerciseID == loser.id {
                        item.substitutionForExerciseID = winner.id
                        summary.repairedSubstitutionReferences += 1
                    }
                }

                if mustRetainProviderIdentity(of: loser, winner: winner) {
                    if !loser.isArchived {
                        loser.isArchived = true
                        loser.touch()
                        summary.archivedRecords += 1
                    }
                } else {
                    context.delete(loser)
                    summary.deletedRecords += 1
                }
            }
        }

        if saveChanges, summary.didChange {
            try context.save()
        }
        return summary
    }
}

private extension ExerciseCatalogDeduplicationService {
    static func mergeMetadata(from source: Exercise, into target: Exercise) -> Bool {
        var changed = false

        func copyIfMissing(_ keyPath: ReferenceWritableKeyPath<Exercise, String?>) {
            let targetValue = target[keyPath: keyPath]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceValue = source[keyPath: keyPath]?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard targetValue?.isEmpty != false, let sourceValue, !sourceValue.isEmpty else { return }
            target[keyPath: keyPath] = sourceValue
            changed = true
        }

        copyIfMissing(\.videoAssetIdentifier)
        copyIfMissing(\.helpYouTubeVideoID)
        copyIfMissing(\.helpVideoTitle)
        copyIfMissing(\.helpVideoChannel)
        copyIfMissing(\.helpVideoVerifiedAt)
        copyIfMissing(\.bundledCatalogID)
        copyIfMissing(\.bundledCatalogVersion)
        copyIfMissing(\.externalCatalogID)
        copyIfMissing(\.mediaURLString)
        copyIfMissing(\.sourceURLString)
        copyIfMissing(\.sourceName)

        if target.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !source.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target.instructions = source.instructions
            changed = true
        }

        let sourceNotes = source.userNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sourceNotes, !sourceNotes.isEmpty {
            let targetNotes = target.userNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
            if targetNotes?.isEmpty != false {
                target.userNotes = sourceNotes
                changed = true
            } else if targetNotes != sourceNotes, targetNotes?.contains(sourceNotes) != true {
                target.userNotes = [targetNotes, sourceNotes].compactMap { $0 }.joined(separator: "\n\n")
                changed = true
            }
        }

        var seenAliases = Set<String>()
        let aliases = (target.searchAliases + source.searchAliases).compactMap { alias -> String? in
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return seenAliases.insert(ExerciseNameNormalizer.normalize(trimmed)).inserted ? trimmed : nil
        }
        if aliases != target.searchAliases {
            target.searchAliases = aliases
            changed = true
        }

        if source.popularityRank < target.popularityRank {
            target.popularityRank = source.popularityRank
            changed = true
        }

        if changed { target.touch() }
        return changed
    }

    static func mustRetainProviderIdentity(of loser: Exercise, winner: Exercise) -> Bool {
        let loserExternal = loser.externalCatalogID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let winnerExternal = winner.externalCatalogID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let loserExternal, !loserExternal.isEmpty, loserExternal != winnerExternal {
            return true
        }

        let loserBundled = loser.bundledCatalogID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let winnerBundled = winner.bundledCatalogID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return loserBundled?.isEmpty == false && loserBundled != winnerBundled
    }
}
