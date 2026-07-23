import Foundation
import SwiftData
import Testing
@testable import Rep

@Suite("Guided routine builder", .serialized)
@MainActor
struct GuidedRoutineBuilderTests {
    @Test("Experience offers beginner, intermediate and expert levels")
    func experienceLevelsAreProgressive() {
        #expect(GuidedRoutineExperience.allCases == [.beginner, .intermediate, .expert])
        #expect(GuidedRoutineExperience.allCases.map(\.title) == ["Beginner", "Intermediate", "Expert"])

        let candidate = GuidedExerciseCandidateDefinition(
            "Progressive Row",
            reason: "Test progression",
            profiles: [],
            newRank: 0,
            experiencedRank: 4
        )
        #expect(candidate.rank(for: .beginner) == 0)
        #expect(candidate.rank(for: .intermediate) == 2)
        #expect(candidate.rank(for: .expert) == 4)
    }

    @Test("The four plans cover 21 distinct movement slots")
    func templatesHaveCompleteMovementCoverage() {
        #expect(GuidedRoutineCatalog.templates.count == 4)
        #expect(GuidedRoutineCatalog.template(for: .legs).slots.count == 5)
        #expect(GuidedRoutineCatalog.template(for: .push).slots.count == 5)
        #expect(GuidedRoutineCatalog.template(for: .pull).slots.count == 5)
        #expect(GuidedRoutineCatalog.template(for: .core).slots.count == 6)

        let slots = GuidedRoutineCatalog.templates.flatMap(\.slots)
        #expect(Set(slots.map(\.id)).count == 21)
        #expect(slots.allSatisfy { $0.candidates.count >= 3 })
        #expect(slots.allSatisfy {
            $0.setCount > 0 && $0.repetitions > 0 && $0.restSeconds >= 0
        })
    }

    @Test("The default plan targets a 50 to 60 minute workout")
    func standardDurationMatchesProductGoal() {
        #expect(GuidedRoutineDuration.standard.estimatedMinutes >= 50)
        #expect(GuidedRoutineDuration.standard.estimatedMinutes <= 60)

        for template in GuidedRoutineCatalog.templates {
            for slot in template.slots {
                #expect(slot.setCount(for: .quick) >= 2)
                #expect(slot.setCount(for: .standard) == slot.setCount)
                #expect(slot.setCount(for: .extended) == slot.setCount + 1)
            }
        }
    }

    @Test("Resolution returns three unique active equipment-compatible choices")
    func resolverFiltersAndRanksChoices() throws {
        let slot = GuidedMovementSlot(
            id: "test-row",
            title: "Row",
            purpose: "Test rows",
            fallbackMuscle: .back,
            setCount: 3,
            repetitions: 10,
            restSeconds: 90,
            candidates: [
                GuidedExerciseCandidateDefinition(
                    "Stable Row",
                    reason: "Recommended",
                    profiles: [.dumbbells],
                    newRank: 0,
                    experiencedRank: 2
                ),
                GuidedExerciseCandidateDefinition(
                    "Strong Row",
                    reason: "Experienced",
                    profiles: [.dumbbells],
                    newRank: 2,
                    experiencedRank: 0
                ),
                GuidedExerciseCandidateDefinition(
                    "Third Row",
                    reason: "Alternative",
                    profiles: [.dumbbells],
                    newRank: 1,
                    experiencedRank: 1
                )
            ]
        )
        let stable = exercise("Stable Row", equipment: .dumbbell)
        let strong = exercise("Strong Row", equipment: .dumbbell)
        let third = exercise("Third Row", equipment: .bodyweight)
        let cable = exercise("Cable Row", equipment: .cable)
        let archived = exercise("Archived Row", equipment: .dumbbell, isArchived: true)
        let timed = exercise("Timed Row", equipment: .dumbbell, measurementType: .duration)

        let options = try GuidedExerciseResolver.options(
            for: slot,
            experience: .beginner,
            equipmentProfile: .dumbbells,
            exercises: [cable, archived, timed, strong, third, stable]
        )

        #expect(options.count == 3)
        #expect(Set(options.map(\.id)).count == 3)
        #expect(options.map(\.exercise.id) == [stable.id, third.id, strong.id])
        #expect(options.first?.isRecommended == true)
        #expect(options.dropFirst().allSatisfy { !$0.isRecommended })
        #expect(options.allSatisfy { $0.exercise.id != cable.id })
        #expect(options.allSatisfy { $0.exercise.id != archived.id })
        #expect(options.allSatisfy { $0.exercise.id != timed.id })
    }

    @Test("Canonical aliases inherit popularity instead of manual beginner rank")
    func canonicalAliasPopularityWins() throws {
        let slot = GuidedMovementSlot(
            id: "press",
            title: "Press",
            purpose: "Test popular presses",
            fallbackMuscle: .chest,
            setCount: 3,
            repetitions: 8,
            restSeconds: 120,
            candidates: [
                GuidedExerciseCandidateDefinition(
                    "Machine Bench Press",
                    reason: "Manual beginner choice",
                    profiles: [],
                    newRank: 0,
                    experiencedRank: 2
                ),
                GuidedExerciseCandidateDefinition(
                    "Barbell Bench Press - Medium Grip",
                    aliases: ["Barbell Bench Press"],
                    reason: "Canonical staple",
                    profiles: [],
                    newRank: 9,
                    experiencedRank: 0
                ),
                GuidedExerciseCandidateDefinition(
                    "Dumbbell Bench Press",
                    reason: "Alternative",
                    profiles: [],
                    newRank: 1,
                    experiencedRank: 1
                )
            ]
        )
        let machine = exercise("Machine Bench Press", muscle: .chest, equipment: .machine)
        let rawBarbell = exercise(
            "Barbell Bench Press - Medium Grip",
            muscle: .chest,
            equipment: .barbell
        )
        let dumbbell = exercise("Dumbbell Bench Press", muscle: .chest)

        let options = try GuidedExerciseResolver.options(
            for: slot,
            experience: .beginner,
            equipmentProfile: .fullGym,
            exercises: [machine, dumbbell, rawBarbell]
        )

        #expect(options.first?.exercise.id == rawBarbell.id)
        #expect(options.first?.isRecommended == true)
    }

    @Test("Exercises above the selected experience are not reintroduced as fallbacks")
    func minimumExperienceIsStrict() throws {
        let slot = GuidedMovementSlot(
            id: "core",
            title: "Core",
            purpose: "Test experience gating",
            fallbackMuscle: .core,
            setCount: 3,
            repetitions: 10,
            restSeconds: 60,
            candidates: [
                GuidedExerciseCandidateDefinition(
                    "Dead Bug",
                    reason: "Beginner",
                    profiles: [],
                    newRank: 0,
                    experiencedRank: 3
                ),
                GuidedExerciseCandidateDefinition(
                    "Reverse Crunch",
                    reason: "Beginner",
                    profiles: [],
                    newRank: 1,
                    experiencedRank: 2
                ),
                GuidedExerciseCandidateDefinition(
                    "Tuck Crunch",
                    reason: "Beginner",
                    profiles: [],
                    newRank: 2,
                    experiencedRank: 1
                ),
                GuidedExerciseCandidateDefinition(
                    "Hanging Leg Raise",
                    reason: "Intermediate",
                    profiles: [],
                    newRank: 9,
                    experiencedRank: 0,
                    minimumExperience: .intermediate
                )
            ]
        )
        let deadBug = exercise("Dead Bug", muscle: .core, equipment: .bodyweight)
        let reverseCrunch = exercise("Reverse Crunch", muscle: .core, equipment: .bodyweight)
        let tuckCrunch = exercise("Tuck Crunch", muscle: .core, equipment: .bodyweight)
        let hangingRaise = exercise("Hanging Leg Raise", muscle: .core, equipment: .bodyweight)
        let exercises = [hangingRaise, deadBug, reverseCrunch, tuckCrunch]

        let beginner = try GuidedExerciseResolver.options(
            for: slot,
            experience: .beginner,
            equipmentProfile: .fullGym,
            exercises: exercises
        )
        let intermediate = try GuidedExerciseResolver.options(
            for: slot,
            experience: .intermediate,
            equipmentProfile: .fullGym,
            exercises: exercises
        )

        #expect(!beginner.contains { $0.exercise.id == hangingRaise.id })
        #expect(intermediate.first?.exercise.id == hangingRaise.id)
    }

    @Test("Every shipped plan resolves three choices from the offline catalog")
    func shippedCatalogResolvesAllPlans() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let suiteName = "GuidedRoutineBuilderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        _ = try BundledExerciseCatalogService.seedIfNeeded(
            in: context,
            bundle: .main,
            defaults: defaults
        )
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        for template in GuidedRoutineCatalog.templates {
            for experience in GuidedRoutineExperience.allCases {
                for equipmentProfile in GuidedRoutineEquipmentProfile.allCases {
                    for slot in template.slots {
                        let options = try GuidedExerciseResolver.options(
                            for: slot,
                            experience: experience,
                            equipmentProfile: equipmentProfile,
                            exercises: exercises
                        )

                        #expect(options.count == 3, "\(template.focus.title): \(slot.title)")
                        #expect(Set(options.map(\.id)).count == 3, "\(template.focus.title): \(slot.title)")
                        #expect(options.allSatisfy { !$0.exercise.isArchived })
                        #expect(options.allSatisfy { equipmentProfile.accepts($0.exercise.equipment) })
                        #expect(options.allSatisfy { isRepetitionBased($0.exercise.measurementType) })
                    }
                }
            }
        }
    }

    @Test("Fresh-install boot order recommends the canonical popular staples")
    func freshInstallDefaultsUsePopularCanonicalExercises() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let suiteName = "GuidedRoutineBuilderDefaults.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        _ = try BundledExerciseCatalogService.seedIfNeeded(
            in: context,
            bundle: .main,
            defaults: defaults
        )
        _ = try ExerciseSeedService.seedIfNeeded(in: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let expectedFirstExercise: [GuidedRoutineFocus: String] = [
            .legs: "Back Squat",
            .push: "Barbell Bench Press",
            .pull: "Lat Pulldown",
            .core: "Dead Bug"
        ]

        for focus in GuidedRoutineFocus.allCases {
            let slot = try #require(GuidedRoutineCatalog.template(for: focus).slots.first)
            let options = try GuidedExerciseResolver.options(
                for: slot,
                experience: .beginner,
                equipmentProfile: .fullGym,
                exercises: exercises
            )

            #expect(options.first?.exercise.name == expectedFirstExercise[focus], "\(focus.title)")
        }

        let pushDefaults = try GuidedRoutineCatalog.template(for: .push).slots.map { slot in
            try #require(GuidedExerciseResolver.options(
                for: slot,
                experience: .beginner,
                equipmentProfile: .fullGym,
                exercises: exercises
            ).first?.exercise.name)
        }
        #expect(pushDefaults == [
            "Barbell Bench Press",
            "Barbell Overhead Press",
            "Incline Barbell Bench Press",
            "Dumbbell Lateral Raise",
            "Triceps Pushdown"
        ])
    }

    @Test("Saving preserves chosen order and movement defaults")
    func factoryMapsReviewIntoRoutine() throws {
        let template = GuidedRoutineCatalog.template(for: .push)
        let firstSlot = try #require(template.slots.first)
        let secondSlot = try #require(template.slots.dropFirst().first)
        let firstExercise = exercise("First Press", muscle: .chest)
        let secondExercise = exercise("Second Press", muscle: .shoulders)
        let selections = [
            GuidedRoutineSelection(slot: secondSlot, exercise: secondExercise),
            GuidedRoutineSelection(slot: firstSlot, exercise: firstExercise)
        ]

        let routine = GuidedRoutineFactory.makeRoutine(
            name: "  My Push  ",
            colorPreset: .purple,
            duration: .standard,
            selections: selections
        )

        #expect(routine.name == "My Push")
        #expect(routine.colorPreset == .purple)
        #expect(routine.orderedExercises.map(\.exercise?.id) == [secondExercise.id, firstExercise.id])
        #expect(routine.orderedExercises.map(\.orderIndex) == [0, 1])
        #expect(routine.orderedExercises[0].targetSetCount == secondSlot.setCount)
        #expect(routine.orderedExercises[0].suggestedRepetitions == secondSlot.repetitions)
        #expect(routine.orderedExercises[0].defaultRestSeconds == secondSlot.restSeconds)
    }

    private func exercise(
        _ name: String,
        muscle: MuscleGroup = .back,
        equipment: Equipment = .dumbbell,
        measurementType: MeasurementType = .weightAndRepetitions,
        isArchived: Bool = false
    ) -> Exercise {
        Exercise(
            name: name,
            primaryMuscleGroup: muscle,
            equipment: equipment,
            measurementType: measurementType,
            isArchived: isArchived
        )
    }

    private func isRepetitionBased(_ measurementType: MeasurementType) -> Bool {
        switch measurementType {
        case .weightAndRepetitions,
             .repetitionsOnly,
             .bodyweightAndRepetitions,
             .bodyweightPlusAddedWeight,
             .assistedBodyweight:
            true
        case .duration,
             .weightAndDuration,
             .distanceAndDuration,
             .custom:
            false
        }
    }
}
