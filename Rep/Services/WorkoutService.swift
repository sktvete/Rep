import Foundation
import SwiftData

@MainActor
final class WorkoutService {
    private let context: ModelContext
    private let creationService: WorkoutCreationService
    private let restTimer: RestTimerService?
    private let defaultRestSeconds: Int

    init(
        context: ModelContext,
        restTimer: RestTimerService? = nil,
        defaultRestSeconds: Int = 90,
        creationService: WorkoutCreationService = WorkoutCreationService()
    ) {
        self.context = context
        self.restTimer = restTimer
        self.defaultRestSeconds = defaultRestSeconds
        self.creationService = creationService
    }

    func save() throws { try context.save() }

    func activeSession() throws -> WorkoutSession? {
        try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter { $0.state == .active }
            .max { $0.updatedAt < $1.updatedAt }
    }

    @discardableResult
    func startWorkout(from routine: Routine, at startedAt: Date = .now) throws -> WorkoutSession {
        let history = try context.fetch(FetchDescriptor<WorkoutSession>())
        let session = creationService.startWorkout(from: routine, previousSessions: history, startedAt: startedAt)
        context.insert(session)
        try context.save()
        return session
    }

    @discardableResult
    func startEmptyWorkout(name: String = "Workout", at startedAt: Date = .now) throws -> WorkoutSession {
        let session = creationService.startEmptyWorkout(name: name, startedAt: startedAt)
        context.insert(session)
        try context.save()
        return session
    }

    func completeSet(_ set: WorkoutSet, in exercise: WorkoutExercise, at date: Date = .now) throws {
        set.markCompleted(at: date)
        exercise.session?.updatedAt = date
        try context.save()
        restTimer?.start(seconds: exercise.defaultRestSeconds ?? defaultRestSeconds)
    }

    func reopenSet(_ set: WorkoutSet, at date: Date = .now) throws {
        set.reopen(at: date)
        set.workoutExercise?.session?.updatedAt = date
        try context.save()
    }

    @discardableResult
    func addSet(to exercise: WorkoutExercise, at date: Date = .now) throws -> WorkoutSet {
        let set = creationService.makeExtraSet(for: exercise, createdAt: date)
        exercise.sets.append(set)
        exercise.session?.updatedAt = date
        try context.save()
        return set
    }

    func removeSet(_ set: WorkoutSet, from exercise: WorkoutExercise, at date: Date = .now) throws {
        exercise.sets.removeAll { $0.id == set.id }
        context.delete(set)
        exercise.normalizeSetOrder()
        exercise.session?.updatedAt = date
        try context.save()
    }

    @discardableResult
    func addExercise(
        _ exercise: Exercise,
        to session: WorkoutSession,
        defaultRestSeconds: Int? = nil,
        at date: Date = .now
    ) throws -> WorkoutExercise {
        let item = WorkoutExercise(
            exercise: exercise,
            orderIndex: session.exercises.count,
            defaultRestSeconds: defaultRestSeconds
        )
        session.exercises.append(item)
        session.updatedAt = date
        try context.save()
        return item
    }

    func replaceExercise(
        _ workoutExercise: WorkoutExercise,
        with exercise: Exercise,
        in session: WorkoutSession,
        at date: Date = .now
    ) throws {
        workoutExercise.substitutionForExerciseID = workoutExercise.exercise?.id
        workoutExercise.exercise = exercise
        session.updatedAt = date
        try context.save()
    }

    func reorderExercises(
        in session: WorkoutSession,
        fromOffsets: IndexSet,
        toOffset: Int,
        at date: Date = .now
    ) throws {
        let original = session.orderedExercises
        let moving = fromOffsets.sorted().compactMap { original.indices.contains($0) ? original[$0] : nil }
        guard !moving.isEmpty else { return }
        let remaining = original.enumerated().filter { !fromOffsets.contains($0.offset) }.map(\.element)
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        let destination = min(max(0, toOffset - removedBeforeDestination), remaining.count)
        var reordered = remaining
        reordered.insert(contentsOf: moving, at: destination)
        session.exercises = reordered
        session.normalizeExerciseOrder()
        session.updatedAt = date
        try context.save()
    }

    func finish(_ session: WorkoutSession, at date: Date = .now) throws {
        session.stateRaw = WorkoutState.completed.rawValue
        session.completedAt = date
        session.updatedAt = date
        restTimer?.skip()
        if let routineID = session.routineID,
           let routine = try context.fetch(FetchDescriptor<Routine>()).first(where: { $0.id == routineID }) {
            routine.lastPerformedAt = date
            routine.updatedAt = date
        }
        try context.save()
    }

    func abandon(_ session: WorkoutSession, at date: Date = .now) throws {
        session.stateRaw = WorkoutState.abandoned.rawValue
        session.completedAt = date
        session.updatedAt = date
        restTimer?.skip()
        try context.save()
    }
}
