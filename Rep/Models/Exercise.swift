import Foundation
import SwiftData

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var normalizedName: String
    var primaryMuscleGroupRaw: String
    var secondaryMuscleGroupRaws: [String]
    var equipmentRaw: String
    var measurementTypeRaw: String
    var isCustom: Bool
    var isArchived: Bool
    var instructions: String
    /// User-authored notes for custom/local context. Catalog guidance belongs in
    /// `instructions`, which lets licensing migrations clear imported guidance
    /// without erasing notes the user wrote after this field existed.
    var userNotes: String?
    var videoAssetIdentifier: String?
    /// Stable identity from Rep's versioned, app-bundled catalog.
    var bundledCatalogID: String?
    /// Catalog release that last supplied this record's canonical metadata.
    /// Nil means an existing curated, imported, or user-created record won a name merge.
    var bundledCatalogVersion: String?
    var externalCatalogID: String?
    var mediaURLString: String?
    var sourceURLString: String?
    var sourceName: String?
    var searchAliases: [String] = []
    /// Lower is more popular. A large sentinel keeps unranked exercises after ranked
    /// ones without needing an optional. Curated common lifts get small ranks.
    var popularityRank: Int = ExercisePopularity.unrankedRank
    var createdAt: Date
    var updatedAt: Date

    var primaryMuscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: primaryMuscleGroupRaw) ?? .other }
        set { primaryMuscleGroupRaw = newValue.rawValue; touch() }
    }

    var secondaryMuscleGroups: [MuscleGroup] {
        get { secondaryMuscleGroupRaws.compactMap(MuscleGroup.init(rawValue:)) }
        set { secondaryMuscleGroupRaws = newValue.map(\.rawValue); touch() }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue; touch() }
    }

    var measurementType: MeasurementType {
        get { MeasurementType(rawValue: measurementTypeRaw) ?? .custom }
        set { measurementTypeRaw = newValue.rawValue; touch() }
    }

    init(
        id: UUID = UUID(),
        name: String,
        primaryMuscleGroup: MuscleGroup,
        secondaryMuscleGroups: [MuscleGroup] = [],
        equipment: Equipment,
        measurementType: MeasurementType = .weightAndRepetitions,
        isCustom: Bool = false,
        isArchived: Bool = false,
        instructions: String = "",
        userNotes: String? = nil,
        videoAssetIdentifier: String? = nil,
        bundledCatalogID: String? = nil,
        bundledCatalogVersion: String? = nil,
        externalCatalogID: String? = nil,
        mediaURLString: String? = nil,
        sourceURLString: String? = nil,
        sourceName: String? = nil,
        searchAliases: [String] = [],
        popularityRank: Int = ExercisePopularity.unrankedRank,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedName = ExerciseNameNormalizer.normalize(name)
        primaryMuscleGroupRaw = primaryMuscleGroup.rawValue
        secondaryMuscleGroupRaws = secondaryMuscleGroups.map(\.rawValue)
        equipmentRaw = equipment.rawValue
        measurementTypeRaw = measurementType.rawValue
        self.isCustom = isCustom
        self.isArchived = isArchived
        self.instructions = instructions
        self.userNotes = userNotes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.videoAssetIdentifier = videoAssetIdentifier
        self.bundledCatalogID = bundledCatalogID
        self.bundledCatalogVersion = bundledCatalogVersion
        self.externalCatalogID = externalCatalogID
        self.mediaURLString = mediaURLString
        self.sourceURLString = sourceURLString
        self.sourceName = sourceName
        self.searchAliases = searchAliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.popularityRank = popularityRank
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    func rename(to newName: String, at date: Date = .now) {
        name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedName = ExerciseNameNormalizer.normalize(newName)
        updatedAt = date
    }

    func touch(at date: Date = .now) { updatedAt = date }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
