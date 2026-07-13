import Foundation
import SwiftData

@MainActor
final class DevelopmentSampleDataService {
    private static let marker = "[Rep development sample]"
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.context = context
        self.calendar = calendar
    }

    func generate(referenceDate: Date = .now) throws {
        guard try hasSampleData() == false else { return }
        _ = try ExerciseSeedService.seedIfNeeded(in: context)
        let allExercises = try context.fetch(FetchDescriptor<Exercise>())
        let byName = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.normalizedName, $0) })

        let push = makeRoutine(
            name: "Push",
            exerciseNames: ["Barbell Bench Press", "Incline Dumbbell Press", "Dumbbell Lateral Raise", "Triceps Pushdown"],
            exercises: byName
        )
        let pull = makeRoutine(
            name: "Pull",
            exerciseNames: ["Pull-Up", "Barbell Row", "Seated Cable Row", "Dumbbell Curl"],
            exercises: byName
        )
        let legs = makeRoutine(
            name: "Legs",
            exerciseNames: ["Back Squat", "Romanian Deadlift", "Leg Press", "Standing Calf Raise"],
            exercises: byName
        )
        [push, pull, legs].forEach(context.insert)

        let creator = WorkoutCreationService()
        for weeksAgo in stride(from: 6, through: 1, by: -1) {
            guard let weekAnchor = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: referenceDate),
                  let tuesday = nextWeekday(3, inWeekContaining: weekAnchor),
                  let wednesday = calendar.date(byAdding: .day, value: 1, to: tuesday),
                  let friday = calendar.date(byAdding: .day, value: 3, to: tuesday) else { continue }

            let pushSession = sampleSession(from: push, at: hour(18, on: tuesday), creator: creator, week: 7 - weeksAgo)
            let pullSession = sampleSession(from: pull, at: hour(18, on: wednesday), creator: creator, week: 7 - weeksAgo)
            let legsSession = sampleSession(from: legs, at: hour(11, on: friday), creator: creator, week: 7 - weeksAgo)
            [pushSession, pullSession, legsSession].forEach(context.insert)

            let bodyweightDate = hour(8, on: tuesday)
            context.insert(BodyweightEntry(
                measuredAt: bodyweightDate,
                weightKilograms: 78 + Double(7 - weeksAgo) * 0.2,
                notes: Self.marker,
                source: .manual,
                createdAt: bodyweightDate
            ))
        }

        let activeDate = calendar.date(byAdding: .hour, value: -1, to: referenceDate) ?? referenceDate
        let active = creator.startWorkout(from: push, previousSessions: [], startedAt: activeDate)
        active.notes = Self.marker
        if let firstSet = active.orderedExercises.first?.orderedSets.first {
            firstSet.markCompleted(at: calendar.date(byAdding: .minute, value: 5, to: activeDate) ?? activeDate)
        }
        context.insert(active)

        let settings: UserSettings
        if let existing = try context.fetch(FetchDescriptor<UserSettings>()).first {
            settings = existing
        } else {
            settings = UserSettings()
            context.insert(settings)
        }
        settings.hasGeneratedSampleData = true
        settings.updatedAt = referenceDate
        try context.save()
    }

    func clear() throws {
        for session in try context.fetch(FetchDescriptor<WorkoutSession>()) where session.notes == Self.marker {
            context.delete(session)
        }
        for routine in try context.fetch(FetchDescriptor<Routine>()) where routine.notes == Self.marker {
            context.delete(routine)
        }
        for entry in try context.fetch(FetchDescriptor<BodyweightEntry>()) where entry.notes == Self.marker {
            context.delete(entry)
        }
        if let settings = try context.fetch(FetchDescriptor<UserSettings>()).first {
            settings.hasGeneratedSampleData = false
            settings.updatedAt = .now
        }
        try context.save()
    }

    private func hasSampleData() throws -> Bool {
        try context.fetch(FetchDescriptor<Routine>()).contains { $0.notes == Self.marker }
    }

    private func makeRoutine(
        name: String,
        exerciseNames: [String],
        exercises: [String: Exercise]
    ) -> Routine {
        let items = exerciseNames.enumerated().compactMap { index, name -> RoutineExercise? in
            guard let exercise = exercises[ExerciseNameNormalizer.normalize(name)] else { return nil }
            return RoutineExercise(
                exercise: exercise,
                orderIndex: index,
                targetSetCount: 3,
                suggestedRepetitions: index == 0 ? 6 : 10,
                defaultRestSeconds: index < 2 ? 120 : 75
            )
        }
        return Routine(name: name, notes: Self.marker, exercises: items)
    }

    private func sampleSession(
        from routine: Routine,
        at date: Date,
        creator: WorkoutCreationService,
        week: Int
    ) -> WorkoutSession {
        let session = creator.startWorkout(from: routine, previousSessions: [], startedAt: date)
        session.notes = Self.marker
        for (exerciseIndex, item) in session.orderedExercises.enumerated() {
            for set in item.orderedSets {
                if item.exercise?.measurementType == .bodyweightAndRepetitions {
                    set.repetitions = 6 + week
                } else {
                    set.weight = 25 + Double(exerciseIndex * 10 + week * 2)
                }
                set.markCompleted(at: calendar.date(byAdding: .minute, value: 5 + set.orderIndex * 3, to: date) ?? date)
            }
        }
        session.stateRaw = WorkoutState.completed.rawValue
        session.completedAt = calendar.date(byAdding: .minute, value: 55, to: date)
        session.updatedAt = session.completedAt ?? date
        return session
    }

    private func nextWeekday(_ weekday: Int, inWeekContaining date: Date) -> Date? {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return calendar.nextDate(
            after: calendar.date(byAdding: .second, value: -1, to: start) ?? start,
            matching: DateComponents(weekday: weekday),
            matchingPolicy: .nextTime
        )
    }

    private func hour(_ hour: Int, on date: Date) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
    }
}
