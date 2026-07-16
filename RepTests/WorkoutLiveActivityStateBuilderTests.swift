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

    @Test("The final exercise points to another set instead of the first exercise")
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
                == "Raise · Another set"
        )
    }

    @Test("Shoulder weight controls use smaller increments")
    @MainActor
    func shoulderIncrement() {
        let set = WorkoutSet(orderIndex: 0, weight: 10, repetitions: 10)
        let item = workoutExercise(
            name: "Lateral Raise",
            muscle: .shoulders,
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

    @MainActor
    private func workoutExercise(
        name: String,
        muscle: MuscleGroup = .back,
        orderIndex: Int,
        sets: [WorkoutSet]
    ) -> WorkoutExercise {
        WorkoutExercise(
            exercise: Exercise(
                name: name,
                primaryMuscleGroup: muscle,
                equipment: .dumbbell
            ),
            orderIndex: orderIndex,
            sets: sets
        )
    }
}
