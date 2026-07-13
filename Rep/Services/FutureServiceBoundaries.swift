import Foundation

struct HealthBodyweightSample: Sendable, Equatable {
    let measuredAt: Date
    let weightKilograms: Double
}

protocol HealthDataService: Sendable {
    func bodyweightSamples(from startDate: Date?) async throws -> [HealthBodyweightSample]
    func exportWorkout(_ sessionID: UUID) async throws
}

struct NoOpHealthDataService: HealthDataService {
    func bodyweightSamples(from startDate: Date?) async throws -> [HealthBodyweightSample] { [] }
    func exportWorkout(_ sessionID: UUID) async throws {}
}

protocol CloudSyncService: Sendable {
    func synchronize() async throws
}

struct NoOpCloudSyncService: CloudSyncService {
    func synchronize() async throws {}
}

struct WorkoutImportPreview: Sendable, Equatable {
    let workoutCount: Int
    let exerciseNamesRequiringMapping: [String]
    let warnings: [String]
}

protocol WorkoutImportService: Sendable {
    func preview(data: Data) async throws -> WorkoutImportPreview
}

struct NoOpWorkoutImportService: WorkoutImportService {
    func preview(data: Data) async throws -> WorkoutImportPreview {
        WorkoutImportPreview(workoutCount: 0, exerciseNamesRequiringMapping: [], warnings: [])
    }
}

protocol ExerciseMediaService: Sendable {
    func localVideoURL(for assetIdentifier: String) async throws -> URL?
}

struct NoOpExerciseMediaService: ExerciseMediaService {
    func localVideoURL(for assetIdentifier: String) async throws -> URL? { nil }
}

@MainActor
protocol NotificationService {
    func scheduleRestTimerEnd(at date: Date) throws
    func cancelRestTimerNotification()
}

@MainActor
struct NoOpNotificationService: NotificationService {
    func scheduleRestTimerEnd(at date: Date) throws {}
    func cancelRestTimerNotification() {}
}
