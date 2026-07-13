import Foundation
import Observation

struct ExerciseProgressPoint: Identifiable, Equatable {
    let sessionID: UUID
    let date: Date
    let estimatedOneRepMax: Double?
    let bestWeight: Double?
    let completedSetCount: Int

    var id: UUID { sessionID }
}

struct ExerciseProgressMetrics: Equatable {
    var bestWeight: Double?
    var bestRepetitions: Int?
    var bestEstimatedOneRepMax: Double?
    var totalSets: Int = 0
    var sessionsInRange: Int = 0
    var recentChangeDescription: String = "—"
    var latestPerformance: ExerciseProgressPoint?
    var previousPerformance: ExerciseProgressPoint?

    static let empty = ExerciseProgressMetrics()
}

/// Cached progress calculations for the exercise chart screen.
///
/// The view previously scanned every catalog exercise against every session on each
/// render. This model rebuilds only when inputs change.
@MainActor
@Observable
final class ExerciseProgressModel {
    private(set) var availableExercises: [Exercise] = []
    private(set) var points: [ExerciseProgressPoint] = []
    private(set) var metrics: ExerciseProgressMetrics = .empty

    private var catalogSignature: UInt64 = 0

    func update(
        sessions: [WorkoutSession],
        selectedExerciseID: UUID?,
        timeRange: ProgressTimeRange,
        preferredUnit: WeightUnit,
        referenceDate: Date = .now
    ) {
        let completed = sessions.filter { $0.state == .completed }
        let signature = catalogSignature(for: completed)
        if signature != catalogSignature {
            availableExercises = Self.availableExercises(in: completed)
            catalogSignature = signature
        }

        let resolvedID = selectedExerciseID.flatMap { id in
            availableExercises.contains(where: { $0.id == id }) ? id : nil
        } ?? availableExercises.first?.id

        guard let exerciseID = resolvedID else {
            points = []
            metrics = .empty
            return
        }

        let rangedSessions = ProgressCalculator.filter(
            sessions: completed,
            range: timeRange,
            relativeTo: referenceDate
        )

        var newPoints: [ExerciseProgressPoint] = []
        var allSets: [WorkoutSet] = []
        newPoints.reserveCapacity(rangedSessions.count)

        for session in rangedSessions {
            let completedSets = session.exercises
                .filter { $0.exercise?.id == exerciseID }
                .flatMap(\.sets)
                .filter(\.isCompleted)
            guard !completedSets.isEmpty else { continue }

            allSets.append(contentsOf: completedSets)
            newPoints.append(
                ExerciseProgressPoint(
                    sessionID: session.id,
                    date: session.completedAt ?? session.startedAt,
                    estimatedOneRepMax: completedSets.compactMap(Self.estimatedOneRepMax).max(),
                    bestWeight: completedSets.compactMap(\.weight).max(),
                    completedSetCount: completedSets.count
                )
            )
        }

        newPoints.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.sessionID.uuidString < $1.sessionID.uuidString
        }

        let chartPoints = Self.dailyBestPoints(from: newPoints, calendar: .autoupdatingCurrent)
        points = chartPoints
        metrics = Self.metrics(
            from: allSets,
            chartPoints: chartPoints,
            sessionPoints: newPoints,
            preferredUnit: preferredUnit
        )
    }

    /// One chart point per calendar day using the best estimated 1RM that day.
    /// The point keeps the session timestamp so same-day workouts stay ordered by time.
    nonisolated static func dailyBestPoints(
        from sessionPoints: [ExerciseProgressPoint],
        calendar: Calendar
    ) -> [ExerciseProgressPoint] {
        var bestByDay: [Date: ExerciseProgressPoint] = [:]
        bestByDay.reserveCapacity(sessionPoints.count)

        for point in sessionPoints {
            let day = calendar.startOfDay(for: point.date)
            guard let existing = bestByDay[day] else {
                bestByDay[day] = point
                continue
            }

            let existingValue = existing.estimatedOneRepMax ?? existing.bestWeight ?? 0
            let candidateValue = point.estimatedOneRepMax ?? point.bestWeight ?? 0
            if candidateValue > existingValue {
                bestByDay[day] = point
            } else if candidateValue == existingValue, point.date > existing.date {
                bestByDay[day] = point
            }
        }

        return bestByDay.values.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.sessionID.uuidString < $1.sessionID.uuidString
        }
    }

    func resolvedSelection(for selectedExerciseID: UUID?) -> UUID? {
        if let selectedExerciseID,
           availableExercises.contains(where: { $0.id == selectedExerciseID }) {
            return selectedExerciseID
        }
        return availableExercises.first?.id
    }

    private static func availableExercises(in sessions: [WorkoutSession]) -> [Exercise] {
        var seen = Set<UUID>()
        var exercises: [Exercise] = []
        exercises.reserveCapacity(32)

        for session in sessions {
            for workoutExercise in session.exercises {
                guard let exercise = workoutExercise.exercise,
                      seen.insert(exercise.id).inserted else { continue }
                exercises.append(exercise)
            }
        }

        return exercises.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func metrics(
        from sets: [WorkoutSet],
        chartPoints: [ExerciseProgressPoint],
        sessionPoints: [ExerciseProgressPoint],
        preferredUnit: WeightUnit
    ) -> ExerciseProgressMetrics {
        let latestSession = sessionPoints.last
        let previousChart = chartPoints.count > 1 ? chartPoints[chartPoints.count - 2] : nil
        let latestChart = chartPoints.last

        var recentChange = "—"
        if let latestOneRepMax = latestChart?.estimatedOneRepMax,
           let previousOneRepMax = previousChart?.estimatedOneRepMax {
            let difference = latestOneRepMax - previousOneRepMax
            let displayDifference = UnitConversion.weight(difference, from: .kilograms, to: preferredUnit)
            let prefix = difference > 0 ? "+" : ""
            recentChange = "\(prefix)\(displayDifference.formatted(.number.precision(.fractionLength(0...1)))) \(preferredUnit.symbol)"
        }

        return ExerciseProgressMetrics(
            bestWeight: sets.compactMap(\.weight).max(),
            bestRepetitions: sets.compactMap(\.repetitions).max(),
            bestEstimatedOneRepMax: sets.compactMap(estimatedOneRepMax).max(),
            totalSets: sets.count,
            sessionsInRange: sessionPoints.count,
            recentChangeDescription: recentChange,
            latestPerformance: latestSession,
            previousPerformance: previousChart
        )
    }

    private static func estimatedOneRepMax(for set: WorkoutSet) -> Double? {
        ProgressCalculator.estimatedOneRepMax(weight: set.weight, repetitions: set.repetitions)
    }

    private func catalogSignature(for sessions: [WorkoutSession]) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(sessions.count)
        if let newest = sessions.max(by: { ($0.completedAt ?? $0.startedAt) < ($1.completedAt ?? $1.startedAt) }) {
            hasher.combine(newest.id)
            hasher.combine(newest.updatedAt)
        }
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }
}
