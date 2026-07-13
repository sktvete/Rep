import Foundation

protocol OneRepMaxFormula: Sendable {
    func estimate(weight: Double, repetitions: Int) -> Double?
}

struct EpleyOneRepMaxFormula: OneRepMaxFormula {
    let maximumSuitableRepetitions: Int

    init(maximumSuitableRepetitions: Int = 15) {
        self.maximumSuitableRepetitions = maximumSuitableRepetitions
    }

    func estimate(weight: Double, repetitions: Int) -> Double? {
        guard weight > 0,
              repetitions > 0,
              repetitions <= maximumSuitableRepetitions else { return nil }
        if repetitions == 1 { return weight }
        return weight * (1 + Double(repetitions) / 30)
    }
}

struct RepetitionRecord: Equatable, Sendable {
    let weight: Double
    let repetitions: Int
}

struct PersonalRecords: Equatable, Sendable {
    var highestWeight: Double?
    var mostRepetitionsAtWeight: RepetitionRecord?
    var highestEstimatedOneRepMax: Double?
    var highestSetVolume: Double?
    var highestWorkoutVolume: Double?

    static let empty = PersonalRecords()
}

enum ProgressCalculator {
    static func estimatedOneRepMax(
        weight: Double?,
        repetitions: Int?,
        formula: any OneRepMaxFormula = EpleyOneRepMaxFormula()
    ) -> Double? {
        guard let weight, let repetitions else { return nil }
        return formula.estimate(weight: weight, repetitions: repetitions)
    }

    static func volume(weight: Double?, repetitions: Int?, measurementType: MeasurementType) -> Double? {
        guard measurementType.supportsExternalWeightVolume,
              let weight,
              weight >= 0,
              let repetitions,
              repetitions > 0 else { return nil }
        return weight * Double(repetitions)
    }

    static func personalRecords(for sessions: [WorkoutSession], exerciseID: UUID) -> PersonalRecords {
        var records = PersonalRecords.empty

        for session in sessions where session.state == .completed {
            var sessionVolume = 0.0
            var hasApplicableVolume = false

            for item in session.exercises where item.exercise?.id == exerciseID {
                guard let measurementType = item.exercise?.measurementType else { continue }
                for set in item.sets where set.isCompleted {
                    if let weight = set.weight, weight >= 0 {
                        records.highestWeight = max(records.highestWeight ?? weight, weight)
                    }

                    if let weight = set.weight, let repetitions = set.repetitions, repetitions > 0 {
                        let candidate = RepetitionRecord(weight: weight, repetitions: repetitions)
                        if isBetterRepetitionRecord(candidate, than: records.mostRepetitionsAtWeight) {
                            records.mostRepetitionsAtWeight = candidate
                        }
                    }

                    if measurementType == .weightAndRepetitions,
                       let estimate = estimatedOneRepMax(weight: set.weight, repetitions: set.repetitions) {
                        records.highestEstimatedOneRepMax = max(records.highestEstimatedOneRepMax ?? estimate, estimate)
                    }

                    if let setVolume = volume(
                        weight: set.weight,
                        repetitions: set.repetitions,
                        measurementType: measurementType
                    ) {
                        hasApplicableVolume = true
                        sessionVolume += setVolume
                        records.highestSetVolume = max(records.highestSetVolume ?? setVolume, setVolume)
                    }
                }
            }

            if hasApplicableVolume {
                records.highestWorkoutVolume = max(records.highestWorkoutVolume ?? sessionVolume, sessionVolume)
            }
        }
        return records
    }

    static func filter(
        sessions: [WorkoutSession],
        range: ProgressTimeRange,
        relativeTo referenceDate: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [WorkoutSession] {
        guard let start = range.startDate(relativeTo: referenceDate, calendar: calendar) else {
            return sessions.filter { ($0.completedAt ?? $0.startedAt) <= referenceDate }
        }
        return sessions.filter {
            let date = $0.completedAt ?? $0.startedAt
            return date >= start && date <= referenceDate
        }
    }

    static func weeklyStreak(
        sessions: [WorkoutSession],
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Int {
        let activeWeekStarts = Set(
            sessions
                .filter { $0.state == .completed }
                .compactMap { session -> Date? in
                    let date = session.completedAt ?? session.startedAt
                    return calendar.dateInterval(of: .weekOfYear, for: date)?.start
                }
        )
        guard !activeWeekStarts.isEmpty else { return 0 }
        guard var weekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start else {
            return 0
        }

        if !activeWeekStarts.contains(weekStart),
           let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) {
            weekStart = previousWeek
        }

        var streak = 0
        while activeWeekStarts.contains(weekStart) {
            streak += 1
            guard let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) else {
                break
            }
            weekStart = previousWeek
        }
        return streak
    }

    private static func isBetterRepetitionRecord(_ candidate: RepetitionRecord, than current: RepetitionRecord?) -> Bool {
        guard let current else { return true }
        if candidate.repetitions != current.repetitions { return candidate.repetitions > current.repetitions }
        return candidate.weight > current.weight
    }
}

extension ProgressTimeRange {
    var title: String { displayName }

    func startDate(
        relativeTo referenceDate: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date? {
        let component: DateComponents?
        switch self {
        case .thirtyDays: component = DateComponents(day: -30)
        case .ninetyDays: component = DateComponents(day: -90)
        case .sixMonths: component = DateComponents(month: -6)
        case .oneYear: component = DateComponents(year: -1)
        case .allTime: component = nil
        }
        return component.flatMap { calendar.date(byAdding: $0, to: referenceDate) }
    }

    func includes(
        _ date: Date,
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Bool {
        guard date <= referenceDate else { return false }
        guard let start = startDate(relativeTo: referenceDate, calendar: calendar) else { return true }
        return date >= start
    }
}
