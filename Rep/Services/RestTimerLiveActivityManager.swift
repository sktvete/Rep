import ActivityKit
import Foundation

enum RestTimerLiveActivityManager {
    private static let storagePrefix = "active-rest-timer-"
    private static let coordinator = Coordinator()

    static func reconcileOnLaunch() {
        Task {
            await coordinator.reconcileOnLaunch()
        }
    }

    static func sync(
        sessionID: UUID,
        endDate: Date?,
        remainingSeconds: Int,
        isPaused: Bool,
        nextExerciseName: String
    ) {
        Task {
            await coordinator.sync(
                sessionKey: sessionID.uuidString,
                endDate: endDate,
                remainingSeconds: remainingSeconds,
                isPaused: isPaused,
                nextExerciseName: nextExerciseName
            )
        }
    }

    static func end(sessionID: UUID) {
        Task {
            await coordinator.end(sessionKey: sessionID.uuidString)
        }
    }

    private actor Coordinator {
        func reconcileOnLaunch() async {
            var activeSessionIDs = Set<String>()

            for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
                guard key.hasPrefix(storagePrefix),
                      let values = value as? [String: Any] else { continue }

                let sessionKey = String(key.dropFirst(storagePrefix.count))
                guard !sessionKey.isEmpty else { continue }

                if let pausedSeconds = values["pausedRemainingSeconds"] as? Int, pausedSeconds > 0 {
                    activeSessionIDs.insert(sessionKey)
                    await sync(
                        sessionKey: sessionKey,
                        endDate: nil,
                        remainingSeconds: pausedSeconds,
                        isPaused: true,
                        nextExerciseName: values["nextExerciseName"] as? String ?? "Next exercise"
                    )
                    continue
                }

                if let timestamp = values["targetDate"] as? TimeInterval {
                    let endDate = Date(timeIntervalSince1970: timestamp)
                    let remaining = max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
                    if remaining > 0 {
                        activeSessionIDs.insert(sessionKey)
                        await sync(
                            sessionKey: sessionKey,
                            endDate: endDate,
                            remainingSeconds: remaining,
                            isPaused: false,
                            nextExerciseName: values["nextExerciseName"] as? String ?? "Next exercise"
                        )
                    } else {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                }
            }

            for activity in Activity<RestTimerAttributes>.activities {
                if !activeSessionIDs.contains(activity.attributes.sessionID) {
                    await endRestTimerActivity(activity)
                }
            }
        }

        func sync(
            sessionKey: String,
            endDate: Date?,
            remainingSeconds: Int,
            isPaused: Bool,
            nextExerciseName: String
        ) async {
            guard remainingSeconds > 0 else {
                await end(sessionKey: sessionKey)
                return
            }

            let content: ActivityContent<RestTimerAttributes.ContentState>
            if isPaused {
                content = ActivityContent(
                    state: RestTimerAttributes.ContentState(
                        timerInterval: Date()...Date(),
                        isPaused: true,
                        pausedRemainingSeconds: remainingSeconds,
                        nextExerciseName: nextExerciseName
                    ),
                    staleDate: nil
                )
            } else {
                guard let endDate else { return }
                let startDate = endDate.addingTimeInterval(-TimeInterval(remainingSeconds))
                content = ActivityContent(
                    state: RestTimerAttributes.ContentState(
                        timerInterval: startDate...endDate,
                        isPaused: false,
                        pausedRemainingSeconds: nil,
                        nextExerciseName: nextExerciseName
                    ),
                    staleDate: endDate
                )
            }

            if let activity = Self.activity(for: sessionKey) {
                await updateRestTimerActivity(activity, content: content)
                return
            }

            let attributes = RestTimerAttributes(sessionID: sessionKey)
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                await MainActor.run {
                    AppLog.timer.error(
                        "Live Activity start failed: \(String(describing: error), privacy: .public)"
                    )
                }
            }
        }

        func end(sessionKey: String) async {
            guard let activity = Self.activity(for: sessionKey) else { return }
            await endRestTimerActivity(activity)
        }

        private static func activity(for sessionID: String) -> Activity<RestTimerAttributes>? {
            Activity<RestTimerAttributes>.activities.first { $0.attributes.sessionID == sessionID }
        }
    }
}

private func updateRestTimerActivity(
    _ activity: Activity<RestTimerAttributes>,
    content: ActivityContent<RestTimerAttributes.ContentState>
) async {
    await activity.update(content)
}

private func endRestTimerActivity(_ activity: Activity<RestTimerAttributes>) async {
    await activity.end(nil, dismissalPolicy: .immediate)
}
