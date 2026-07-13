import Foundation
import SwiftData

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var routineID: UUID?
    var name: String
    var startedAt: Date
    var completedAt: Date?
    var stateRaw: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.session)
    var exercises: [WorkoutExercise]

    var state: WorkoutState {
        get { WorkoutState(rawValue: stateRaw) ?? .planned }
        set { stateRaw = newValue.rawValue; updatedAt = .now }
    }

    var orderedExercises: [WorkoutExercise] {
        exercises.sorted { lhs, rhs in
            lhs.orderIndex == rhs.orderIndex
                ? lhs.id.uuidString < rhs.id.uuidString
                : lhs.orderIndex < rhs.orderIndex
        }
    }

    var duration: TimeInterval { duration(at: .now) }
    func duration(at date: Date) -> TimeInterval {
        max(0, (completedAt ?? date).timeIntervalSince(startedAt))
    }

    var completedSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
    }

    var totalVolume: Double {
        exercises.reduce(0) { $0 + $1.totalVolume }
    }

    init(
        id: UUID = UUID(),
        routineID: UUID? = nil,
        name: String,
        startedAt: Date = .now,
        completedAt: Date? = nil,
        state: WorkoutState = .active,
        notes: String = "",
        exercises: [WorkoutExercise] = [],
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.routineID = routineID
        self.name = name
        self.startedAt = startedAt
        self.completedAt = completedAt
        stateRaw = state.rawValue
        self.notes = notes
        let createdAt = createdAt ?? startedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.exercises = exercises
        normalizeExerciseOrder()
    }

    func normalizeExerciseOrder() {
        for (index, item) in orderedExercises.enumerated() { item.orderIndex = index }
    }
}

@Model
final class WorkoutExercise {
    @Attribute(.unique) var id: UUID
    var exercise: Exercise?
    var orderIndex: Int
    var notes: String
    var sourceRoutineExerciseID: UUID?
    var substitutionForExerciseID: UUID?
    var defaultRestSeconds: Int?
    var isSkipped: Bool
    var session: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workoutExercise)
    var sets: [WorkoutSet]

    var orderedSets: [WorkoutSet] {
        sets.sorted { lhs, rhs in
            lhs.orderIndex == rhs.orderIndex
                ? lhs.id.uuidString < rhs.id.uuidString
                : lhs.orderIndex < rhs.orderIndex
        }
    }

    var totalVolume: Double {
        guard exercise?.measurementType.supportsExternalWeightVolume == true else { return 0 }
        return sets.filter(\.isCompleted).compactMap(\.volume).reduce(0, +)
    }

    init(
        id: UUID = UUID(),
        exercise: Exercise? = nil,
        orderIndex: Int = 0,
        notes: String = "",
        sourceRoutineExerciseID: UUID? = nil,
        substitutionForExerciseID: UUID? = nil,
        defaultRestSeconds: Int? = nil,
        isSkipped: Bool = false,
        sets: [WorkoutSet] = []
    ) {
        self.id = id
        self.exercise = exercise
        self.orderIndex = orderIndex
        self.notes = notes
        self.sourceRoutineExerciseID = sourceRoutineExerciseID
        self.substitutionForExerciseID = substitutionForExerciseID
        self.defaultRestSeconds = defaultRestSeconds
        self.isSkipped = isSkipped
        self.sets = sets
        normalizeSetOrder()
    }

    func normalizeSetOrder() {
        for (index, item) in orderedSets.enumerated() { item.orderIndex = index }
    }
}

@Model
final class WorkoutSet {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var setTypeRaw: String
    var weight: Double?
    var repetitions: Int?
    var durationSeconds: Int?
    var distance: Double?
    var assistanceWeight: Double?
    var leftValue: Double?
    var rightValue: Double?
    var rpe: Double?
    var rir: Int?
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var workoutExercise: WorkoutExercise?

    var setType: WorkoutSetType {
        get { WorkoutSetType(rawValue: setTypeRaw) ?? .working }
        set { setTypeRaw = newValue.rawValue; updatedAt = .now }
    }

    var volume: Double? {
        guard let weight, weight >= 0, let repetitions, repetitions > 0 else { return nil }
        return weight * Double(repetitions)
    }

    init(
        id: UUID = UUID(),
        orderIndex: Int = 0,
        setType: WorkoutSetType = .working,
        weight: Double? = nil,
        repetitions: Int? = nil,
        durationSeconds: Int? = nil,
        distance: Double? = nil,
        assistanceWeight: Double? = nil,
        leftValue: Double? = nil,
        rightValue: Double? = nil,
        rpe: Double? = nil,
        rir: Int? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        setTypeRaw = setType.rawValue
        self.weight = weight
        self.repetitions = repetitions
        self.durationSeconds = durationSeconds
        self.distance = distance
        self.assistanceWeight = assistanceWeight
        self.leftValue = leftValue
        self.rightValue = rightValue
        self.rpe = rpe
        self.rir = rir
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    func markCompleted(at date: Date = .now) {
        isCompleted = true
        completedAt = date
        updatedAt = date
    }

    func reopen(at date: Date = .now) {
        isCompleted = false
        completedAt = nil
        updatedAt = date
    }
}
