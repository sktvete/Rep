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
        /// Bumped when a set is logged from Lock Screen so the widget can animate.
        var loggedConfirmationID: Int
        var showsLoggedConfirmation: Bool

        init(
            timerInterval: ClosedRange<Date>,
            isPaused: Bool,
            pausedRemainingSeconds: Int?,
            nextExerciseName: String,
            isResting: Bool,
            currentSet: WorkoutLiveActivitySet?,
            loggedConfirmationID: Int = 0,
            showsLoggedConfirmation: Bool = false
        ) {
            self.timerInterval = timerInterval
            self.isPaused = isPaused
            self.pausedRemainingSeconds = pausedRemainingSeconds
            self.nextExerciseName = nextExerciseName
            self.isResting = isResting
            self.currentSet = currentSet
            self.loggedConfirmationID = loggedConfirmationID
            self.showsLoggedConfirmation = showsLoggedConfirmation
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            timerInterval = try container.decode(ClosedRange<Date>.self, forKey: .timerInterval)
            isPaused = try container.decode(Bool.self, forKey: .isPaused)
            pausedRemainingSeconds = try container.decodeIfPresent(Int.self, forKey: .pausedRemainingSeconds)
            nextExerciseName = try container.decode(String.self, forKey: .nextExerciseName)
            isResting = try container.decode(Bool.self, forKey: .isResting)
            currentSet = try container.decodeIfPresent(WorkoutLiveActivitySet.self, forKey: .currentSet)
            loggedConfirmationID = try container.decodeIfPresent(Int.self, forKey: .loggedConfirmationID) ?? 0
            showsLoggedConfirmation = try container.decodeIfPresent(Bool.self, forKey: .showsLoggedConfirmation) ?? false
        }
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
