import ActivityKit
import Foundation

struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var timerInterval: ClosedRange<Date>
        var isPaused: Bool
        var pausedRemainingSeconds: Int?
        var nextExerciseName: String
    }

    var sessionID: String
}

enum RestTimerLiveActivityFormatting {
    static func clock(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let remainder = max(0, seconds) % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
