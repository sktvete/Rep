import AppIntents
import Foundation

enum WorkoutLiveActivityCommand: Sendable {
    case adjustWeight(sessionID: String, setID: String, delta: Double)
    case adjustRepetitions(sessionID: String, setID: String, delta: Int)
    case completeSet(sessionID: String, setID: String)
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
    static let description = IntentDescription("Marks the current workout set as complete.")
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
