import Foundation
import SwiftData
@testable import Rep

enum TestFixtures {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value + "T12:00:00Z")!
    }

    static func routine(_ name: String) -> Routine {
        Routine(name: name, createdAt: date("2025-01-01"))
    }

    static func completedSession(
        routine: Routine,
        at date: Date,
        exercises: [WorkoutExercise] = []
    ) -> WorkoutSession {
        WorkoutSession(
            routineID: routine.id,
            name: routine.name,
            startedAt: date,
            completedAt: calendar.date(byAdding: .hour, value: 1, to: date),
            state: .completed,
            exercises: exercises,
            createdAt: date,
            updatedAt: calendar.date(byAdding: .hour, value: 1, to: date)
        )
    }

    @MainActor
    static func container() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self,
            Routine.self,
            RoutineExercise.self,
            WorkoutSession.self,
            WorkoutExercise.self,
            WorkoutSet.self,
            BodyweightEntry.self,
            LearnedPattern.self,
            UserSettings.self
        ])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }
}
