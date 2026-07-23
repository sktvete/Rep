import Foundation

struct ExerciseHelpVideoMapping: Codable, Equatable, Sendable {
    let exerciseId: String
    let bundledCatalogID: String?
    let exerciseName: String
    let equipment: String?
    let youtubeVideoId: String
    let title: String
    let channel: String
    let verifiedAt: String
}

struct ExerciseHelpVideoCatalogPayload: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let catalogVersion: String
    let publishedAt: String
    let ascendApiExerciseCount: Int?
    let mappings: [ExerciseHelpVideoMapping]
}

enum ExerciseHelpVideoCatalogError: LocalizedError, Equatable {
    case missingResource
    case unreadableResource
    case invalidPayload
    case unsupportedSchema(Int)
    case duplicateExerciseID(String)
    case invalidMapping(field: String, exerciseId: String)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            "The exercise help video catalog is missing."
        case .unreadableResource:
            "The exercise help video catalog couldn't be read."
        case .invalidPayload:
            "The exercise help video catalog is invalid."
        case .unsupportedSchema(let version):
            "The exercise help video catalog uses unsupported schema \(version)."
        case .duplicateExerciseID(let id):
            "The exercise help video catalog contains duplicate exercise ID \(id)."
        case .invalidMapping(let field, let exerciseId):
            "Exercise help video mapping \(exerciseId) has an invalid \(field)."
        }
    }
}

struct ExerciseHelpVideoCatalog: Equatable, Sendable {
    let payload: ExerciseHelpVideoCatalogPayload
    private let byExerciseID: [String: ExerciseHelpVideoMapping]
    private let byBundledCatalogID: [String: ExerciseHelpVideoMapping]
    private let byNameAndEquipment: [String: ExerciseHelpVideoMapping]

    init(payload: ExerciseHelpVideoCatalogPayload) throws {
        self.payload = payload
        var exerciseIDs = Set<String>()
        var byExerciseID: [String: ExerciseHelpVideoMapping] = [:]
        var byBundledCatalogID: [String: ExerciseHelpVideoMapping] = [:]
        var byNameAndEquipment: [String: ExerciseHelpVideoMapping] = [:]

        for mapping in payload.mappings {
            let exerciseID = mapping.exerciseId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !exerciseID.isEmpty else {
                throw ExerciseHelpVideoCatalogError.invalidMapping(field: "exerciseId", exerciseId: "unknown")
            }
            guard exerciseIDs.insert(exerciseID).inserted else {
                throw ExerciseHelpVideoCatalogError.duplicateExerciseID(exerciseID)
            }
            guard ExerciseHelpVideoCatalog.isValidYouTubeVideoID(mapping.youtubeVideoId) else {
                throw ExerciseHelpVideoCatalogError.invalidMapping(field: "youtubeVideoId", exerciseId: exerciseID)
            }

            byExerciseID[exerciseID] = mapping
            if let bundledCatalogID = mapping.bundledCatalogID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !bundledCatalogID.isEmpty {
                byBundledCatalogID[bundledCatalogID] = mapping
            }
            if let equipment = mapping.equipment,
               let key = ExerciseHelpVideoCatalog.fallbackKey(name: mapping.exerciseName, equipment: equipment) {
                byNameAndEquipment[key] = mapping
            }
        }

        self.byExerciseID = byExerciseID
        self.byBundledCatalogID = byBundledCatalogID
        self.byNameAndEquipment = byNameAndEquipment
    }

    var mappedExerciseCount: Int { byExerciseID.count }

    func mapping(for exercise: Exercise) -> ExerciseHelpVideoMapping? {
        if let externalCatalogID = exercise.externalCatalogID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !externalCatalogID.isEmpty,
           let mapping = byExerciseID[externalCatalogID] {
            return mapping
        }

        if let bundledCatalogID = exercise.bundledCatalogID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundledCatalogID.isEmpty {
            if let mapping = byExerciseID[bundledCatalogID] {
                return mapping
            }
            if let mapping = byBundledCatalogID[bundledCatalogID] {
                return mapping
            }
        }

        return fallbackMapping(for: exercise)
    }

    func fallbackMapping(for exercise: Exercise) -> ExerciseHelpVideoMapping? {
        guard !exercise.isCustom else { return nil }
        guard let key = ExerciseHelpVideoCatalog.fallbackKey(
            name: exercise.name,
            equipment: exercise.equipmentRaw
        ) else { return nil }
        guard let mapping = byNameAndEquipment[key] else { return nil }
        guard mapping.equipment == exercise.equipmentRaw else { return nil }
        guard ExerciseNameNormalizer.normalize(mapping.exerciseName) == exercise.normalizedName else {
            return nil
        }
        return mapping
    }

    static func load(bundle: Bundle = .main) throws -> ExerciseHelpVideoCatalog {
        let filename = catalogFilename
        let path = NSString(string: filename)
        let name = path.deletingPathExtension
        let extensionName = path.pathExtension
        let candidate = bundle.url(forResource: name, withExtension: extensionName, subdirectory: "Catalog")
            ?? bundle.url(forResource: name, withExtension: extensionName, subdirectory: "Resources/Catalog")
            ?? bundle.url(forResource: name, withExtension: extensionName)
        guard let url = candidate else {
            throw ExerciseHelpVideoCatalogError.missingResource
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw ExerciseHelpVideoCatalogError.unreadableResource
        }

        let payload: ExerciseHelpVideoCatalogPayload
        do {
            payload = try JSONDecoder().decode(ExerciseHelpVideoCatalogPayload.self, from: data)
        } catch {
            throw ExerciseHelpVideoCatalogError.invalidPayload
        }
        guard payload.schemaVersion == supportedSchemaVersion else {
            throw ExerciseHelpVideoCatalogError.unsupportedSchema(payload.schemaVersion)
        }
        return try ExerciseHelpVideoCatalog(payload: payload)
    }

    static let catalogFilename = "exercise-help-videos-v1.json"
    static let supportedSchemaVersion = 1

    static func isValidYouTubeVideoID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...11).contains(trimmed.count) else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func fallbackKey(name: String, equipment: String) -> String? {
        let normalizedName = ExerciseNameNormalizer.normalize(name)
        let normalizedEquipment = equipment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, !normalizedEquipment.isEmpty else { return nil }
        return "\(normalizedName)|\(normalizedEquipment)"
    }

    static func watchURL(for mapping: ExerciseHelpVideoMapping) -> URL? {
        let videoID = mapping.youtubeVideoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidYouTubeVideoID(videoID) else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }

    static func thumbnailURL(forVideoID videoID: String) -> URL? {
        let trimmed = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidYouTubeVideoID(trimmed) else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(trimmed)/hqdefault.jpg")
    }
}
