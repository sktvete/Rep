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
    var videoAssetIdentifier: String?
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
        videoAssetIdentifier: String? = nil,
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
        self.videoAssetIdentifier = videoAssetIdentifier
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
