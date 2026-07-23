import Foundation
import SwiftData
import Testing
@testable import Rep

@Suite("Exercise help video catalog", .serialized)
@MainActor
struct ExerciseHelpVideoCatalogTests {
    @Test("Resolves mappings by AscendAPI exercise ID")
    func resolvesByExerciseID() throws {
        let catalog = try sampleCatalog()
        let exercise = Exercise(
            name: "Barbell Bench Press",
            primaryMuscleGroup: .chest,
            equipment: .barbell,
            externalCatalogID: "EIeI8Vf"
        )

        let mapping = try #require(catalog.mapping(for: exercise))
        #expect(mapping.exerciseId == "EIeI8Vf")
        #expect(mapping.youtubeVideoId == "rT7DgCr-3pg")
    }

    @Test("Uses strict name and equipment fallback when IDs are absent")
    func resolvesFallbackMatch() throws {
        let catalog = try sampleCatalog()
        let exercise = Exercise(
            name: "Lat Pulldown",
            primaryMuscleGroup: .back,
            equipment: .cable
        )

        let mapping = try #require(catalog.fallbackMapping(for: exercise))
        #expect(mapping.exerciseName == "Lat Pulldown")
        #expect(mapping.equipment == "cable")
    }

    @Test("Rejects fallback when equipment differs")
    func rejectsEquipmentMismatch() throws {
        let catalog = try sampleCatalog()
        let exercise = Exercise(
            name: "Lat Pulldown",
            primaryMuscleGroup: .back,
            equipment: .machine
        )

        #expect(catalog.fallbackMapping(for: exercise) == nil)
    }

    @Test("Leaves exercises without reviewed mappings untouched")
    func leavesMissingMappingsEmpty() throws {
        let catalog = try sampleCatalog()
        let exercise = Exercise(
            name: "Unknown Movement",
            primaryMuscleGroup: .other,
            equipment: .other
        )

        #expect(catalog.mapping(for: exercise) == nil)
    }

    @Test("Rejects malformed catalog payloads")
    func rejectsMalformedJSON() {
        let data = Data("{".utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(ExerciseHelpVideoCatalogPayload.self, from: data)
        }
    }

    @Test("Rejects invalid YouTube IDs in reviewed mappings")
    func rejectsInvalidYouTubeID() {
        let payload = ExerciseHelpVideoCatalogPayload(
            schemaVersion: 1,
            catalogVersion: "test",
            publishedAt: "2026-07-14T00:00:00Z",
            ascendApiExerciseCount: 1,
            mappings: [
                ExerciseHelpVideoMapping(
                    exerciseId: "bad",
                    bundledCatalogID: nil,
                    exerciseName: "Bad Mapping",
                    equipment: "barbell",
                    youtubeVideoId: "not-a-real-id",
                    title: "Bad",
                    channel: "Bad",
                    verifiedAt: "2026-07-14"
                )
            ]
        )

        #expect(throws: ExerciseHelpVideoCatalogError.invalidMapping(field: "youtubeVideoId", exerciseId: "bad")) {
            _ = try ExerciseHelpVideoCatalog(payload: payload)
        }
    }

    @Test("Backfills persisted exercises without touching custom records")
    func backfillsExistingRecords() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)

        let catalogExercise = Exercise(
            name: "Barbell Bench Press",
            primaryMuscleGroup: .chest,
            equipment: .barbell,
            externalCatalogID: "EIeI8Vf"
        )
        let customExercise = Exercise(
            name: "My Press",
            primaryMuscleGroup: .chest,
            equipment: .barbell,
            isCustom: true
        )
        context.insert(catalogExercise)
        context.insert(customExercise)

        let catalog = try sampleCatalog()
        let summary = try ExerciseHelpVideoEnrichmentService.enrichAll(in: context, catalog: catalog)

        #expect(summary.updatedExercises == 1)
        #expect(summary.skippedCustomExercises == 1)
        #expect(catalogExercise.helpYouTubeVideoID == "rT7DgCr-3pg")
        #expect(catalogExercise.helpVideoChannel == "ScottHermanFitness")
        #expect(customExercise.helpYouTubeVideoID == nil)
        #expect(
            ExerciseHelpVideoCatalog.thumbnailURL(forVideoID: "rT7DgCr-3pg")?.absoluteString
                == "https://i.ytimg.com/vi/rT7DgCr-3pg/hqdefault.jpg"
        )
    }

    @Test("Loads the shipped catalog from the application bundle")
    func loadsShippedCatalog() throws {
        let catalog = try ExerciseHelpVideoCatalog.load(bundle: .main)
        #expect(catalog.payload.schemaVersion == 1)
        #expect(!catalog.payload.mappings.isEmpty)
        #expect(catalog.payload.ascendApiExerciseCount == 1_500)
    }

    private func sampleCatalog() throws -> ExerciseHelpVideoCatalog {
        let payload = ExerciseHelpVideoCatalogPayload(
            schemaVersion: 1,
            catalogVersion: "test",
            publishedAt: "2026-07-14T00:00:00Z",
            ascendApiExerciseCount: 1_500,
            mappings: [
                ExerciseHelpVideoMapping(
                    exerciseId: "EIeI8Vf",
                    bundledCatalogID: nil,
                    exerciseName: "Barbell Bench Press",
                    equipment: "barbell",
                    youtubeVideoId: "rT7DgCr-3pg",
                    title: "How To: Barbell Bench Press",
                    channel: "ScottHermanFitness",
                    verifiedAt: "2026-07-14"
                ),
                ExerciseHelpVideoMapping(
                    exerciseId: "rep:local:lat-pulldown",
                    bundledCatalogID: nil,
                    exerciseName: "Lat Pulldown",
                    equipment: "cable",
                    youtubeVideoId: "CAwf7n6Luuc",
                    title: "How To: Lat Pulldown | 3 GOLDEN RULES",
                    channel: "ScottHermanFitness",
                    verifiedAt: "2026-07-14"
                ),
                ExerciseHelpVideoMapping(
                    exerciseId: "rep:local:bench-press-dumbbell",
                    bundledCatalogID: nil,
                    exerciseName: "Dumbbell Bench Press",
                    equipment: "barbell",
                    youtubeVideoId: "VmB1G1K7v94",
                    title: "Wrong equipment mapping",
                    channel: "ScottHermanFitness",
                    verifiedAt: "2026-07-14"
                )
            ]
        )
        return try ExerciseHelpVideoCatalog(payload: payload)
    }
}
