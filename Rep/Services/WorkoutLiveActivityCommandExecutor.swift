import Foundation
import SwiftData

/// Keeps Lock Screen actions on Rep's workout store. The active workout view
/// can lend its ModelContext for immediate UI observation; App Intents fall
/// back to the same on-disk SwiftData store when the scene isn't resident.
@MainActor
enum WorkoutLiveActivityWorkoutCoordinator {
    private static var activeModelContext: ModelContext?
    private static var selectionHandler: ((UUID) -> Void)?
    private static var fallbackContainer: ModelContainer?

    static func register(
        modelContext: ModelContext,
        onSelectExercise: @escaping (UUID) -> Void
    ) {
        activeModelContext = modelContext
        selectionHandler = onSelectExercise
    }

    static func unregister() {
        activeModelContext = nil
        selectionHandler = nil
    }

    static func synchronize(
        session: WorkoutSession,
        selectedExerciseID: UUID?,
        preferredUnit: WeightUnit
    ) {
        guard session.state == .active,
              let target = WorkoutLiveActivityStateBuilder.currentTarget(
                in: session,
                selectedExerciseID: selectedExerciseID
              ) else { return }

        RestTimerLiveActivityManager.syncWorkout(
            sessionID: session.id,
            currentSet: WorkoutLiveActivityStateBuilder.snapshot(
                target,
                preferredUnit: preferredUnit
            ),
            nextExerciseName: WorkoutLiveActivityStateBuilder.followingLabel(
                after: target,
                in: session
            )
        )
    }

    /// Advances the Live Activity after an in-app completion. If there is no
    /// later set or exercise, this creates the additional set the user expects
    /// instead of cycling back to the workout's first exercise.
    static func advanceAfterCompletion(
        session: WorkoutSession,
        completedSetID: UUID,
        preferredUnit: WeightUnit
    ) {
        guard let completed = WorkoutLiveActivityStateBuilder.target(
            setID: completedSetID,
            in: session
        ) else { return }

        let next = WorkoutLiveActivityStateBuilder.nextTarget(
            after: completed,
            in: session
        ) ?? WorkoutLiveActivityStateBuilder.addAnotherSet(after: completed)
        session.updatedAt = .now
        selectExercise(next.exercise.id, sessionID: session.id)

        RestTimerLiveActivityManager.syncWorkout(
            sessionID: session.id,
            currentSet: WorkoutLiveActivityStateBuilder.snapshot(
                next,
                preferredUnit: preferredUnit
            ),
            nextExerciseName: WorkoutLiveActivityStateBuilder.followingLabel(
                after: next,
                in: session
            )
        )
    }

    static func end(sessionID: UUID) {
        RestTimerNotificationManager.cancel(sessionID: sessionID)
        RestTimerLiveActivityManager.end(sessionID: sessionID)
    }

    fileprivate static func contextForIntent() throws -> ModelContext {
        if let activeModelContext { return activeModelContext }
        if fallbackContainer == nil {
            let schema = Schema([
                Exercise.self,
                Routine.self,
                RoutineExercise.self,
                WorkoutSession.self,
                WorkoutExercise.self,
                WorkoutSet.self,
                BodyweightEntry.self,
                LearnedPattern.self,
                UserSettings.self
            ])
            fallbackContainer = try ModelContainer(for: schema)
        }
        return ModelContext(fallbackContainer!)
    }

    fileprivate static func selectExercise(_ exerciseID: UUID, sessionID: UUID) {
        UserDefaults.standard.set(
            exerciseID.uuidString,
            forKey: "active-workout-selection-\(sessionID.uuidString)"
        )
        selectionHandler?(exerciseID)
    }
}

@MainActor
enum WorkoutLiveActivityCommandExecutor {
    static func execute(_ command: WorkoutLiveActivityCommand) async throws {
        let identifiers = command.identifiers
        guard let sessionID = UUID(uuidString: identifiers.sessionID),
              let setID = UUID(uuidString: identifiers.setID) else { return }

        let context = try WorkoutLiveActivityWorkoutCoordinator.contextForIntent()
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        guard let session = try context.fetch(descriptor).first,
              session.state == .active,
              let target = WorkoutLiveActivityStateBuilder.target(
                setID: setID,
                in: session
              ) else {
            RestTimerLiveActivityManager.end(sessionID: sessionID)
            return
        }

        let settings = try context.fetch(FetchDescriptor<UserSettings>()).first
        let preferredUnit = settings?.preferredWeightUnit ?? .kilograms

        switch command {
        case let .adjustWeight(_, _, delta):
            guard !target.set.isCompleted else { return }
            adjustWeight(
                of: target,
                by: delta,
                preferredUnit: preferredUnit
            )
            session.updatedAt = .now
            try context.save()
            await synchronize(target: target, session: session, preferredUnit: preferredUnit)

        case let .adjustRepetitions(_, _, delta):
            guard !target.set.isCompleted else { return }
            let adjusted = max(0, (target.set.repetitions ?? 0) + delta)
            target.set.repetitions = adjusted == 0 ? nil : adjusted
            target.set.updatedAt = .now
            session.updatedAt = .now
            try context.save()
            await synchronize(target: target, session: session, preferredUnit: preferredUnit)

        case .completeSet:
            if !target.set.isCompleted {
                target.set.markCompleted()
                session.updatedAt = .now
            }

            let nextTarget = WorkoutLiveActivityStateBuilder.nextTarget(
                after: target,
                in: session
            ) ?? WorkoutLiveActivityStateBuilder.addAnotherSet(after: target)
            session.updatedAt = .now
            try context.save()

            WorkoutLiveActivityWorkoutCoordinator.selectExercise(
                nextTarget.exercise.id,
                sessionID: sessionID
            )
            await synchronize(
                target: nextTarget,
                session: session,
                preferredUnit: preferredUnit
            )

            let restSeconds = target.exercise.defaultRestSeconds
                ?? settings?.defaultRestSeconds
                ?? 90
            let nextLabel = WorkoutLiveActivityStateBuilder.targetLabel(nextTarget)
            if let endDate = await RestTimerLiveActivityManager.startRestFromIntent(
                sessionID: sessionID,
                seconds: restSeconds,
                nextExerciseName: nextLabel
            ) {
                RestTimerNotificationManager.schedule(sessionID: sessionID, at: endDate)
            }
        }
    }

    private static func adjustWeight(
        of target: WorkoutLiveActivityStateBuilder.Target,
        by delta: Double,
        preferredUnit: WeightUnit
    ) {
        let field = WorkoutLiveActivityStateBuilder.weightField(for: target.exercise)
        let kilograms: Double?
        switch field {
        case .weight:
            kilograms = target.set.weight
        case .assistance:
            kilograms = target.set.assistanceWeight
        }

        let displayed = kilograms.map {
            UnitConversion.weight($0, from: .kilograms, to: preferredUnit)
        } ?? 0
        let adjusted = max(0, displayed + delta)
        let adjustedKilograms = UnitConversion.weight(
            adjusted,
            from: preferredUnit,
            to: .kilograms
        )

        switch field {
        case .weight:
            target.set.weight = adjustedKilograms
        case .assistance:
            target.set.assistanceWeight = adjustedKilograms
        }
        target.set.updatedAt = .now
    }

    private static func synchronize(
        target: WorkoutLiveActivityStateBuilder.Target,
        session: WorkoutSession,
        preferredUnit: WeightUnit
    ) async {
        await RestTimerLiveActivityManager.syncWorkoutImmediately(
            sessionID: session.id,
            currentSet: WorkoutLiveActivityStateBuilder.snapshot(
                target,
                preferredUnit: preferredUnit
            ),
            nextExerciseName: WorkoutLiveActivityStateBuilder.followingLabel(
                after: target,
                in: session
            )
        )
    }
}

enum WorkoutLiveActivityStateBuilder {
    struct Target {
        let exercise: WorkoutExercise
        let set: WorkoutSet
    }

    static func target(setID: UUID, in session: WorkoutSession) -> Target? {
        for exercise in session.orderedExercises {
            if let set = exercise.orderedSets.first(where: { $0.id == setID }) {
                return Target(exercise: exercise, set: set)
            }
        }
        return nil
    }

    static func currentTarget(
        in session: WorkoutSession,
        selectedExerciseID: UUID?
    ) -> Target? {
        let exercises = session.orderedExercises
        guard !exercises.isEmpty else { return nil }
        let selectedIndex = selectedExerciseID
            .flatMap { id in exercises.firstIndex(where: { $0.id == id }) }
            ?? 0

        for exercise in exercises.suffix(from: selectedIndex) {
            if let set = exercise.orderedSets.first(where: { !$0.isCompleted }) {
                return Target(exercise: exercise, set: set)
            }
        }
        return nil
    }

    static func nextTarget(after target: Target, in session: WorkoutSession) -> Target? {
        let sets = target.exercise.orderedSets
        if let currentIndex = sets.firstIndex(where: { $0.id == target.set.id }) {
            for set in sets.suffix(from: min(currentIndex + 1, sets.endIndex))
            where !set.isCompleted {
                return Target(exercise: target.exercise, set: set)
            }
        }

        let exercises = session.orderedExercises
        guard let exerciseIndex = exercises.firstIndex(where: { $0.id == target.exercise.id }) else {
            return nil
        }
        for exercise in exercises.suffix(from: min(exerciseIndex + 1, exercises.endIndex)) {
            if let set = exercise.orderedSets.first(where: { !$0.isCompleted }) {
                return Target(exercise: exercise, set: set)
            }
        }
        return nil
    }

    static func followingLabel(after target: Target, in session: WorkoutSession) -> String {
        guard let following = nextTarget(after: target, in: session) else {
            let name = target.exercise.exercise?.name ?? "Exercise"
            return "\(name) · Another set"
        }
        return targetLabel(following)
    }

    static func targetLabel(_ target: Target) -> String {
        let name = target.exercise.exercise?.name ?? "Exercise"
        return "\(name) · Set \(target.set.orderIndex + 1)"
    }

    static func addAnotherSet(after target: Target) -> Target {
        let set = WorkoutCreationService().makeExtraSet(for: target.exercise)
        target.exercise.sets.append(set)
        target.exercise.normalizeSetOrder()
        return Target(exercise: target.exercise, set: set)
    }

    static func snapshot(_ target: Target, preferredUnit: WeightUnit) -> WorkoutLiveActivitySet {
        let exercise = target.exercise.exercise
        let measurement = exercise?.measurementType ?? .weightAndRepetitions
        let field = weightField(for: target.exercise)
        let kilograms = field == .assistance
            ? target.set.assistanceWeight
            : target.set.weight
        let displayedWeight = kilograms.map {
            UnitConversion.weight($0, from: .kilograms, to: preferredUnit)
        }

        return WorkoutLiveActivitySet(
            setID: target.set.id.uuidString,
            exerciseID: target.exercise.id.uuidString,
            exerciseName: exercise?.name ?? "Exercise",
            setNumber: target.set.orderIndex + 1,
            totalSetCount: target.exercise.sets.count,
            displayedWeight: displayedWeight,
            weightUnitSymbol: preferredUnit.symbol,
            repetitions: target.set.repetitions,
            supportsWeight: supportsWeight(measurement),
            supportsRepetitions: supportsRepetitions(measurement),
            weightStep: weightStep(for: exercise, preferredUnit: preferredUnit),
            weightField: field
        )
    }

    static func weightField(for exercise: WorkoutExercise) -> WorkoutLiveActivitySet.WeightField {
        exercise.exercise?.measurementType == .assistedBodyweight ? .assistance : .weight
    }

    private static func supportsWeight(_ measurement: MeasurementType) -> Bool {
        switch measurement {
        case .weightAndRepetitions, .weightAndDuration,
             .bodyweightPlusAddedWeight, .assistedBodyweight, .custom:
            true
        case .repetitionsOnly, .duration, .distanceAndDuration,
             .bodyweightAndRepetitions:
            false
        }
    }

    private static func supportsRepetitions(_ measurement: MeasurementType) -> Bool {
        switch measurement {
        case .weightAndRepetitions, .repetitionsOnly, .bodyweightAndRepetitions,
             .bodyweightPlusAddedWeight, .assistedBodyweight, .custom:
            true
        case .duration, .weightAndDuration, .distanceAndDuration:
            false
        }
    }

    private static func weightStep(for exercise: Exercise?, preferredUnit: WeightUnit) -> Double {
        if exercise?.primaryMuscleGroup == .shoulders {
            return preferredUnit == .kilograms ? 1 : 2.5
        }
        return 5
    }
}

private extension WorkoutLiveActivityCommand {
    var identifiers: (sessionID: String, setID: String) {
        switch self {
        case let .adjustWeight(sessionID, setID, _),
             let .adjustRepetitions(sessionID, setID, _),
             let .completeSet(sessionID, setID):
            (sessionID, setID)
        }
    }
}
