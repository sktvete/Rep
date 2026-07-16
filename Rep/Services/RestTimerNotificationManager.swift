import Foundation
import UserNotifications

@MainActor
enum RestTimerNotificationManager {
    static let messages = [
        "Get back to work, champ!",
        "Rest complete. You’re ready for a strong set.",
        "You’ve got this—time to lift.",
        "Next set—make it count.",
        "Break complete. Back to the weights.",
        "Ready when you are. Let’s go!",
        "The bar is ready when you are.",
        "Deep breath. Strong set.",
        "Recovery complete. Power up.",
        "Your next set starts now.",
        "Back at it—stay sharp.",
        "Rested and ready. Go crush it.",
        "Time’s up. Bring your best form.",
        "Let’s keep the momentum rolling.",
        "You recovered. Now build on it.",
        "Next round. Same focus.",
        "You’re ready. Bring the effort.",
        "Reset complete. Get after it.",
        "Strong form. Strong finish. Go.",
        "Your next great set starts now.",
        "Rest finished. Lock in.",
        "One more great set is waiting.",
        "Back to business, legend.",
        "Energy restored. Put it to work.",
        "Rest complete—you’re ready to move!",
        "Your muscles are ready. Let’s go.",
        "Round two. Ring the bell.",
        "Set time. Make yourself proud.",
        "Break complete. Chase the next rep.",
        "Ready, steady, lift.",
        "Fresh set. Full intent.",
        "Time to earn those reps.",
        "Rest complete. Finish strong.",
        "The next win is one set away.",
        "Focus up. It’s lifting time.",
        "You’re recharged. Let’s work.",
        "Take your strength into the next set.",
        "Back on deck. Move with purpose.",
        "The timer says you’re ready. Let’s go.",
        "Champ mode: on."
    ]

    private static let center = UNUserNotificationCenter.current()
    private static var scheduledEndDates: [UUID: Date] = [:]

    static func schedule(sessionID: UUID, at endDate: Date) {
        let identifier = notificationIdentifier(for: sessionID)
        scheduledEndDates[sessionID] = endDate
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let message = messages.randomElement() ?? "Get back to work, champ!"
        Task {
            guard await canScheduleNotifications() else { return }
            guard scheduledEndDates[sessionID] == endDate else { return }

            let interval = endDate.timeIntervalSinceNow
            guard interval >= 1 else { return }

            let content = UNMutableNotificationContent()
            content.title = "Break’s over"
            content.body = message
            content.sound = .default
            content.threadIdentifier = "rest-timers"

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: interval,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                AppLog.timer.error(
                    "Rest notification scheduling failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    static func cancel(sessionID: UUID) {
        scheduledEndDates[sessionID] = nil
        center.removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(for: sessionID)]
        )
    }

    private static func notificationIdentifier(for sessionID: UUID) -> String {
        "rest-timer-\(sessionID.uuidString)"
    }

    private static func canScheduleNotifications() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                AppLog.timer.error(
                    "Notification permission request failed: \(String(describing: error), privacy: .public)"
                )
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}
