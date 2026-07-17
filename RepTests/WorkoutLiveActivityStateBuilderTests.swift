import Testing
@testable import Rep

@Suite("Workout Live Activity navigation")
struct WorkoutLiveActivityStateBuilderTests {
    @Test("The next incomplete set in the current exercise wins")
    @MainActor
    func nextSetInCurrentExercise() {
        let first = WorkoutSet(orderIndex: 0, isCompleted: true)
        let second = WorkoutSet(orderIndex: 1)
        let item = workoutExercise(name: "Row", orderIndex: 0, sets: [first, second])
        let session = WorkoutSession(name: "Pull", exercises: [item])

        let target = WorkoutLiveActivityStateBuilder.Target(exercise: item, set: first)
        let next = WorkoutLiveActivityStateBuilder.nextTarget(after: target, in: session)

        #expect(next?.set.id == second.id)
        #expect(next?.exercise.id == item.id)
    }

    @Test("Navigation advances to the actual next exercise without wrapping")
    @MainActor
    func nextExerciseWithoutWrap() {
        let completed = WorkoutSet(orderIndex: 0, isCompleted: true)
        let upcoming = WorkoutSet(orderIndex: 0)
        let first = workoutExercise(name: "Row", orderIndex: 0, sets: [completed])
        let second = workoutExercise(name: "Curl", orderIndex: 1, sets: [upcoming])
        let session = WorkoutSession(name: "Pull", exercises: [first, second])

        let target = WorkoutLiveActivityStateBuilder.Target(exercise: first, set: completed)
        let next = WorkoutLiveActivityStateBuilder.nextTarget(after: target, in: session)

        #expect(next?.exercise.id == second.id)
        #expect(next?.set.id == upcoming.id)
        #expect(WorkoutLiveActivityStateBuilder.targetLabel(next!) == "Curl · Set 1")
    }

    @Test("The final exercise does not wrap or invent another set")
    @MainActor
    func finalExerciseDoesNotLoop() {
        let firstSet = WorkoutSet(orderIndex: 0, isCompleted: true)
        let finalSet = WorkoutSet(orderIndex: 0, isCompleted: true)
        let first = workoutExercise(name: "Press", orderIndex: 0, sets: [firstSet])
        let final = workoutExercise(name: "Raise", orderIndex: 1, sets: [finalSet])
        let session = WorkoutSession(name: "Push", exercises: [first, final])
        let target = WorkoutLiveActivityStateBuilder.Target(exercise: final, set: finalSet)

        #expect(WorkoutLiveActivityStateBuilder.nextTarget(after: target, in: session) == nil)
        #expect(
            WorkoutLiveActivityStateBuilder.followingLabel(after: target, in: session)
                == "All sets done"
        )
    }

    @Test("Another-set navigation stays on the same exercise")
    @MainActor
    func anotherSetStaysOnExercise() {
        let first = WorkoutSet(orderIndex: 0, weight: 100, repetitions: 5, isCompleted: true)
        let second = WorkoutSet(orderIndex: 1)
        let row = workoutExercise(name: "Row", orderIndex: 0, sets: [first, second])
        let curl = workoutExercise(
            name: "Curl",
            orderIndex: 1,
            sets: [WorkoutSet(orderIndex: 0)]
        )
        let session = WorkoutSession(name: "Pull", exercises: [row, curl])
        let target = WorkoutLiveActivityStateBuilder.Target(exercise: row, set: first)

        let same = WorkoutLiveActivityStateBuilder.nextTargetOnSameExercise(after: target)
        #expect(same?.set.id == second.id)
        #expect(same?.exercise.id == row.id)

        let across = WorkoutLiveActivityStateBuilder.nextTarget(after: target, in: session)
        #expect(across?.set.id == second.id)

        let last = WorkoutLiveActivityStateBuilder.Target(exercise: row, set: second)
        second.markCompleted()
        #expect(WorkoutLiveActivityStateBuilder.nextTargetOnSameExercise(after: last) == nil)
        #expect(
            WorkoutLiveActivityStateBuilder.nextTarget(after: last, in: session)?.exercise.id
                == curl.id
        )
    }

    @Test("Empty next-set fields inherit the completed set values")
    @MainActor
    func prefillEmptyValuesFromCompletedSet() {
        let completed = WorkoutSet(
            orderIndex: 0,
            weight: 80,
            repetitions: 8,
            isCompleted: true
        )
        let empty = WorkoutSet(orderIndex: 1)
        WorkoutLiveActivityStateBuilder.prefillEmptyValues(on: empty, from: completed)

        #expect(empty.weight == 80)
        #expect(empty.repetitions == 8)
    }

    @Test("Existing next-set values are preserved when prefilling")
    @MainActor
    func prefillKeepsExistingValues() {
        let completed = WorkoutSet(
            orderIndex: 0,
            weight: 80,
            repetitions: 8,
            isCompleted: true
        )
        let planned = WorkoutSet(orderIndex: 1, weight: 85, repetitions: 6)
        WorkoutLiveActivityStateBuilder.prefillEmptyValues(on: planned, from: completed)

        #expect(planned.weight == 85)
        #expect(planned.repetitions == 6)
    }

    @Test("Shoulder weight controls use smaller increments")
    @MainActor
    func shoulderIncrement() {
        let set = WorkoutSet(orderIndex: 0, weight: 10, repetitions: 10)
        let item = workoutExercise(
            name: "Lateral Raise",
            muscle: .shoulders,
            equipment: .dumbbell,
            orderIndex: 0,
            sets: [set]
        )
        let target = WorkoutLiveActivityStateBuilder.Target(exercise: item, set: set)

        #expect(
            WorkoutLiveActivityStateBuilder.snapshot(target, preferredUnit: .kilograms).weightStep
                == 1
        )
        #expect(
            WorkoutLiveActivityStateBuilder.snapshot(target, preferredUnit: .pounds).weightStep
                == 2.5
        )
    }

    @Test("Weight steps follow equipment and muscle conventions")
    @MainActor
    func weightStepsByEquipment() {
        #expect(ExerciseWeightStep.kilogramsStep(for: exercise(muscle: .back, equipment: .machine)) == 5)
        #expect(ExerciseWeightStep.kilogramsStep(for: exercise(muscle: .back, equipment: .cable)) == 2.5)
        #expect(ExerciseWeightStep.kilogramsStep(for: exercise(muscle: .chest, equipment: .dumbbell)) == 2.5)
        #expect(ExerciseWeightStep.kilogramsStep(for: exercise(muscle: .chest, equipment: .barbell)) == 5)
        #expect(ExerciseWeightStep.kilogramsStep(for: exercise(muscle: .back, equipment: .barbell)) == 5)
        #expect(ExerciseWeightStep.kilogramsStep(for: exercise(muscle: .biceps, equipment: .barbell)) == 5)
        #expect(ExerciseWeightStep.kilogramsStep(for: exercise(muscle: .biceps, equipment: .machine)) == 1)
        #expect(ExerciseWeightStep.step(for: exercise(muscle: .back, equipment: .machine), preferredUnit: .pounds) == 10)
        #expect(ExerciseWeightStep.step(for: exercise(muscle: .chest, equipment: .barbell), preferredUnit: .pounds) == 10)
        #expect(ExerciseWeightStep.step(for: exercise(muscle: .chest, equipment: .dumbbell), preferredUnit: .pounds) == 5)
    }

    @MainActor
    private func exercise(
        muscle: MuscleGroup,
        equipment: Equipment
    ) -> Exercise {
        Exercise(
            name: "Test",
            primaryMuscleGroup: muscle,
            equipment: equipment
        )
    }

    @MainActor
    private func workoutExercise(
        name: String,
        muscle: MuscleGroup = .back,
        equipment: Equipment = .dumbbell,
        orderIndex: Int,
        sets: [WorkoutSet]
    ) -> WorkoutExercise {
        WorkoutExercise(
            exercise: Exercise(
                name: name,
                primaryMuscleGroup: muscle,
                equipment: equipment
            ),
            orderIndex: orderIndex,
            sets: sets
        )
    }
}
