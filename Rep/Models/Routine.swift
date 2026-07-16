import Foundation
import SwiftData

@Model
final class Routine {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var lastPerformedAt: Date?
    var isArchived: Bool
    // Optional so stores created before routine colors can migrate without a
    // custom schema stage. Existing routines resolve to the default below.
    var colorPresetRaw: String?
    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    var exercises: [RoutineExercise]

    var colorPreset: RoutineColorPreset {
        get { colorPresetRaw.flatMap(RoutineColorPreset.init(rawValue:)) ?? .blue }
        set {
            colorPresetRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var orderedExercises: [RoutineExercise] {
        exercises.sorted { lhs, rhs in
            lhs.orderIndex == rhs.orderIndex
                ? lhs.id.uuidString < rhs.id.uuidString
                : lhs.orderIndex < rhs.orderIndex
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        lastPerformedAt: Date? = nil,
        isArchived: Bool = false,
        colorPreset: RoutineColorPreset = .blue,
        exercises: [RoutineExercise] = []
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastPerformedAt = lastPerformedAt
        self.isArchived = isArchived
        colorPresetRaw = colorPreset.rawValue
        self.exercises = exercises
        normalizeExerciseOrder()
    }

    func appendExercise(_ routineExercise: RoutineExercise, at date: Date = .now) {
        routineExercise.orderIndex = exercises.count
        exercises.append(routineExercise)
        updatedAt = date
    }

    func removeExercise(id exerciseID: UUID, at date: Date = .now) {
        exercises.removeAll { $0.id == exerciseID }
        normalizeExerciseOrder()
        updatedAt = date
    }

    func normalizeExerciseOrder() {
        for (index, item) in orderedExercises.enumerated() { item.orderIndex = index }
    }
}

@Model
final class RoutineExercise {
    @Attribute(.unique) var id: UUID
    var exercise: Exercise?
    var orderIndex: Int
    var targetSetCount: Int
    var suggestedRepetitions: Int
    var defaultRestSeconds: Int
    var notes: String
    var supersetGroupIdentifier: UUID?
    var routine: Routine?

    init(
        id: UUID = UUID(),
        exercise: Exercise? = nil,
        orderIndex: Int = 0,
        targetSetCount: Int = 3,
        suggestedRepetitions: Int = 8,
        defaultRestSeconds: Int = 90,
        notes: String = "",
        supersetGroupIdentifier: UUID? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.orderIndex = orderIndex
        self.targetSetCount = max(1, targetSetCount)
        self.suggestedRepetitions = max(1, suggestedRepetitions)
        self.defaultRestSeconds = max(0, defaultRestSeconds)
        self.notes = notes
        self.supersetGroupIdentifier = supersetGroupIdentifier
    }
}
