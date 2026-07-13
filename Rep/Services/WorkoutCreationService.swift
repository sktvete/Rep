import Foundation

struct PreviousPerformanceSelection {
    let exercise: WorkoutExercise
    let session: WorkoutSession
    let matchedSameRoutine: Bool
}

struct WorkoutCreationService {
    func startWorkout(
        from routine: Routine,
        previousSessions: [WorkoutSession],
        startedAt: Date = .now
    ) -> WorkoutSession {
        let session = WorkoutSession(
            routineID: routine.id,
            name: routine.name,
            startedAt: startedAt,
            state: .active,
            notes: routine.notes
        )

        session.exercises = routine.orderedExercises.enumerated().map { index, routineItem in
            let previous = routineItem.exercise.flatMap {
                previousPerformance(
                    for: $0.id,
                    routineID: routine.id,
                    before: startedAt,
                    sessions: previousSessions
                )
            }

            let sets = makePrefilledSets(
                routineExercise: routineItem,
                previous: previous?.exercise,
                createdAt: startedAt
            )
            let item = WorkoutExercise(
                exercise: routineItem.exercise,
                orderIndex: index,
                notes: routineItem.notes,
                sourceRoutineExerciseID: routineItem.id,
                defaultRestSeconds: routineItem.defaultRestSeconds,
                sets: sets
            )
            return item
        }
        return session
    }

    func startEmptyWorkout(name: String = "Workout", startedAt: Date = .now) -> WorkoutSession {
        WorkoutSession(name: name, startedAt: startedAt, state: .active)
    }

    func previousPerformance(
        for exerciseID: UUID,
        routineID: UUID?,
        before date: Date,
        sessions: [WorkoutSession]
    ) -> PreviousPerformanceSelection? {
        let candidates = sessions
            .filter { $0.state == .completed && ($0.completedAt ?? $0.startedAt) < date }
            .compactMap { session -> (WorkoutSession, WorkoutExercise)? in
                guard let item = session.exercises.first(where: { $0.exercise?.id == exerciseID }) else { return nil }
                return (session, item)
            }

        if let routineID,
           let sameRoutine = candidates
            .filter({ $0.0.routineID == routineID })
            .max(by: { performanceDate($0.0) < performanceDate($1.0) }) {
            return PreviousPerformanceSelection(
                exercise: sameRoutine.1,
                session: sameRoutine.0,
                matchedSameRoutine: true
            )
        }

        guard let latest = candidates.max(by: { performanceDate($0.0) < performanceDate($1.0) }) else { return nil }
        return PreviousPerformanceSelection(exercise: latest.1, session: latest.0, matchedSameRoutine: false)
    }

    func makeExtraSet(for workoutExercise: WorkoutExercise, createdAt: Date = .now) -> WorkoutSet {
        guard let previous = workoutExercise.orderedSets.last else {
            return WorkoutSet(orderIndex: 0, createdAt: createdAt)
        }
        return cloneSet(previous, orderIndex: workoutExercise.sets.count, createdAt: createdAt)
    }

    private func makePrefilledSets(
        routineExercise: RoutineExercise,
        previous: WorkoutExercise?,
        createdAt: Date
    ) -> [WorkoutSet] {
        let previousSets = previous?.orderedSets.filter(\.isCompleted) ?? []
        if !previousSets.isEmpty {
            return previousSets.enumerated().map { index, set in
                cloneSet(set, orderIndex: index, createdAt: createdAt)
            }
        }

        return (0..<routineExercise.targetSetCount).map { index in
            WorkoutSet(
                orderIndex: index,
                repetitions: routineExercise.suggestedRepetitions,
                createdAt: createdAt
            )
        }
    }

    private func cloneSet(_ source: WorkoutSet, orderIndex: Int, createdAt: Date) -> WorkoutSet {
        WorkoutSet(
            orderIndex: orderIndex,
            setType: source.setType,
            weight: source.weight,
            repetitions: source.repetitions,
            durationSeconds: source.durationSeconds,
            distance: source.distance,
            assistanceWeight: source.assistanceWeight,
            leftValue: source.leftValue,
            rightValue: source.rightValue,
            createdAt: createdAt
        )
    }

    private func performanceDate(_ session: WorkoutSession) -> Date {
        session.completedAt ?? session.startedAt
    }
}
