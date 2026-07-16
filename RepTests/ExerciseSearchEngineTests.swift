import Foundation
import Testing
@testable import Rep

@Suite("Exercise search ranking")
struct ExerciseSearchEngineTests {
    private let exercises = [
        Exercise(name: "Seated Cable Row", primaryMuscleGroup: .back, equipment: .cable),
        Exercise(
            name: "Romanian Deadlift",
            primaryMuscleGroup: .hamstrings,
            secondaryMuscleGroups: [.glutes, .back],
            equipment: .barbell,
            searchAliases: ["RDL", "Romanian hip hinge"]
        ),
        Exercise(
            name: "Deadlift",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.back, .hamstrings, .glutes],
            equipment: .barbell,
            searchAliases: ["Conventional deadlift"]
        ),
        Exercise(
            name: "Sumo Deadlift",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.glutes, .hamstrings, .quadriceps],
            equipment: .barbell
        ),
        Exercise(name: "Lat Pulldown", primaryMuscleGroup: .back, equipment: .cable),
        Exercise(name: "Dumbbell Bench Press", primaryMuscleGroup: .chest, equipment: .dumbbell),
    ]

    @Test("An exact name match is first")
    func exactMatch() {
        let results = ExerciseSearchEngine.search(exercises, query: "deadlift")

        #expect(results.first?.name == "Deadlift")
    }

    @Test("Multiple words can match name and muscle metadata")
    func multiTokenMatch() {
        let results = ExerciseSearchEngine.search(exercises, query: "Back dead")
        let names = results.map(\.name)

        #expect(names.first == "Deadlift")
        #expect(Set(names.prefix(3)) == Set(["Deadlift", "Romanian Deadlift", "Sumo Deadlift"]))
        #expect(names.firstIndex(of: "Sumo Deadlift")! < names.firstIndex(of: "Seated Cable Row")!)
    }

    @Test("A name prefix outranks a later substring")
    func prefixMatch() {
        let results = ExerciseSearchEngine.search(exercises, query: "dead")

        #expect(results.first?.name == "Deadlift")
        #expect(results.map(\.name).contains("Romanian Deadlift"))
    }

    @Test("A small typo still finds the intended exercise")
    func typoMatch() {
        let results = ExerciseSearchEngine.search(exercises, query: "dedlift")

        #expect(results.first?.name == "Deadlift")
    }

    @Test("Queries without spaces match spaced exercise names")
    func compactMatch() {
        let results = ExerciseSearchEngine.search(exercises, query: "benchpress")

        #expect(results.first?.name == "Dumbbell Bench Press")
    }

    @Test("Messy compact queries still find the intended exercise")
    func compactTypoMatch() {
        let results = ExerciseSearchEngine.search(exercises, query: "bcnhpress")

        #expect(results.first?.name == "Dumbbell Bench Press")
    }

    @Test("Aliases participate in ranking")
    func aliasMatch() {
        let results = ExerciseSearchEngine.search(exercises, query: "RDL")

        #expect(results.first?.name == "Romanian Deadlift")
    }

    @Test("An unrelated query has no matches")
    func noMatch() {
        let results = ExerciseSearchEngine.search(exercises, query: "swimming")

        #expect(results.isEmpty)
    }

    @Test("An empty query sorts alphabetically")
    func emptyQuery() {
        let results = ExerciseSearchEngine.search(exercises, query: "   ")

        #expect(results.map(\.name) == exercises.map(\.name).sorted())
    }

    @Test("A single-token query ranks popular squats above obscure prefix matches")
    func squatPopularityRanking() {
        let squatExercises = [
            Exercise(
                name: "Back Squat",
                primaryMuscleGroup: .quadriceps,
                equipment: .barbell,
                searchAliases: ["Squat"],
                popularityRank: ExercisePopularity.rank(for: "Back Squat")
            ),
            Exercise(
                name: "Front Squat",
                primaryMuscleGroup: .quadriceps,
                equipment: .barbell,
                popularityRank: ExercisePopularity.rank(for: "Front Squat")
            ),
            Exercise(
                name: "Squat Jerk",
                primaryMuscleGroup: .fullBody,
                equipment: .barbell,
                popularityRank: ExercisePopularity.unrankedRank
            ),
        ]

        let results = ExerciseSearchEngine.search(squatExercises, query: "Squat")

        #expect(results.first?.name == "Back Squat")
        #expect(results.map(\.name).last == "Squat Jerk")
    }

    @Test("Singular/plural query variants still rank the canonical exercise first")
    func tricepsPushdownSingularVariant() {
        let list = [
            Exercise(
                name: "Triceps Pushdown",
                primaryMuscleGroup: .triceps,
                equipment: .cable,
                searchAliases: ["Tricep Pushdown"],
                popularityRank: ExercisePopularity.rank(for: "Triceps Pushdown")
            ),
            Exercise(
                name: "Triceps Pushdown (Rope)",
                primaryMuscleGroup: .triceps,
                equipment: .cable
            ),
        ]

        let results = ExerciseSearchEngine.search(list, query: "Tricep Pushdown")
        #expect(results.first?.name == "Triceps Pushdown")
    }

    @Test("Bent-over punctuation does not change search identity")
    func bentOverDumbbellRowPunctuation() {
        let row = Exercise(
            name: "Dumbbell Bent-Over Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.biceps],
            equipment: .dumbbell
        )

        #expect(
            ExerciseNameNormalizer.normalize("Dumbbell Bent-over row")
                == ExerciseNameNormalizer.normalize("Dumbbell Bent over row")
        )
        #expect(
            ExerciseSearchEngine.search([row], query: "Dumbbell Bent over row").first?.id
                == row.id
        )
    }

    @Test("Rope bicep wording finds the normal rope curl before hammer variants")
    func ropeBicepCurlIntent() {
        let ropeCurl = Exercise(
            name: "Rope Biceps Curl",
            primaryMuscleGroup: .biceps,
            equipment: .cable,
            searchAliases: ["Rope Bicep Curl", "Cable Rope Curl"]
        )
        let hammerCurl = Exercise(
            name: "Cable Hammer Curl With Rope",
            primaryMuscleGroup: .biceps,
            equipment: .cable,
            searchAliases: ["Rope"]
        )

        let results = ExerciseSearchEngine.search(
            [hammerCurl, ropeCurl],
            query: "rope bicep curl"
        )

        #expect(results.first?.id == ropeCurl.id)
    }

    @Test("Straight-bar wording resolves to the standard cable curl")
    func straightBarCableCurlAlias() {
        let cableCurl = Exercise(
            name: "Cable Curl",
            primaryMuscleGroup: .biceps,
            equipment: .cable,
            searchAliases: ["Straight-Bar Cable Curl", "Cable Bicep Curl"]
        )

        #expect(
            ExerciseSearchEngine.search([cableCurl], query: "straight bar bicep curl").first?.id
                == cableCurl.id
        )
    }
}
