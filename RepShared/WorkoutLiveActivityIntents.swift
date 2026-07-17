import AppIntents
import Foundation

enum WorkoutLiveActivityCommand: Sendable {
    case adjustWeight(sessionID: String, setID: String, delta: Double)
    case adjustRepetitions(sessionID: String, setID: String, delta: Int)
    case completeSet(sessionID: String, setID: String)
    case completeAnotherSet(sessionID: String, setID: String)
    case toggleRestPause(sessionID: String)
    case adjustRest(sessionID: String, seconds: Int)
}

struct AdjustWorkoutWeightIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Adjust Workout Weight"
    static let description = IntentDescription("Adjusts the weight for the current workout set.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Set") var setID: String
    @Parameter(title: "Change") var delta: Double

    init() {}

    init(sessionID: String, setID: String, delta: Double) {
        self.sessionID = sessionID
        self.setID = setID
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        #if REP_APP
        try await WorkoutLiveActivityCommandExecutor.execute(
            .adjustWeight(sessionID: sessionID, setID: setID, delta: delta)
        )
        #endif
        return .result()
    }
}

struct AdjustWorkoutRepetitionsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Adjust Workout Repetitions"
    static let description = IntentDescription("Adjusts the repetitions for the current workout set.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Set") var setID: String
    @Parameter(title: "Change") var delta: Int

    init() {}

    init(sessionID: String, setID: String, delta: Int) {
        self.sessionID = sessionID
        self.setID = setID
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        #if REP_APP
        try await WorkoutLiveActivityCommandExecutor.execute(
            .adjustRepetitions(sessionID: sessionID, setID: setID, delta: delta)
        )
        #endif
        return .result()
    }
}

struct CompleteWorkoutSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Complete Workout Set"
    static let description = IntentDescription("Marks the current set complete and moves to the next set.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Set") var setID: String

    init() {}

    init(sessionID: String, setID: String) {
        self.sessionID = sessionID
        self.setID = setID
    }

    func perform() async throws -> some IntentResult {
        #if REP_APP
        try await WorkoutLiveActivityCommandExecutor.execute(
            .completeSet(sessionID: sessionID, setID: setID)
        )
        #endif
        return .result()
    }
}

struct CompleteAnotherWorkoutSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Another Set"
    static let description = IntentDescription(
        "Marks the current set complete and stays on the same exercise for another set."
    )
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Set") var setID: String

    init() {}

    init(sessionID: String, setID: String) {
        self.sessionID = sessionID
        self.setID = setID
    }

    func perform() async throws -> some IntentResult {
        #if REP_APP
        try await WorkoutLiveActivityCommandExecutor.execute(
            .completeAnotherSet(sessionID: sessionID, setID: setID)
        )
        #endif
        return .result()
    }
}

struct ToggleRestTimerPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Rest Timer"
    static let description = IntentDescription("Pauses or resumes the active rest timer.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Session") var sessionID: String

    init() {}

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func perform() async throws -> some IntentResult {
        #if REP_APP
        try await WorkoutLiveActivityCommandExecutor.execute(
            .toggleRestPause(sessionID: sessionID)
        )
        #endif
        return .result()
    }
}

struct AdjustRestTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Adjust Rest Timer"
    static let description = IntentDescription("Adds or removes time from the active rest timer.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Seconds") var seconds: Int

    init() {}

    init(sessionID: String, seconds: Int) {
        self.sessionID = sessionID
        self.seconds = seconds
    }

    func perform() async throws -> some IntentResult {
        #if REP_APP
        try await WorkoutLiveActivityCommandExecutor.execute(
            .adjustRest(sessionID: sessionID, seconds: seconds)
        )
        #endif
        return .result()
    }
}
