import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Rep

@Suite("Bundled offline exercise catalog", .serialized)
@MainActor
struct BundledExerciseCatalogTests {
    @Test("The shipped catalog validates and imports all 873 records offline")
    func importsShippedCatalog() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)

        let first = try BundledExerciseCatalogService.seedIfNeeded(in: context, bundle: .main)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let originalIDs = Dictionary(uniqueKeysWithValues: exercises.compactMap { exercise in
            exercise.bundledCatalogID.map { ($0, exercise.id) }
        })

        #expect(first.catalogVersion == "2026.05.24.2")
        #expect(first.totalItems == 873)
        #expect(first.insertedItems == 873)
        #expect(originalIDs.count == 873)
        #expect(exercises.allSatisfy { $0.externalCatalogID == nil && $0.mediaURLString == nil })

        let second = try BundledExerciseCatalogService.seedIfNeeded(in: context, bundle: .main)
        let reloaded = try context.fetch(FetchDescriptor<Exercise>())

        #expect(second.insertedItems == 0)
        #expect(second.mergedItems == 873)
        #expect(second.updatedItems == 0)
        #expect(second.retiredItems == 0)
        #expect(Dictionary(uniqueKeysWithValues: reloaded.compactMap { exercise in
            exercise.bundledCatalogID.map { ($0, exercise.id) }
        }) == originalIDs)
    }

    @Test("A corrupt payload fails before SwiftData is mutated")
    func rejectsCorruptPayload() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let (manifest, payload) = try shippedResourceData()
        var corruptPayload = payload
        corruptPayload.append(0x20)

        do {
            _ = try BundledExerciseCatalogService.importCatalog(
                manifestData: manifest,
                payloadData: corruptPayload,
                in: context
            )
            Issue.record("Expected checksum validation to fail")
        } catch let error as BundledExerciseCatalogError {
            #expect(error == .checksumMismatch)
        }

        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 0)
    }

    @Test("Duplicate IDs and unknown domain values fail closed")
    func rejectsInvalidRecords() throws {
        let valid = BundledExerciseCatalogRecord(
            id: "rep:test:one",
            name: "Test Press",
            primaryMuscleGroup: MuscleGroup.chest.rawValue,
            secondaryMuscleGroups: [MuscleGroup.triceps.rawValue],
            equipment: Equipment.dumbbell.rawValue,
            measurementType: MeasurementType.weightAndRepetitions.rawValue,
            searchAliases: ["Press"]
        )

        let duplicateFixture = try fixture(records: [valid, valid])
        do {
            _ = try BundledExerciseCatalogService.validate(
                manifestData: duplicateFixture.manifest,
                payloadData: duplicateFixture.payload
            )
            Issue.record("Expected duplicate ID validation to fail")
        } catch let error as BundledExerciseCatalogError {
            #expect(error == .duplicateID(valid.id))
        }

        let invalid = BundledExerciseCatalogRecord(
            id: "rep:test:invalid",
            name: "Impossible Press",
            primaryMuscleGroup: "not-a-muscle",
            secondaryMuscleGroups: [],
            equipment: Equipment.other.rawValue,
            measurementType: MeasurementType.custom.rawValue,
            searchAliases: []
        )
        let invalidFixture = try fixture(records: [invalid])
        do {
            _ = try BundledExerciseCatalogService.validate(
                manifestData: invalidFixture.manifest,
                payloadData: invalidFixture.payload
            )
            Issue.record("Expected domain validation to fail")
        } catch let error as BundledExerciseCatalogError {
            #expect(error == .invalidRecord(id: invalid.id, field: "primaryMuscleGroup"))
        }
    }

    @Test("A matched legacy record converts in place without breaking relationships")
    func convertsMatchedLegacyRecord() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let exercise = Exercise(
            name: "3/4 Sit-Up",
            primaryMuscleGroup: .other,
            equipment: .other,
            instructions: "Provider instructions",
            externalCatalogID: "legacy-123",
            mediaURLString: "https://static.exercisedb.dev/media/legacy.gif",
            sourceURLString: "https://ascendapi.com",
            sourceName: "ExerciseDB by AscendAPI",
            searchAliases: ["provider-only"]
        )
        let originalID = exercise.id
        let routineItem = RoutineExercise(exercise: exercise)
        let routine = Routine(name: "Core", exercises: [routineItem])
        let workoutItem = WorkoutExercise(exercise: exercise)
        let workout = WorkoutSession(name: "Core", exercises: [workoutItem])
        context.insert(exercise)
        context.insert(routine)
        context.insert(workout)
        try context.save()

        _ = try BundledExerciseCatalogService.seedIfNeeded(in: context, bundle: .main)

        #expect(exercise.id == originalID)
        #expect(routineItem.exercise?.id == originalID)
        #expect(workoutItem.exercise?.id == originalID)
        #expect(exercise.bundledCatalogID == "rep:free-exercise-db:3_4_Sit-Up")
        #expect(exercise.bundledCatalogVersion == "2026.05.24.2")
        #expect(exercise.primaryMuscleGroup == .core)
        #expect(exercise.equipment == .bodyweight)
        #expect(exercise.externalCatalogID == nil)
        #expect(exercise.mediaURLString == nil)
        #expect(exercise.instructions.isEmpty)
        #expect(exercise.sourceName == "Free Exercise DB")
        #expect(!exercise.searchAliases.contains("provider-only"))
    }

    @Test("Legacy cleanup deletes unused data and archives minimal referenced identity")
    func removesUnmatchedLegacyData() async throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let referenced = Exercise(
            name: "Legacy Cable Unicorn",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.biceps],
            equipment: .cable,
            instructions: "Provider instructions",
            externalCatalogID: "legacy-referenced",
            mediaURLString: "https://static.exercisedb.dev/media/referenced.gif",
            sourceURLString: "https://ascendapi.com",
            sourceName: "ExerciseDB by AscendAPI",
            searchAliases: ["provider metadata"]
        )
        let unused = Exercise(
            name: "Unused Legacy Exercise",
            primaryMuscleGroup: .chest,
            equipment: .machine,
            externalCatalogID: "legacy-unused"
        )
        let mediaOnly = Exercise(
            name: "Media Backfill",
            primaryMuscleGroup: .shoulders,
            equipment: .dumbbell,
            instructions: "Copied instructions",
            mediaURLString: "https://static.exercisedb.dev/media/backfill.gif"
        )
        let item = RoutineExercise(exercise: referenced)
        let routine = Routine(name: "Legacy", exercises: [item])
        context.insert(referenced)
        context.insert(unused)
        context.insert(mediaOnly)
        context.insert(routine)
        try context.save()

        let summary = try await LegacyExerciseDBDataRemovalService.removeUnlicensedData(
            in: context,
            defaults: migrationDefaults(),
            clearSharedCaches: false
        )
        let remaining = try context.fetch(FetchDescriptor<Exercise>())

        #expect(summary.retainedUserReferences == 1)
        #expect(summary.deletedUnreferencedExercises == 2)
        #expect(remaining.map(\.id) == [referenced.id])
        #expect(item.exercise?.id == referenced.id)
        #expect(referenced.name == LegacyExerciseDBDataRemovalService.unavailableLegacyExerciseName)
        #expect(referenced.isCustom)
        #expect(referenced.isArchived)
        #expect(referenced.primaryMuscleGroup == .other)
        #expect(referenced.secondaryMuscleGroups.isEmpty)
        #expect(referenced.equipment == .other)
        #expect(referenced.measurementType == .custom)
        #expect(referenced.externalCatalogID == nil)
        #expect(referenced.mediaURLString == nil)
        #expect(referenced.sourceName == nil)
        #expect(referenced.sourceURLString == nil)
        #expect(referenced.instructions.isEmpty)
        #expect(referenced.searchAliases.isEmpty)
    }

    @Test("Legacy cleanup preserves custom rows but removes provider fields")
    func preservesCustomLegacyRows() async throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let custom = Exercise(
            name: "My Cable Row Variant",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.biceps],
            equipment: .cable,
            measurementType: .weightAndRepetitions,
            isCustom: true,
            instructions: "Possibly imported provider text",
            externalCatalogID: "legacy-custom",
            mediaURLString: "https://static.exercisedb.dev/media/custom.gif",
            sourceURLString: "https://ascendapi.com",
            sourceName: "ExerciseDB by AscendAPI",
            searchAliases: ["provider alias"]
        )
        let originalID = custom.id
        context.insert(custom)
        try context.save()

        let summary = try await LegacyExerciseDBDataRemovalService.removeUnlicensedData(
            in: context,
            defaults: migrationDefaults(),
            clearSharedCaches: false
        )

        #expect(summary.retainedCustomExercises == 1)
        #expect(summary.clearedAmbiguousCustomNotes == 1)
        #expect(custom.id == originalID)
        #expect(custom.name == "My Cable Row Variant")
        #expect(custom.primaryMuscleGroup == .back)
        #expect(custom.equipment == .cable)
        #expect(custom.measurementType == .weightAndRepetitions)
        #expect(custom.isCustom)
        #expect(!custom.isArchived)
        #expect(custom.externalCatalogID == nil)
        #expect(custom.mediaURLString == nil)
        #expect(custom.sourceName == nil)
        #expect(custom.sourceURLString == nil)
        #expect(custom.instructions.isEmpty)
        #expect(custom.searchAliases.isEmpty)
    }

    @Test("Custom rows do not win catalog name merges")
    func customRowsDoNotWinCatalogNameMerges() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let custom = Exercise(
            name: "3/4 Sit-Up",
            primaryMuscleGroup: .other,
            equipment: .other,
            isCustom: true
        )
        context.insert(custom)
        try context.save()

        let summary = try BundledExerciseCatalogService.seedIfNeeded(in: context, bundle: .main)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let bundled = try #require(exercises.first { $0.bundledCatalogID == "rep:free-exercise-db:3_4_Sit-Up" })

        #expect(summary.insertedItems == 873)
        #expect(custom.bundledCatalogID == nil)
        #expect(custom.primaryMuscleGroup == .other)
        #expect(bundled.id != custom.id)
        #expect(bundled.primaryMuscleGroup == .core)
    }

    @Test("Catalog import retires removed IDs without corrupting renamed records")
    func retiresRemovedCatalogIDs() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let oldRecord = BundledExerciseCatalogRecord(
            id: "rep:test:old",
            name: "Old Carry",
            primaryMuscleGroup: MuscleGroup.fullBody.rawValue,
            secondaryMuscleGroups: [],
            equipment: Equipment.other.rawValue,
            measurementType: MeasurementType.distanceAndDuration.rawValue,
            searchAliases: []
        )
        let newRecord = BundledExerciseCatalogRecord(
            id: "rep:test:new",
            name: "New Carry",
            primaryMuscleGroup: MuscleGroup.fullBody.rawValue,
            secondaryMuscleGroups: [],
            equipment: Equipment.other.rawValue,
            measurementType: MeasurementType.distanceAndDuration.rawValue,
            searchAliases: []
        )
        var first = try fixture(records: [oldRecord])
        _ = try BundledExerciseCatalogService.importCatalog(
            manifestData: first.manifest,
            payloadData: first.payload,
            in: context
        )
        let old = try #require(try context.fetch(FetchDescriptor<Exercise>()).first)
        let routineItem = RoutineExercise(exercise: old)
        context.insert(Routine(name: "Carry", exercises: [routineItem]))
        try context.save()

        first = try fixture(records: [newRecord])
        let summary = try BundledExerciseCatalogService.importCatalog(
            manifestData: first.manifest,
            payloadData: first.payload,
            in: context
        )

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(summary.retiredItems == 1)
        #expect(exercises.count == 2)
        #expect(old.isArchived)
        #expect(routineItem.exercise?.id == old.id)
        #expect(exercises.contains { $0.bundledCatalogID == "rep:test:new" && !$0.isArchived })
    }

    @Test("Reviewed carry and sprint records use distance and duration logging")
    func reviewedMeasurementOverrides() throws {
        let (_, payloadData) = try shippedResourceData()
        let payload = try JSONDecoder().decode(BundledExerciseCatalogPayload.self, from: payloadData)
        let byID = Dictionary(uniqueKeysWithValues: payload.exercises.map { ($0.id, $0.measurementType) })

        for sourceID in [
            "Farmers_Walk",
            "Wind_Sprints",
            "Yoke_Walk",
            "Sled_Push",
            "Rickshaw_Carry"
        ] {
            #expect(byID["rep:free-exercise-db:\(sourceID)"] == MeasurementType.distanceAndDuration.rawValue)
        }
    }
}

private extension BundledExerciseCatalogTests {
    func shippedResourceData() throws -> (manifest: Data, payload: Data) {
        let manifestURL = try #require(
            Bundle.main.url(
                forResource: "rep-exercise-catalog-manifest-v1",
                withExtension: "json"
            )
        )
        let payloadURL = try #require(
            Bundle.main.url(
                forResource: "rep-exercise-catalog-v1",
                withExtension: "json"
            )
        )
        return (try Data(contentsOf: manifestURL), try Data(contentsOf: payloadURL))
    }

    func fixture(
        records: [BundledExerciseCatalogRecord]
    ) throws -> (manifest: Data, payload: Data) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(
            BundledExerciseCatalogPayload(schemaVersion: 1, exercises: records)
        )
        let digest = SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()
        let manifest = BundledExerciseCatalogManifest(
            schemaVersion: 1,
            catalogVersion: "test.1",
            publishedAt: "2026-07-14T00:00:00Z",
            payloadFilename: "test-catalog.json",
            itemCount: records.count,
            payloadSHA256: digest,
            source: .init(
                name: "Test",
                url: "https://example.com/catalog",
                revision: "test",
                sourceSHA256: digest,
                license: "Test",
                licenseURL: "https://example.com/license"
            )
        )
        return (try encoder.encode(manifest), payload)
    }

    func migrationDefaults() -> UserDefaults {
        let suiteName = "RepTests.LegacyExerciseDBDataRemoval"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "rep.exerciseCatalog.removedExerciseDBData.v1")
        return defaults
    }
}
