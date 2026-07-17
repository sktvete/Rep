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

        let startedInWorkout = ActiveWorkoutRestTimerBridge.shared.startIfRegistered()

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
@Observable
final class ActiveWorkoutRestTimerBridge {
    static let shared = ActiveWorkoutRestTimerBridge()

    private(set) var presentedTimer: WorkoutRestTimerViewModel?
    private var startHandler: (() -> Void)?

    func register(
        timer: WorkoutRestTimerViewModel,
        startHandler: @escaping () -> Void
    ) {
        presentedTimer = timer
        self.startHandler = startHandler
    }

    func unregister(timer: WorkoutRestTimerViewModel) {
        if presentedTimer === timer {
            presentedTimer = nil
        }
        startHandler = nil
    }

    func startIfRegistered() -> Bool {
        guard let startHandler else { return false }
        startHandler()
        return true
    }
}
