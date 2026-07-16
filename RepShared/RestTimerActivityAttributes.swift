import ActivityKit
import Foundation

struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var timerInterval: ClosedRange<Date>
        var isPaused: Bool
        var pausedRemainingSeconds: Int?
        var nextExerciseName: String
        var isResting: Bool
        var currentSet: WorkoutLiveActivitySet?
    }

    var sessionID: String
}

/// The compact set snapshot rendered by the Live Activity. Keeping it in the
/// ActivityKit state lets a Lock Screen intent update immediately without
/// loading the workout database inside the widget extension.
struct WorkoutLiveActivitySet: Codable, Hashable, Sendable {
    enum WeightField: String, Codable, Hashable, Sendable {
        case weight
        case assistance
    }

    var setID: String
    var exerciseID: String
    var exerciseName: String
    var setNumber: Int
    var totalSetCount: Int
    var displayedWeight: Double?
    var weightUnitSymbol: String
    var repetitions: Int?
    var supportsWeight: Bool
    var supportsRepetitions: Bool
    var weightStep: Double
    var weightField: WeightField

    var setLabel: String {
        "Set \(setNumber) of \(max(setNumber, totalSetCount))"
    }
}

enum RestTimerLiveActivityFormatting {
    static func clock(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let remainder = max(0, seconds) % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
