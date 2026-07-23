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
    static var cachedPreferredUnit: WeightUnit = .kilograms

    static func register(
        modelContext: ModelContext,
        onSelectExercise: @escaping (UUID) -> Void
    ) {
        activeModelContext = modelContext
        selectionHandler = onSelectExercise
        if let settings = try? modelContext.fetch(FetchDescriptor<UserSettings>()).first {
            cachedPreferredUnit = settings.preferredWeightUnit
        }
        // Warm the on-disk container so lock-screen intents skip cold start.
        if fallbackContainer == nil {
            fallbackContainer = try? ModelContainer(
                for: Schema([
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
            )
        }
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

    /// Syncs the Live Activity after an in-app completion. Stays on the current
    /// exercise — never auto-jumps to the next one.
    static func advanceAfterCompletion(
        session: WorkoutSession,
        completedSetID: UUID,
        preferredUnit: WeightUnit
    ) {
        guard let completed = WorkoutLiveActivityStateBuilder.target(
            setID: completedSetID,
            in: session
        ) else { return }

        cachedPreferredUnit = preferredUnit

        let focus: WorkoutLiveActivityStateBuilder.Target
        if let next = WorkoutLiveActivityStateBuilder.nextTargetOnSameExercise(after: completed) {
            WorkoutLiveActivityStateBuilder.prefillEmptyValues(on: next.set, from: completed.set)
            focus = next
        } else {
            focus = completed
        }
        session.updatedAt = .now

        RestTimerLiveActivityManager.syncWorkout(
            sessionID: session.id,
            currentSet: WorkoutLiveActivityStateBuilder.snapshot(
                focus,
                preferredUnit: preferredUnit
            ),
            nextExerciseName: WorkoutLiveActivityStateBuilder.followingLabel(
                after: focus,
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
        await MainActor.run {
            LockScreenInteractionKeepAwake.ping()
        }
        switch command {
        case let .toggleRestPause(sessionID):
            guard let sessionID = UUID(uuidString: sessionID) else { return }
            if let timer = ActiveWorkoutRestTimerBridge.shared.presentedTimer,
               timer.isPresented {
                timer.togglePause()
            } else {
                await RestTimerLiveActivityManager.togglePauseFromIntent(sessionID: sessionID)
            }
            return

        case let .adjustRest(sessionID, seconds):
            guard let sessionID = UUID(uuidString: sessionID) else { return }
            if let timer = ActiveWorkoutRestTimerBridge.shared.presentedTimer,
               timer.isPresented {
                timer.adjust(by: seconds)
            } else {
                await RestTimerLiveActivityManager.adjustFromIntent(
                    sessionID: sessionID,
                    by: seconds
                )
            }
            return

        case let .adjustWeight(sessionID, setID, delta):
            // Lock Screen first, then persist — intents feel snappy that way.
            if let sessionUUID = UUID(uuidString: sessionID) {
                await RestTimerLiveActivityManager.applyWeightDeltaFromIntent(
                    sessionID: sessionUUID,
                    setID: setID,
                    delta: delta
                )
            }
            try await mutateSet(sessionID: sessionID, setID: setID) { target, session, preferredUnit, context in
                guard !target.set.isCompleted else { return }
                adjustWeight(of: target, by: delta, preferredUnit: preferredUnit)
                session.updatedAt = .now
                // Skip a second ActivityKit round-trip — optimistic paint already ran.
                try context.save()
            }

        case let .adjustRepetitions(sessionID, setID, delta):
            // Lock Screen first, then persist — intents feel snappy that way.
            if let sessionUUID = UUID(uuidString: sessionID) {
                await RestTimerLiveActivityManager.applyRepetitionsDeltaFromIntent(
                    sessionID: sessionUUID,
                    setID: setID,
                    delta: delta
                )
            }
            try await mutateSet(sessionID: sessionID, setID: setID) { target, session, preferredUnit, context in
                guard !target.set.isCompleted else { return }
                let adjusted = max(0, (target.set.repetitions ?? 0) + delta)
                target.set.repetitions = adjusted == 0 ? nil : adjusted
                target.set.updatedAt = .now
                session.updatedAt = .now
                try context.save()
            }

        case let .completeSet(sessionID, setID):
            try await complete(
                sessionID: sessionID,
                setID: setID,
                preferSameExercise: false
            )

        case let .completeAnotherSet(sessionID, setID):
            try await complete(
                sessionID: sessionID,
                setID: setID,
                preferSameExercise: true
            )
        }
    }

    private static func mutateSet(
        sessionID: String,
        setID: String,
        body: @MainActor (
            WorkoutLiveActivityStateBuilder.Target,
            WorkoutSession,
            WeightUnit,
            ModelContext
        ) async throws -> Void
    ) async throws {
        guard let sessionID = UUID(uuidString: sessionID),
              let setID = UUID(uuidString: setID) else { return }

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

        let preferredUnit = preferredUnit(in: context)
        try await body(target, session, preferredUnit, context)
    }

    private static func preferredUnit(in context: ModelContext) -> WeightUnit {
        if let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first {
            WorkoutLiveActivityWorkoutCoordinator.cachedPreferredUnit = settings.preferredWeightUnit
            return settings.preferredWeightUnit
        }
        return WorkoutLiveActivityWorkoutCoordinator.cachedPreferredUnit
    }

    private static func complete(
        sessionID: String,
        setID: String,
        preferSameExercise: Bool
    ) async throws {
        guard let sessionUUID = UUID(uuidString: sessionID),
              let setUUID = UUID(uuidString: setID) else { return }

        let context = try WorkoutLiveActivityWorkoutCoordinator.contextForIntent()
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == sessionUUID }
        )
        guard let session = try context.fetch(descriptor).first,
              session.state == .active,
              let target = WorkoutLiveActivityStateBuilder.target(
                setID: setUUID,
                in: session
              ) else {
            RestTimerLiveActivityManager.end(sessionID: sessionUUID)
            return
        }

        let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first
        let preferredUnit = settings?.preferredWeightUnit
            ?? WorkoutLiveActivityWorkoutCoordinator.cachedPreferredUnit
        if let settings {
            WorkoutLiveActivityWorkoutCoordinator.cachedPreferredUnit = settings.preferredWeightUnit
        }

        if !target.set.isCompleted {
            target.set.markCompleted()
            session.updatedAt = .now
        }

        // Another: stay on exercise and append when needed.
        // Next: advance to next incomplete target, or append when nothing remains.
        let focus = WorkoutLiveActivityStateBuilder.focusAfterCompleting(
            target,
            preferSameExercise: preferSameExercise,
            in: session
        )
        session.updatedAt = .now

        WorkoutLiveActivityWorkoutCoordinator.selectExercise(
            focus.exercise.id,
            sessionID: sessionUUID
        )

        let restSeconds = target.exercise.defaultRestSeconds
            ?? settings?.defaultRestSeconds
            ?? 90
        let nextLabel = WorkoutLiveActivityStateBuilder.targetLabel(focus)
        let snapshot = WorkoutLiveActivityStateBuilder.snapshot(
            focus,
            preferredUnit: preferredUnit
        )
        let inAppTimer = ActiveWorkoutRestTimerBridge.shared.presentedTimer
        let liveActivityRestSeconds = inAppTimer == nil ? restSeconds : 0

        // One ActivityKit update paints the next set + Logged (+ rest when app isn't open).
        await RestTimerLiveActivityManager.applyCompletedSetFromIntent(
            sessionID: sessionUUID,
            currentSet: snapshot,
            nextExerciseName: WorkoutLiveActivityStateBuilder.followingLabel(
                after: focus,
                in: session
            ),
            restSeconds: liveActivityRestSeconds,
            restNextExerciseName: nextLabel
        )

        // Persist after Lock Screen paint so the intent returns quickly.
        try context.save()

        if let timer = inAppTimer {
            timer.start(seconds: restSeconds, nextExerciseName: nextLabel)
        } else if restSeconds > 0 {
            RestTimerNotificationManager.schedule(
                sessionID: sessionUUID,
                at: Date().addingTimeInterval(TimeInterval(restSeconds))
            )
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
        if let sameExercise = nextTargetOnSameExercise(after: target) {
            return sameExercise
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

    static func nextTargetOnSameExercise(after target: Target) -> Target? {
        let sets = target.exercise.orderedSets
        guard let currentIndex = sets.firstIndex(where: { $0.id == target.set.id }) else {
            return nil
        }
        for set in sets.suffix(from: min(currentIndex + 1, sets.endIndex))
        where !set.isCompleted {
            return Target(exercise: target.exercise, set: set)
        }
        return nil
    }

    /// After logging a set:
    /// - Prefer the next incomplete set on the same exercise.
    /// - “Another” always appends when none remain on this exercise.
    /// - “Next” advances to a later exercise when one exists; otherwise appends.
    static func focusAfterCompleting(
        _ target: Target,
        preferSameExercise: Bool,
        in session: WorkoutSession
    ) -> Target {
        if let next = nextTargetOnSameExercise(after: target) {
            prefillEmptyValues(on: next.set, from: target.set)
            return next
        }
        if preferSameExercise {
            return appendExtraSet(after: target)
        }
        if let across = nextTarget(after: target, in: session) {
            return across
        }
        return appendExtraSet(after: target)
    }

    private static func appendExtraSet(after target: Target) -> Target {
        let newSet = WorkoutCreationService().makeExtraSet(for: target.exercise)
        target.exercise.sets.append(newSet)
        target.exercise.normalizeSetOrder()
        return Target(exercise: target.exercise, set: newSet)
    }

    /// Copies performance fields onto `next` only when that field is empty, so a
    /// planned set that already has values keeps them.
    static func prefillEmptyValues(on next: WorkoutSet, from source: WorkoutSet) {
        if next.weight == nil { next.weight = source.weight }
        if next.repetitions == nil { next.repetitions = source.repetitions }
        if next.durationSeconds == nil { next.durationSeconds = source.durationSeconds }
        if next.distance == nil { next.distance = source.distance }
        if next.assistanceWeight == nil { next.assistanceWeight = source.assistanceWeight }
        if next.leftValue == nil { next.leftValue = source.leftValue }
        if next.rightValue == nil { next.rightValue = source.rightValue }
        next.updatedAt = .now
    }

    static func followingLabel(after target: Target, in session: WorkoutSession) -> String {
        guard let following = nextTarget(after: target, in: session) else {
            return "All sets done"
        }
        return targetLabel(following)
    }

    static func targetLabel(_ target: Target) -> String {
        let name = target.exercise.exercise?.name ?? "Exercise"
        return "\(name) · Set \(target.set.orderIndex + 1)"
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
        ExerciseWeightStep.step(for: exercise, preferredUnit: preferredUnit)
    }
}

