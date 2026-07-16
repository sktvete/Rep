import ActivityKit
import Foundation

enum RestTimerLiveActivityManager {
    private static let timerStoragePrefix = "active-rest-timer-"
    private static let workoutStoragePrefix = "active-workout-live-activity-"
    private static let coordinator = Coordinator()

    static func reconcileOnLaunch() {
        Task { await coordinator.reconcileOnLaunch() }
    }

    static func sync(
        sessionID: UUID,
        endDate: Date?,
        remainingSeconds: Int,
        isPaused: Bool,
        nextExerciseName: String
    ) {
        Task {
            await coordinator.syncTimer(
                sessionKey: sessionID.uuidString,
                endDate: endDate,
                remainingSeconds: remainingSeconds,
                isPaused: isPaused,
                nextExerciseName: nextExerciseName
            )
        }
    }

    static func syncWorkout(
        sessionID: UUID,
        currentSet: WorkoutLiveActivitySet,
        nextExerciseName: String
    ) {
        Task {
            await coordinator.syncWorkout(
                sessionKey: sessionID.uuidString,
                currentSet: currentSet,
                nextExerciseName: nextExerciseName
            )
        }
    }

    static func syncWorkoutImmediately(
        sessionID: UUID,
        currentSet: WorkoutLiveActivitySet,
        nextExerciseName: String
    ) async {
        await coordinator.syncWorkout(
            sessionKey: sessionID.uuidString,
            currentSet: currentSet,
            nextExerciseName: nextExerciseName
        )
    }

    /// Starts a rest period from an App Intent and writes the same persisted
    /// timer shape used by `WorkoutRestTimerViewModel`, so the in-app timer can
    /// take over without jumping when the app becomes active again.
    static func startRestFromIntent(
        sessionID: UUID,
        seconds: Int,
        nextExerciseName: String
    ) async -> Date? {
        await coordinator.startRestFromIntent(
            sessionKey: sessionID.uuidString,
            seconds: seconds,
            nextExerciseName: nextExerciseName
        )
    }

    static func clearRest(sessionID: UUID) {
        Task { await coordinator.clearRest(sessionKey: sessionID.uuidString) }
    }

    static func end(sessionID: UUID) {
        Task { await coordinator.end(sessionKey: sessionID.uuidString) }
    }

    private struct WorkoutRecord: Codable {
        var currentSet: WorkoutLiveActivitySet
        var nextExerciseName: String
    }

    private actor Coordinator {
        func reconcileOnLaunch() async {
            let defaults = UserDefaults.standard
            let values = defaults.dictionaryRepresentation()
            var activeSessionIDs = Set<String>()

            for (key, value) in values where key.hasPrefix(workoutStoragePrefix) {
                let sessionKey = String(key.dropFirst(workoutStoragePrefix.count))
                guard !sessionKey.isEmpty,
                      let data = value as? Data,
                      let record = try? JSONDecoder().decode(WorkoutRecord.self, from: data) else {
                    defaults.removeObject(forKey: key)
                    continue
                }

                activeSessionIDs.insert(sessionKey)
                await syncWorkout(
                    sessionKey: sessionKey,
                    currentSet: record.currentSet,
                    nextExerciseName: record.nextExerciseName
                )
            }

            for (key, value) in values where key.hasPrefix(timerStoragePrefix) {
                guard let timerValues = value as? [String: Any] else { continue }
                let sessionKey = String(key.dropFirst(timerStoragePrefix.count))
                guard !sessionKey.isEmpty else { continue }

                let nextName = timerValues["nextExerciseName"] as? String ?? "Next set"
                if let pausedSeconds = timerValues["pausedRemainingSeconds"] as? Int,
                   pausedSeconds > 0 {
                    activeSessionIDs.insert(sessionKey)
                    await syncTimer(
                        sessionKey: sessionKey,
                        endDate: nil,
                        remainingSeconds: pausedSeconds,
                        isPaused: true,
                        nextExerciseName: nextName
                    )
                    continue
                }

                if let timestamp = timerValues["targetDate"] as? TimeInterval {
                    let endDate = Date(timeIntervalSince1970: timestamp)
                    let remaining = max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
                    if remaining > 0 {
                        activeSessionIDs.insert(sessionKey)
                        await syncTimer(
                            sessionKey: sessionKey,
                            endDate: endDate,
                            remainingSeconds: remaining,
                            isPaused: false,
                            nextExerciseName: nextName
                        )
                    } else {
                        defaults.removeObject(forKey: key)
                        await clearRest(sessionKey: sessionKey)
                    }
                }
            }

            for activity in Activity<RestTimerAttributes>.activities
            where !activeSessionIDs.contains(activity.attributes.sessionID) {
                await endRestTimerActivity(activity)
            }
        }

        func syncTimer(
            sessionKey: String,
            endDate: Date?,
            remainingSeconds: Int,
            isPaused: Bool,
            nextExerciseName: String
        ) async {
            guard remainingSeconds > 0 else {
                await clearRest(sessionKey: sessionKey)
                return
            }

            let currentSet = workoutRecord(for: sessionKey)?.currentSet
            let content: ActivityContent<RestTimerAttributes.ContentState>
            if isPaused {
                content = ActivityContent(
                    state: RestTimerAttributes.ContentState(
                        timerInterval: Date()...Date(),
                        isPaused: true,
                        pausedRemainingSeconds: remainingSeconds,
                        nextExerciseName: nextExerciseName,
                        isResting: true,
                        currentSet: currentSet
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
                        nextExerciseName: nextExerciseName,
                        isResting: true,
                        currentSet: currentSet
                    ),
                    staleDate: endDate
                )
            }

            await upsertActivity(sessionKey: sessionKey, content: content)
        }

        func syncWorkout(
            sessionKey: String,
            currentSet: WorkoutLiveActivitySet,
            nextExerciseName: String
        ) async {
            storeWorkoutRecord(
                WorkoutRecord(currentSet: currentSet, nextExerciseName: nextExerciseName),
                sessionKey: sessionKey
            )

            if let timer = persistedTimer(for: sessionKey) {
                await syncTimer(
                    sessionKey: sessionKey,
                    endDate: timer.endDate,
                    remainingSeconds: timer.remainingSeconds,
                    isPaused: timer.isPaused,
                    nextExerciseName: timer.nextExerciseName
                )
                return
            }

            await upsertActivity(
                sessionKey: sessionKey,
                content: readyContent(currentSet: currentSet, nextExerciseName: nextExerciseName)
            )
        }

        func startRestFromIntent(
            sessionKey: String,
            seconds: Int,
            nextExerciseName: String
        ) async -> Date? {
            guard seconds > 0 else {
                UserDefaults.standard.removeObject(forKey: timerStoragePrefix + sessionKey)
                await clearRest(sessionKey: sessionKey)
                return nil
            }

            let endDate = Date().addingTimeInterval(TimeInterval(seconds))
            UserDefaults.standard.set(
                [
                    "targetDate": endDate.timeIntervalSince1970,
                    "nextExerciseName": nextExerciseName
                ],
                forKey: timerStoragePrefix + sessionKey
            )
            await syncTimer(
                sessionKey: sessionKey,
                endDate: endDate,
                remainingSeconds: seconds,
                isPaused: false,
                nextExerciseName: nextExerciseName
            )
            return endDate
        }

        func clearRest(sessionKey: String) async {
            UserDefaults.standard.removeObject(forKey: timerStoragePrefix + sessionKey)
            guard let record = workoutRecord(for: sessionKey) else {
                guard let activity = Self.activity(for: sessionKey) else { return }
                await endRestTimerActivity(activity)
                return
            }

            await upsertActivity(
                sessionKey: sessionKey,
                content: readyContent(
                    currentSet: record.currentSet,
                    nextExerciseName: record.nextExerciseName
                )
            )
        }

        func end(sessionKey: String) async {
            UserDefaults.standard.removeObject(forKey: workoutStoragePrefix + sessionKey)
            UserDefaults.standard.removeObject(forKey: timerStoragePrefix + sessionKey)
            guard let activity = Self.activity(for: sessionKey) else { return }
            await endRestTimerActivity(activity)
        }

        private func readyContent(
            currentSet: WorkoutLiveActivitySet,
            nextExerciseName: String
        ) -> ActivityContent<RestTimerAttributes.ContentState> {
            ActivityContent(
                state: RestTimerAttributes.ContentState(
                    timerInterval: Date()...Date(),
                    isPaused: false,
                    pausedRemainingSeconds: nil,
                    nextExerciseName: nextExerciseName,
                    isResting: false,
                    currentSet: currentSet
                ),
                staleDate: nil
            )
        }

        private func upsertActivity(
            sessionKey: String,
            content: ActivityContent<RestTimerAttributes.ContentState>
        ) async {
            if let activity = Self.activity(for: sessionKey) {
                await updateRestTimerActivity(activity, content: content)
                return
            }

            do {
                _ = try Activity.request(
                    attributes: RestTimerAttributes(sessionID: sessionKey),
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

        private func storeWorkoutRecord(_ record: WorkoutRecord, sessionKey: String) {
            guard let data = try? JSONEncoder().encode(record) else { return }
            UserDefaults.standard.set(data, forKey: workoutStoragePrefix + sessionKey)
        }

        private func workoutRecord(for sessionKey: String) -> WorkoutRecord? {
            guard let data = UserDefaults.standard.data(forKey: workoutStoragePrefix + sessionKey) else {
                return nil
            }
            return try? JSONDecoder().decode(WorkoutRecord.self, from: data)
        }

        private func persistedTimer(for sessionKey: String) -> (
            endDate: Date?,
            remainingSeconds: Int,
            isPaused: Bool,
            nextExerciseName: String
        )? {
            guard let values = UserDefaults.standard.dictionary(
                forKey: timerStoragePrefix + sessionKey
            ) else { return nil }

            let nextName = values["nextExerciseName"] as? String ?? "Next set"
            if let paused = values["pausedRemainingSeconds"] as? Int, paused > 0 {
                return (nil, paused, true, nextName)
            }
            guard let timestamp = values["targetDate"] as? TimeInterval else { return nil }
            let endDate = Date(timeIntervalSince1970: timestamp)
            let remaining = max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
            guard remaining > 0 else {
                UserDefaults.standard.removeObject(forKey: timerStoragePrefix + sessionKey)
                return nil
            }
            return (endDate, remaining, false, nextName)
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
