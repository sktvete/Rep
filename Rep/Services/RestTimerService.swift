import Foundation
import Observation

@MainActor
@Observable
final class RestTimerService {
    private(set) var remainingSeconds = 0
    private(set) var isRunning = false
    private(set) var isPaused = false

    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let notifications: any NotificationService

    init(notifications: (any NotificationService)? = nil) {
        self.notifications = notifications ?? NoOpNotificationService()
    }

    deinit { ticker?.cancel() }

    func start(seconds: Int) {
        ticker?.cancel()
        guard seconds > 0 else { skip(); return }
        remainingSeconds = seconds
        isPaused = false
        isRunning = true
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        scheduleNotification(at: endDate!)
        startTicker()
    }

    func togglePause() {
        guard remainingSeconds > 0 else { return }
        if isPaused {
            isPaused = false
            isRunning = true
            endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
            scheduleNotification(at: endDate!)
            startTicker()
        } else {
            updateRemaining()
            isPaused = true
            isRunning = false
            endDate = nil
            ticker?.cancel()
            notifications.cancelRestTimerNotification()
        }
    }

    func adjust(seconds: Int) {
        let adjusted = max(0, remainingSeconds + seconds)
        guard adjusted > 0 else { skip(); return }
        remainingSeconds = adjusted
        if !isPaused {
            isRunning = true
            endDate = Date().addingTimeInterval(TimeInterval(adjusted))
            scheduleNotification(at: endDate!)
            startTicker()
        }
    }

    func adjust(by seconds: Int) { adjust(seconds: seconds) }

    func skip() {
        ticker?.cancel()
        ticker = nil
        endDate = nil
        remainingSeconds = 0
        isRunning = false
        isPaused = false
        notifications.cancelRestTimerNotification()
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.updateRemaining()
                if !self.isRunning { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func scheduleNotification(at date: Date) {
        do {
            try notifications.scheduleRestTimerEnd(at: date)
        } catch {
            AppLog.timer.error(
                "Notification scheduling failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func updateRemaining() {
        guard isRunning, let endDate else { return }
        remainingSeconds = max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
        if remainingSeconds == 0 {
            ticker?.cancel()
            ticker = nil
            self.endDate = nil
            isRunning = false
            isPaused = false
        }
    }
}
