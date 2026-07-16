import CryptoKit
import Foundation
import SwiftData

struct BundledExerciseCatalogManifest: Codable, Equatable, Sendable {
    struct Source: Codable, Equatable, Sendable {
        let name: String
        let url: String
        let revision: String
        let sourceSHA256: String
        let license: String
        let licenseURL: String
    }

    let schemaVersion: Int
    let catalogVersion: String
    let publishedAt: String
    let payloadFilename: String
    let itemCount: Int
    let payloadSHA256: String
    let source: Source
}

struct BundledExerciseCatalogPayload: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let exercises: [BundledExerciseCatalogRecord]
}

struct BundledExerciseCatalogRecord: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let primaryMuscleGroup: String
    let secondaryMuscleGroups: [String]
    let equipment: String
    let measurementType: String
    let searchAliases: [String]
}

struct BundledExerciseCatalogImportSummary: Equatable, Sendable {
    let catalogVersion: String
    let totalItems: Int
    let insertedItems: Int
    let mergedItems: Int
    let updatedItems: Int
    let retiredItems: Int
}

enum BundledExerciseCatalogError: LocalizedError, Equatable {
    case missingResource(String)
    case unreadableResource(String)
    case invalidManifest
    case unsupportedSchema(Int)
    case invalidPayloadFilename
    case checksumMismatch
    case itemCountMismatch(expected: Int, actual: Int)
    case duplicateID(String)
    case duplicateName(String)
    case invalidRecord(id: String, field: String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            "The offline exercise catalog is missing \(name)."
        case .unreadableResource(let name):
            "The offline exercise catalog couldn’t read \(name)."
        case .invalidManifest:
            "The offline exercise catalog manifest is invalid."
        case .unsupportedSchema(let version):
            "The offline exercise catalog uses unsupported schema \(version)."
        case .invalidPayloadFilename:
            "The offline exercise catalog references an invalid payload filename."
        case .checksumMismatch:
            "The offline exercise catalog failed its integrity check."
        case .itemCountMismatch(let expected, let actual):
            "The offline exercise catalog expected \(expected) exercises but found \(actual)."
        case .duplicateID(let id):
            "The offline exercise catalog contains duplicate ID \(id)."
        case .duplicateName(let name):
            "The offline exercise catalog contains duplicate name \(name)."
        case .invalidRecord(let id, let field):
            "Offline exercise \(id) has an invalid \(field)."
        }
    }
}

/// Imports Rep's immutable baseline catalog from the application bundle at launch.
///
/// The manifest count and SHA-256 are verified before SwiftData is mutated. Import is
/// idempotent, merges by stable ID then normalized name, and saves once so a fresh
/// installation has the full baseline without contacting an external service.
@MainActor
enum BundledExerciseCatalogService {
    static let manifestFilename = "rep-exercise-catalog-manifest-v1.json"
    static let supportedSchemaVersion = 1
    private static let importRevision = 1
    private static let installedCatalogKey = "rep.bundledExerciseCatalog.installedRevision"

    @discardableResult
    static func seedIfNeeded(
        in context: ModelContext,
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard
    ) throws -> BundledExerciseCatalogImportSummary {
        let manifestData = try resourceData(named: manifestFilename, in: bundle)
        let manifest: BundledExerciseCatalogManifest
        do {
            manifest = try JSONDecoder().decode(BundledExerciseCatalogManifest.self, from: manifestData)
        } catch {
            throw BundledExerciseCatalogError.invalidManifest
        }

        guard isSafeResourceFilename(manifest.payloadFilename) else {
            throw BundledExerciseCatalogError.invalidPayloadFilename
        }

        let installedRevision = "\(manifest.catalogVersion)|\(importRevision)"
        if defaults.string(forKey: installedCatalogKey) == installedRevision {
            let version = manifest.catalogVersion
            let descriptor = FetchDescriptor<Exercise>(
                predicate: #Predicate { exercise in
                    exercise.bundledCatalogVersion == version && exercise.isArchived == false
                }
            )
            if try context.fetchCount(descriptor) == manifest.itemCount {
                return BundledExerciseCatalogImportSummary(
                    catalogVersion: manifest.catalogVersion,
                    totalItems: manifest.itemCount,
                    insertedItems: 0,
                    mergedItems: manifest.itemCount,
                    updatedItems: 0,
                    retiredItems: 0
                )
            }
        }

        let payloadData = try resourceData(named: manifest.payloadFilename, in: bundle)
        let summary = try importCatalog(
            manifestData: manifestData,
            payloadData: payloadData,
            in: context
        )
        defaults.set(installedRevision, forKey: installedCatalogKey)
        return summary
    }

    @discardableResult
    static func importCatalog(
        manifestData: Data,
        payloadData: Data,
        in context: ModelContext
    ) throws -> BundledExerciseCatalogImportSummary {
        let validated = try validate(manifestData: manifestData, payloadData: payloadData)
        let manifest = validated.manifest
        let records = validated.payload.exercises

        let existing = try context.fetch(FetchDescriptor<Exercise>())
        var byBundledID: [String: Exercise] = [:]
        var byNormalizedName: [String: Exercise] = [:]
        for exercise in existing {
            if let id = exercise.bundledCatalogID, byBundledID[id] == nil {
                byBundledID[id] = exercise
            }
            let normalizedName = ExerciseNameNormalizer.normalize(exercise.name)
            if !exercise.isCustom, byNormalizedName[normalizedName] == nil {
                byNormalizedName[normalizedName] = exercise
            }
        }

        var insertedItems = 0
        var mergedItems = 0
        var updatedItems = 0
        var retiredItems = 0
        var incomingIDs = Set<String>()

        do {
            for record in records {
                let values = try domainValues(for: record)
                let normalizedName = ExerciseNameNormalizer.normalize(values.name)
                incomingIDs.insert(record.id)

                if let exercise = byBundledID[record.id] ?? byNormalizedName[normalizedName] {
                    let oldNormalizedName = ExerciseNameNormalizer.normalize(exercise.name)
                    let isAdoptingLegacyRecord = exercise.bundledCatalogID == nil
                        && LegacyExerciseDBDataRemovalService.isLegacyExerciseDBRecord(exercise)
                    var changed = false

                    changed = setIfChanged(exercise, \.bundledCatalogID, record.id) || changed

                    if isAdoptingLegacyRecord
                        || exercise.bundledCatalogVersion != manifest.catalogVersion {
                        changed = setIfChanged(exercise, \.name, values.name) || changed
                        changed = setIfChanged(exercise, \.normalizedName, normalizedName) || changed
                        changed = setIfChanged(exercise, \.primaryMuscleGroupRaw, values.primary.rawValue) || changed
                        changed = setIfChanged(exercise, \.secondaryMuscleGroupRaws, values.secondary.map(\.rawValue)) || changed
                        changed = setIfChanged(exercise, \.equipmentRaw, values.equipment.rawValue) || changed
                        changed = setIfChanged(exercise, \.measurementTypeRaw, values.measurement.rawValue) || changed
                        changed = setIfChanged(exercise, \.sourceName, manifest.source.name) || changed
                        changed = setIfChanged(exercise, \.sourceURLString, manifest.source.url) || changed
                        changed = setIfChanged(exercise, \.bundledCatalogVersion, manifest.catalogVersion) || changed
                    }
                    changed = setIfChanged(exercise, \.isArchived, false) || changed

                    if isAdoptingLegacyRecord {
                        changed = setIfChanged(exercise, \.instructions, "") || changed
                        changed = setIfChanged(exercise, \.externalCatalogID, nil) || changed
                        changed = setIfChanged(exercise, \.mediaURLString, nil) || changed
                    }

                    let aliases = isAdoptingLegacyRecord
                        ? values.aliases
                        : uniqueAliases(exercise.searchAliases + values.aliases)
                    changed = setIfChanged(exercise, \.searchAliases, aliases) || changed

                    if exercise.popularityRank == ExercisePopularity.unrankedRank,
                       let rank = ExercisePopularity.rank(forNormalizedName: normalizedName) {
                        exercise.popularityRank = rank
                        changed = true
                    }

                    if changed {
                        exercise.touch()
                        updatedItems += 1
                    }
                    mergedItems += 1
                    byBundledID[record.id] = exercise
                    if oldNormalizedName != exercise.normalizedName, byNormalizedName[oldNormalizedName]?.id == exercise.id {
                        byNormalizedName.removeValue(forKey: oldNormalizedName)
                    }
                    byNormalizedName[normalizedName] = exercise
                    continue
                }

                let exercise = Exercise(
                    name: values.name,
                    primaryMuscleGroup: values.primary,
                    secondaryMuscleGroups: values.secondary,
                    equipment: values.equipment,
                    measurementType: values.measurement,
                    bundledCatalogID: record.id,
                    bundledCatalogVersion: manifest.catalogVersion,
                    sourceURLString: manifest.source.url,
                    sourceName: manifest.source.name,
                    searchAliases: values.aliases,
                    popularityRank: ExercisePopularity.rank(for: values.name)
                )
                context.insert(exercise)
                insertedItems += 1
                byBundledID[record.id] = exercise
                byNormalizedName[exercise.normalizedName] = exercise
            }

            let referencedIDs = try referencedExerciseIDs(in: context)
            for exercise in existing {
                guard let catalogID = exercise.bundledCatalogID,
                      !incomingIDs.contains(catalogID)
                else { continue }
                if referencedIDs.contains(exercise.id) {
                    if !exercise.isArchived {
                        exercise.isArchived = true
                        exercise.touch()
                        retiredItems += 1
                    }
                } else {
                    context.delete(exercise)
                    retiredItems += 1
                }
            }

            if insertedItems > 0 || updatedItems > 0 || retiredItems > 0 {
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }

        return BundledExerciseCatalogImportSummary(
            catalogVersion: manifest.catalogVersion,
            totalItems: records.count,
            insertedItems: insertedItems,
            mergedItems: mergedItems,
            updatedItems: updatedItems,
            retiredItems: retiredItems
        )
    }

    static func validate(
        manifestData: Data,
        payloadData: Data
    ) throws -> (
        manifest: BundledExerciseCatalogManifest,
        payload: BundledExerciseCatalogPayload
    ) {
        let decoder = JSONDecoder()
        let manifest: BundledExerciseCatalogManifest
        let payload: BundledExerciseCatalogPayload
        do {
            manifest = try decoder.decode(BundledExerciseCatalogManifest.self, from: manifestData)
        } catch {
            throw BundledExerciseCatalogError.invalidManifest
        }

        guard manifest.schemaVersion == supportedSchemaVersion else {
            throw BundledExerciseCatalogError.unsupportedSchema(manifest.schemaVersion)
        }
        guard isSafeResourceFilename(manifest.payloadFilename) else {
            throw BundledExerciseCatalogError.invalidPayloadFilename
        }
        guard digest(of: payloadData) == manifest.payloadSHA256.lowercased() else {
            throw BundledExerciseCatalogError.checksumMismatch
        }

        do {
            payload = try decoder.decode(BundledExerciseCatalogPayload.self, from: payloadData)
        } catch {
            throw BundledExerciseCatalogError.invalidRecord(id: "payload", field: "JSON")
        }
        guard payload.schemaVersion == supportedSchemaVersion else {
            throw BundledExerciseCatalogError.unsupportedSchema(payload.schemaVersion)
        }
        guard payload.exercises.count == manifest.itemCount else {
            throw BundledExerciseCatalogError.itemCountMismatch(
                expected: manifest.itemCount,
                actual: payload.exercises.count
            )
        }

        var ids = Set<String>()
        var names = Set<String>()
        for record in payload.exercises {
            guard ids.insert(record.id).inserted else {
                throw BundledExerciseCatalogError.duplicateID(record.id)
            }
            let normalizedName = ExerciseNameNormalizer.normalize(record.name)
            guard names.insert(normalizedName).inserted else {
                throw BundledExerciseCatalogError.duplicateName(record.name)
            }
            _ = try domainValues(for: record)
        }

        return (manifest, payload)
    }
}

private extension BundledExerciseCatalogService {
    struct DomainValues {
        let name: String
        let primary: MuscleGroup
        let secondary: [MuscleGroup]
        let equipment: Equipment
        let measurement: MeasurementType
        let aliases: [String]
    }

    static func domainValues(for record: BundledExerciseCatalogRecord) throws -> DomainValues {
        let id = record.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw BundledExerciseCatalogError.invalidRecord(id: "unknown", field: "id")
        }
        guard !name.isEmpty else {
            throw BundledExerciseCatalogError.invalidRecord(id: id, field: "name")
        }
        guard let primary = MuscleGroup(rawValue: record.primaryMuscleGroup) else {
            throw BundledExerciseCatalogError.invalidRecord(id: id, field: "primaryMuscleGroup")
        }

        let secondary = try record.secondaryMuscleGroups.map { rawValue in
            guard let muscle = MuscleGroup(rawValue: rawValue) else {
                throw BundledExerciseCatalogError.invalidRecord(id: id, field: "secondaryMuscleGroups")
            }
            return muscle
        }
        guard Set(secondary).count == secondary.count, !secondary.contains(primary) else {
            throw BundledExerciseCatalogError.invalidRecord(id: id, field: "secondaryMuscleGroups")
        }
        guard let equipment = Equipment(rawValue: record.equipment) else {
            throw BundledExerciseCatalogError.invalidRecord(id: id, field: "equipment")
        }
        guard let measurement = MeasurementType(rawValue: record.measurementType) else {
            throw BundledExerciseCatalogError.invalidRecord(id: id, field: "measurementType")
        }

        return DomainValues(
            name: name,
            primary: primary,
            secondary: secondary,
            equipment: equipment,
            measurement: measurement,
            aliases: uniqueAliases(record.searchAliases)
        )
    }

    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isSafeResourceFilename(_ value: String) -> Bool {
        let path = NSString(string: value)
        return !value.isEmpty
            && path.lastPathComponent == value
            && path.pathExtension == "json"
    }

    static func resourceData(named filename: String, in bundle: Bundle) throws -> Data {
        let path = NSString(string: filename)
        let name = path.deletingPathExtension
        let extensionName = path.pathExtension
        let candidate = bundle.url(forResource: name, withExtension: extensionName, subdirectory: "Catalog")
            ?? bundle.url(forResource: name, withExtension: extensionName, subdirectory: "Resources/Catalog")
            ?? bundle.url(forResource: name, withExtension: extensionName)
        guard let url = candidate else {
            throw BundledExerciseCatalogError.missingResource(filename)
        }
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw BundledExerciseCatalogError.unreadableResource(filename)
        }
    }

    static func referencedExerciseIDs(in context: ModelContext) throws -> Set<UUID> {
        let routineExercises = try context.fetch(FetchDescriptor<RoutineExercise>())
        let workoutExercises = try context.fetch(FetchDescriptor<WorkoutExercise>())
        return Set(
            routineExercises.compactMap { $0.exercise?.id }
                + workoutExercises.compactMap { $0.exercise?.id }
        )
    }

    static func uniqueAliases(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let normalized = ExerciseNameNormalizer.normalize(trimmed)
            return seen.insert(normalized).inserted ? trimmed : nil
        }
    }

    static func setIfChanged<T: Equatable>(
        _ exercise: Exercise,
        _ keyPath: ReferenceWritableKeyPath<Exercise, T>,
        _ value: T
    ) -> Bool {
        guard exercise[keyPath: keyPath] != value else { return false }
        exercise[keyPath: keyPath] = value
        return true
    }
}
