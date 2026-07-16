import Foundation
import Observation

/// View-facing rest timer state. The target date is persisted so reopening the
/// active-workout screen restores the countdown instead of starting it over.
@MainActor
@Observable
final class WorkoutRestTimerViewModel {
    private(set) var targetDate: Date?
    private(set) var pausedRemainingSeconds: Int?
    private(set) var remainingSeconds = 0
    private(set) var completionCount = 0
    private(set) var isPresented = false
    private(set) var nextExerciseName = "Next exercise"

    @ObservationIgnored nonisolated(unsafe) private var ticker: Task<Void, Never>?
    private let sessionID: UUID
    private let storageKey: String

    var shouldPlayCompletionHaptic: () -> Bool = { true }

    init(sessionID: UUID) {
        self.sessionID = sessionID
        storageKey = "active-rest-timer-\(sessionID.uuidString)"
        restore()
    }

    deinit {
        ticker?.cancel()
    }

    var isActive: Bool { remainingSeconds > 0 }
    var isPaused: Bool { pausedRemainingSeconds != nil }

    func start(seconds: Int, nextExerciseName: String) {
        guard seconds > 0 else {
            skip()
            return
        }
        self.nextExerciseName = nextExerciseName.isEmpty ? "Next exercise" : nextExerciseName
        pausedRemainingSeconds = nil
        targetDate = Date().addingTimeInterval(TimeInterval(seconds))
        remainingSeconds = seconds
        isPresented = true
        persist()
        scheduleNotification()
        syncLiveActivity()
        startTicker()
    }

    func togglePause() {
        guard isActive else { return }
        if let pausedRemainingSeconds {
            self.pausedRemainingSeconds = nil
            targetDate = Date().addingTimeInterval(TimeInterval(pausedRemainingSeconds))
            persist()
            scheduleNotification()
            syncLiveActivity()
            startTicker()
        } else {
            pausedRemainingSeconds = remainingSeconds
            targetDate = nil
            persist()
            RestTimerNotificationManager.cancel(sessionID: sessionID)
            syncLiveActivity()
            ticker?.cancel()
        }
    }

    func adjust(by seconds: Int) {
        let adjusted = max(0, remainingSeconds + seconds)
        guard adjusted > 0 else {
            skip()
            return
        }

        remainingSeconds = adjusted
        if isPaused {
            pausedRemainingSeconds = adjusted
        } else {
            targetDate = Date().addingTimeInterval(TimeInterval(adjusted))
        }
        persist()
        scheduleNotification()
        syncLiveActivity()
    }

    func reconcileAfterForeground() {
        reloadPersistedTimerIfNeeded()

        if let pausedRemainingSeconds, pausedRemainingSeconds > 0 {
            remainingSeconds = pausedRemainingSeconds
            isPresented = true
            return
        }

        guard let targetDate else { return }

        remainingSeconds = max(0, Int(targetDate.timeIntervalSinceNow.rounded(.up)))
        if remainingSeconds == 0 {
            finishTimer()
        } else {
            isPresented = true
            startTicker()
        }
    }

    func skip(cancelNotification: Bool = true) {
        ticker?.cancel()
        targetDate = nil
        pausedRemainingSeconds = nil
        remainingSeconds = 0
        isPresented = false
        nextExerciseName = "Next exercise"
        UserDefaults.standard.removeObject(forKey: storageKey)
        if cancelNotification {
            RestTimerNotificationManager.cancel(sessionID: sessionID)
        }
        RestTimerLiveActivityManager.clearRest(sessionID: sessionID)
    }

    /// Ends the workout-level Live Activity as well as its current rest. Use
    /// this for finish/discard; `skip()` intentionally keeps set controls alive.
    func endWorkout() {
        ticker?.cancel()
        targetDate = nil
        pausedRemainingSeconds = nil
        remainingSeconds = 0
        isPresented = false
        nextExerciseName = "Next exercise"
        UserDefaults.standard.removeObject(forKey: storageKey)
        RestTimerNotificationManager.cancel(sessionID: sessionID)
        RestTimerLiveActivityManager.end(sessionID: sessionID)
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                updateRemainingTime()
                if remainingSeconds == 0 { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func updateRemainingTime() {
        guard let targetDate else { return }
        remainingSeconds = max(0, Int(targetDate.timeIntervalSinceNow.rounded(.up)))
        if remainingSeconds == 0 {
            finishTimer()
        }
    }

    private func finishTimer() {
        let isDevTest = nextExerciseName == "Development test"
        let playHaptic = shouldPlayCompletionHaptic() && !isDevTest
        completionCount += 1
        // The system notification is due at this same instant. Leave that request
        // alone so foreground sessions receive the banner as well as the haptic.
        skip(cancelNotification: false)
        guard playHaptic else { return }
        HapticFeedback.tripleBuzz()
    }

    private func persist() {
        var values: [String: Any] = [
            "nextExerciseName": nextExerciseName
        ]
        if let targetDate { values["targetDate"] = targetDate.timeIntervalSince1970 }
        if let pausedRemainingSeconds { values["pausedRemainingSeconds"] = pausedRemainingSeconds }
        UserDefaults.standard.set(values, forKey: storageKey)
    }

    private func restore() {
        guard let values = UserDefaults.standard.dictionary(forKey: storageKey) else { return }
        if let name = values["nextExerciseName"] as? String, !name.isEmpty {
            nextExerciseName = name
        }

        if let pausedSeconds = values["pausedRemainingSeconds"] as? Int, pausedSeconds > 0 {
            pausedRemainingSeconds = pausedSeconds
            remainingSeconds = pausedSeconds
            isPresented = true
            syncLiveActivity()
            return
        }

        if let timestamp = values["targetDate"] as? TimeInterval {
            let restoredTarget = Date(timeIntervalSince1970: timestamp)
            let seconds = max(0, Int(restoredTarget.timeIntervalSinceNow.rounded(.up)))
            if seconds > 0 {
                targetDate = restoredTarget
                remainingSeconds = seconds
                isPresented = true
                scheduleNotification()
                syncLiveActivity()
                startTicker()
            } else {
                skip()
            }
        }
    }

    private func reloadPersistedTimerIfNeeded() {
        guard let values = UserDefaults.standard.dictionary(forKey: storageKey) else { return }

        if let name = values["nextExerciseName"] as? String, !name.isEmpty {
            nextExerciseName = name
        }
        if let pausedSeconds = values["pausedRemainingSeconds"] as? Int, pausedSeconds > 0 {
            pausedRemainingSeconds = pausedSeconds
            targetDate = nil
            remainingSeconds = pausedSeconds
            isPresented = true
            return
        }
        if let timestamp = values["targetDate"] as? TimeInterval {
            pausedRemainingSeconds = nil
            targetDate = Date(timeIntervalSince1970: timestamp)
        }
    }

    private func syncLiveActivity() {
        RestTimerLiveActivityManager.sync(
            sessionID: sessionID,
            endDate: targetDate,
            remainingSeconds: remainingSeconds,
            isPaused: isPaused,
            nextExerciseName: nextExerciseName
        )
    }

    private func scheduleNotification() {
        guard let targetDate, !isPaused else {
            RestTimerNotificationManager.cancel(sessionID: sessionID)
            return
        }
        RestTimerNotificationManager.schedule(sessionID: sessionID, at: targetDate)
    }
}
