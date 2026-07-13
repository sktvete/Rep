import Foundation
import SwiftData

/// Counts how often each exercise appears in completed workouts.
@MainActor
enum ExerciseUsageService {
    private static var cached: [UUID: Int]?

    static func invalidateCache() {
        cached = nil
    }

    static func cachedCounts(in context: ModelContext) -> [UUID: Int] {
        if let cached { return cached }
        let counts = usageCounts(in: context)
        cached = counts
        return counts
    }

    static func usageCounts(in context: ModelContext) -> [UUID: Int] {
        let completedRaw = WorkoutState.completed.rawValue
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.stateRaw == completedRaw }
        )
        guard let sessions = try? context.fetch(descriptor) else { return [:] }

        var counts: [UUID: Int] = [:]
        for session in sessions {
            for workoutExercise in session.exercises {
                guard let id = workoutExercise.exercise?.id else { continue }
                counts[id, default: 0] += 1
            }
        }
        return counts
    }
}
