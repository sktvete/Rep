import SwiftData
import XCTest
@testable import Rep

final class ExerciseSeedMediaOverridesTests: XCTestCase {
    func testAbWheelRolloutOverride() {
        let override = ExerciseSeedMediaOverrides.override(
            forNormalizedName: ExerciseNameNormalizer.normalize("Ab Wheel Rollout")
        )
        XCTAssertEqual(override?.catalogExerciseID, "NAgVB3t")
        XCTAssertTrue(override?.mediaURLString.contains("NAgVB3t.gif") == true)
    }

    @MainActor
    func testLegitimateSeedsStayAvailableWithoutUnverifiedMedia() {
        for name in [
            "Chest-Supported Row",
            "Smith Machine Bench Press",
            "Rope Biceps Curl",
            "Face Pull",
            "Barbell Hip Thrust",
            "Dumbbell Shoulder Press",
            "Bulgarian Split Squat",
            "Incline Dumbbell Press",
        ] {
            XCTAssertTrue(ExerciseSeedService.activeSeedNormalizedNames.contains(ExerciseNameNormalizer.normalize(name)))
            XCTAssertNil(
                ExerciseSeedMediaOverrides.override(forNormalizedName: ExerciseNameNormalizer.normalize(name)),
                "An absent GIF is safer than assigning a different movement's media to \(name)."
            )
        }
    }

    @MainActor
    func testRestoredExercisesAreSearchableAndActive() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        _ = try ExerciseSeedService.seedIfNeeded(in: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        for query in ["chest supported row", "smith machine bench press"] {
            let result = ExerciseSearchEngine.search(exercises, query: query).first
            XCTAssertNotNil(result, "Expected a result for \(query)")
            XCTAssertFalse(result?.isArchived ?? true)
        }
    }

    func testPopularSeedsHaveOverrides() {
        let names = [
            "Barbell Bench Press",
            "Back Squat",
            "Deadlift",
            "Ab Wheel Rollout",
            "Farmer Carry",
            "Cable Curl",
        ]
        for name in names {
            XCTAssertNotNil(
                ExerciseSeedMediaOverrides.override(forNormalizedName: ExerciseNameNormalizer.normalize(name)),
                "Missing override for \(name)"
            )
        }
    }

    @MainActor
    func testEveryMediaOverrideBelongsToAnActiveSeedAndIsStructurallyValid() {
        let activeSeedNames = ExerciseSeedService.activeSeedNormalizedNames
        XCTAssertTrue(ExerciseSeedMediaOverrides.allNormalizedNames.isSubset(of: activeSeedNames))

        let overrides = ExerciseSeedMediaOverrides.allOverrides
        XCTAssertEqual(Set(overrides.map(\.catalogExerciseID)).count, overrides.count)
        for override in overrides {
            let url = URL(string: override.mediaURLString)
            XCTAssertEqual(url?.scheme, "https")
            XCTAssertEqual(url?.host, "static.exercisedb.dev")
            XCTAssertEqual(url?.lastPathComponent, "\(override.catalogExerciseID).gif")
            XCTAssertFalse(override.enrichSearchQueries.isEmpty)
            XCTAssertNotNil(
                ExerciseSeedMediaOverrides.normalizedSeedName(
                    forCatalogExerciseID: override.catalogExerciseID
                )
            )
        }
    }

    func testReportedSearchExercisesUseVerifiedCatalogIDs() {
        XCTAssertEqual(
            ExerciseSeedMediaOverrides.override(
                forNormalizedName: ExerciseNameNormalizer.normalize("Deadlift")
            )?.catalogExerciseID,
            "ila4NZS"
        )
        XCTAssertEqual(
            ExerciseSeedMediaOverrides.override(
                forNormalizedName: ExerciseNameNormalizer.normalize("Dumbbell Bent-Over Row")
            )?.catalogExerciseID,
            "BJ0Hz5L"
        )
        XCTAssertEqual(
            ExerciseSeedMediaOverrides.override(
                forNormalizedName: ExerciseNameNormalizer.normalize("Rope Biceps Curl")
            )?.catalogExerciseID,
            nil
        )
        XCTAssertEqual(
            ExerciseSeedMediaOverrides.override(
                forNormalizedName: ExerciseNameNormalizer.normalize("Cable Curl")
            )?.catalogExerciseID,
            "G08RZcQ"
        )
    }

    @MainActor
    func testSeedRepairClearsPreviouslyAssignedWrongMedia() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let facePull = Exercise(
            name: "Face Pull",
            primaryMuscleGroup: .shoulders,
            equipment: .cable,
            instructions: "Instructions for a different row.",
            externalCatalogID: "G61cXLk",
            mediaURLString: "https://static.exercisedb.dev/media/G61cXLk.gif",
            sourceURLString: "https://ascendapi.com",
            sourceName: "ExerciseDB by AscendAPI"
        )
        context.insert(facePull)
        try context.save()

        _ = try ExerciseSeedService.seedIfNeeded(in: context)

        XCTAssertNil(facePull.externalCatalogID)
        XCTAssertNil(facePull.mediaURLString)
        XCTAssertTrue(facePull.instructions.isEmpty)
        XCTAssertNil(facePull.sourceName)
        XCTAssertNil(facePull.sourceURLString)
        XCTAssertFalse(facePull.isArchived)
    }
}
