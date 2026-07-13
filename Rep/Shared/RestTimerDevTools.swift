import Foundation

extension Notification.Name {
    static let devStartFiveSecondRestTimer = Notification.Name("RepDevStartFiveSecondRestTimer")
}

#if DEBUG
@MainActor
enum RestTimerDevTools {
    static let standaloneSessionID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    private static var completionTask: Task<Void, Never>?

    static func startFiveSecondTimer(hapticsEnabled: Bool) {
        completionTask?.cancel()

        let startedInWorkout = ActiveWorkoutRestTimerBridge.startIfRegistered()

        if !startedInWorkout {
            RestTimerLiveActivityManager.sync(
                sessionID: standaloneSessionID,
                endDate: Date().addingTimeInterval(5),
                remainingSeconds: 5,
                isPaused: false,
                nextExerciseName: "Development test"
            )
        }

        completionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }

            if !startedInWorkout {
                RestTimerLiveActivityManager.end(sessionID: standaloneSessionID)
            }

            if hapticsEnabled {
                await HapticFeedback.tripleBuzzAndWait()
            }
        }
    }
}
#endif

@MainActor
enum ActiveWorkoutRestTimerBridge {
    private static var startHandler: (() -> Void)?

    static func register(startHandler: @escaping () -> Void) {
        self.startHandler = startHandler
    }

    static func unregister() {
        startHandler = nil
    }

    static func startIfRegistered() -> Bool {
        guard let startHandler else { return false }
        startHandler()
        return true
    }
}
