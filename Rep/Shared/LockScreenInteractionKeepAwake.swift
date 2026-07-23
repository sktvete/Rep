import UIKit

/// Best-effort keep-awake while Live Activity intents run, and for the whole
/// in-app active workout.
///
/// Third-party Live Activities cannot keep the Lock Screen lit the way Now Playing
/// can, but when the app process wakes we still disable the idle timer so the phone
/// is less likely to sleep mid-adjustment if the display is already on.
@MainActor
enum LockScreenInteractionKeepAwake {
    private static var releaseTask: Task<Void, Never>?
    private static var workoutHoldCount = 0

    /// Called on every Lock Screen button. Re-arms a long hold so adjusting
    /// weight/reps between rests does not let auto-lock win.
    static func ping(holdSeconds: TimeInterval = 180) {
        UIApplication.shared.isIdleTimerDisabled = true
        releaseTask?.cancel()
        releaseTask = Task {
            try? await Task.sleep(for: .seconds(holdSeconds))
            guard !Task.isCancelled else { return }
            if workoutHoldCount == 0 {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    /// Keeps the screen awake for the duration of an on-screen active workout.
    static func beginWorkoutHold() {
        workoutHoldCount += 1
        UIApplication.shared.isIdleTimerDisabled = true
        releaseTask?.cancel()
        releaseTask = nil
    }

    static func endWorkoutHold() {
        workoutHoldCount = max(0, workoutHoldCount - 1)
        if workoutHoldCount == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
