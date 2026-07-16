import Foundation

/// Stable, conservative identity rules shared by catalog import and picker display.
///
/// Exact names ignore punctuation, so `bent-over` and `bent over` cannot become two
/// exercises. The semantic key additionally catches a small class of mechanically
/// equivalent source names without collapsing meaningful variants such as one-arm,
/// incline, reverse-grip, or seated movements.
enum ExerciseCatalogIdentity {
    static func deduplicated(
        _ exercises: [Exercise],
        usage: [UUID: Int] = [:]
    ) -> [Exercise] {
        let originalIndex = Dictionary(
            uniqueKeysWithValues: exercises.enumerated().map { ($0.element.id, $0.offset) }
        )
        return duplicateGroups(in: exercises)
            .compactMap { group -> (exercise: Exercise, position: Int)? in
                guard let winner = group.reduce(nil as Exercise?, { current, candidate in
                    guard let current else { return candidate }
                    return preferred(candidate, over: current, usage: usage) ? candidate : current
                }) else { return nil }
                return (winner, originalIndex[winner.id] ?? .max)
            }
            .sorted { $0.position < $1.position }
            .map { $0.exercise }
    }

    static func duplicateGroups(in exercises: [Exercise]) -> [[Exercise]] {
        guard !exercises.isEmpty else { return [] }

        var parents = Array(exercises.indices)

        func root(of index: Int) -> Int {
            var current = index
            while parents[current] != current {
                current = parents[current]
            }
            return current
        }

        func unite(_ lhs: Int, _ rhs: Int) {
            let leftRoot = root(of: lhs)
            let rightRoot = root(of: rhs)
            if leftRoot != rightRoot {
                parents[rightRoot] = leftRoot
            }
        }

        var firstIndexByKey: [String: Int] = [:]
        for (index, exercise) in exercises.enumerated() {
            for key in identityKeys(for: exercise) {
                if let first = firstIndexByKey[key] {
                    unite(index, first)
                } else {
                    firstIndexByKey[key] = index
                }
            }
        }

        var grouped: [Int: [Exercise]] = [:]
        var firstPosition: [Int: Int] = [:]
        for (index, exercise) in exercises.enumerated() {
            let groupRoot = root(of: index)
            grouped[groupRoot, default: []].append(exercise)
            firstPosition[groupRoot] = min(firstPosition[groupRoot] ?? index, index)
        }
        return grouped
            .sorted { (firstPosition[$0.key] ?? .max) < (firstPosition[$1.key] ?? .max) }
            .map { $0.value }
    }

    static func preferred(
        _ lhs: Exercise,
        over rhs: Exercise,
        usage: [UUID: Int] = [:]
    ) -> Bool {
        if lhs.isArchived != rhs.isArchived { return !lhs.isArchived }

        let lhsIsCurated = ExerciseSeedMediaOverrides.override(for: lhs) != nil
        let rhsIsCurated = ExerciseSeedMediaOverrides.override(for: rhs) != nil
        if lhsIsCurated != rhsIsCurated { return lhsIsCurated }

        let lhsUsage = usage[lhs.id] ?? 0
        let rhsUsage = usage[rhs.id] ?? 0
        if lhsUsage != rhsUsage { return lhsUsage > rhsUsage }

        let lhsHasMedia = hasMedia(lhs)
        let rhsHasMedia = hasMedia(rhs)
        if lhsHasMedia != rhsHasMedia { return lhsHasMedia }

        let lhsIsBundled = lhs.bundledCatalogID?.isEmpty == false
        let rhsIsBundled = rhs.bundledCatalogID?.isEmpty == false
        if lhsIsBundled != rhsIsBundled { return lhsIsBundled }

        if lhs.popularityRank != rhs.popularityRank {
            return lhs.popularityRank < rhs.popularityRank
        }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private extension ExerciseCatalogIdentity {
    static let ignoredSemanticTokens: Set<String> = [
        "a", "an", "attachment", "barbell", "body", "bodyweight", "cable",
        "dumbbell", "kettlebell", "lever", "machine", "only", "the", "two", "with",
    ]

    static let singularTokens: [String: String] = [
        "biceps": "bicep",
        "curls": "curl",
        "dumbbells": "dumbbell",
        "extensions": "extension",
        "presses": "press",
        "raises": "raise",
        "rows": "row",
    ]

    static func identityKeys(for exercise: Exercise) -> [String] {
        guard !exercise.isCustom else { return ["custom:\(exercise.id.uuidString)"] }

        let exactName = ExerciseNameNormalizer.normalize(exercise.name)
        guard !exactName.isEmpty else { return ["exercise:\(exercise.id.uuidString)"] }

        var keys = ["name:\(exactName)"]
        let semanticTokens = exactName
            .split(separator: " ")
            .map(String.init)
            .map { singularTokens[$0] ?? $0 }
            .filter { !ignoredSemanticTokens.contains($0) }
            .sorted()
        if !semanticTokens.isEmpty {
            keys.append(
                "movement:\(exercise.primaryMuscleGroupRaw):\(exercise.equipmentRaw):\(semanticTokens.joined(separator: " "))"
            )
        }

        if let externalID = exercise.externalCatalogID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !externalID.isEmpty {
            keys.append("external:\(externalID)")
        }
        if let override = ExerciseSeedMediaOverrides.override(for: exercise) {
            keys.append("external:\(override.catalogExerciseID)")
        }
        return keys
    }

    static func hasMedia(_ exercise: Exercise) -> Bool {
        exercise.mediaURLString?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || exercise.videoAssetIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
