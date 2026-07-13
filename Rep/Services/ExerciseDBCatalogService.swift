import Foundation
import Observation
import SwiftData

// MARK: - ExerciseDB wire format

/// The public ExerciseDB response format. These types intentionally stay separate
/// from the SwiftData model so an upstream API change cannot leak into persistence.
struct ExerciseDBPageResponse: Codable, Sendable, Equatable {
    let success: Bool
    let meta: ExerciseDBPageMetadata
    let data: [ExerciseDBExerciseDTO]
}

struct ExerciseDBPageMetadata: Codable, Sendable, Equatable {
    let total: Int
    let hasNextPage: Bool
    let hasPreviousPage: Bool
    let nextCursor: String?
    let previousCursor: String?
}

struct ExerciseDBExerciseDTO: Codable, Sendable, Equatable {
    let exerciseId: String
    let name: String
    let gifUrl: String
    let bodyParts: [String]
    let equipments: [String]
    let targetMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]
}

// MARK: - Public synchronization state

struct ExerciseCatalogSyncProgress: Sendable, Equatable {
    let completedItems: Int
    let totalItems: Int
    let completedPages: Int
    let insertedItems: Int
    let enrichedItems: Int

    var fractionCompleted: Double {
        guard totalItems > 0 else { return 0 }
        return min(1, Double(completedItems) / Double(totalItems))
    }
}

struct ExerciseCatalogSyncSummary: Sendable, Equatable {
    let totalItems: Int
    let insertedItems: Int
    let enrichedItems: Int
    let didSkipCompletedCatalog: Bool
}

enum ExerciseCatalogSyncState: Sendable, Equatable {
    case idle
    case syncing(ExerciseCatalogSyncProgress)
    case complete(ExerciseCatalogSyncProgress)
    case failed(String)
}

enum ExerciseCatalogError: LocalizedError, Sendable, Equatable {
    case alreadySyncing
    case invalidSearchQuery
    case invalidResponse
    case unsuccessfulResponse
    case http(statusCode: Int, message: String?)
    case stalledPagination

    var errorDescription: String? {
        switch self {
        case .alreadySyncing:
            "The exercise catalog is already syncing."
        case .invalidSearchQuery:
            "Enter an exercise name to search the catalog."
        case .invalidResponse:
            "ExerciseDB returned an invalid response."
        case .unsuccessfulResponse:
            "ExerciseDB could not complete the request."
        case let .http(statusCode, message):
            message.map { "ExerciseDB returned HTTP \(statusCode): \($0)" }
                ?? "ExerciseDB returned HTTP \(statusCode)."
        case .stalledPagination:
            "ExerciseDB pagination stopped before the catalog was complete."
        }
    }
}

/// Downloads the free ExerciseDB catalog and incrementally merges it into SwiftData.
///
/// Every page is saved before its cursor is checkpointed. A cancelled or failed sync
/// therefore resumes at the last durable page and never needs to hold all 1,500
/// exercises in memory. Search imports can safely run while the background sync is
/// awaiting its next network page because every merge re-reads the current index.
@MainActor
@Observable
final class ExerciseDBCatalogService {
    typealias ProgressHandler = @MainActor (ExerciseCatalogSyncProgress) -> Void

    private(set) var state: ExerciseCatalogSyncState = .idle

    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let decoder: JSONDecoder

    private let pageSize = 25
    private let baseURL = URL(string: "https://oss.exercisedb.dev/api/v1/exercises")!

    private static let sourceName = "ExerciseDB by AscendAPI"
    private static let sourceURLString = "https://ascendapi.com"

    private enum CheckpointKey {
        static let prefix = "exerciseDB.catalog.v1."
        static let isComplete = prefix + "isComplete"
        static let nextCursor = prefix + "nextCursor"
        static let processedCount = prefix + "processedCount"
        static let expectedCount = prefix + "expectedCount"
        static let storedRecordCount = prefix + "storedRecordCount"
    }

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        decoder = JSONDecoder()
    }

    /// Synchronizes every ExerciseDB page. Pass `force: true` only for a user-requested
    /// refresh; ordinary launches cheaply skip a catalog that is already durable.
    @discardableResult
    func synchronize(
        in context: ModelContext,
        force: Bool = false,
        progress progressHandler: ProgressHandler? = nil
    ) async throws -> ExerciseCatalogSyncSummary {
        if case .syncing = state { throw ExerciseCatalogError.alreadySyncing }

        if force {
            resetCheckpoint()
        } else if try catalogIsAlreadyComplete(in: context) {
            let total = defaults.integer(forKey: CheckpointKey.expectedCount)
            let finished = ExerciseCatalogSyncProgress(
                completedItems: total,
                totalItems: total,
                completedPages: pageCount(for: total),
                insertedItems: 0,
                enrichedItems: 0
            )
            state = .complete(finished)
            progressHandler?(finished)
            return ExerciseCatalogSyncSummary(
                totalItems: total,
                insertedItems: 0,
                enrichedItems: 0,
                didSkipCompletedCatalog: true
            )
        }

        var cursor = defaults.string(forKey: CheckpointKey.nextCursor)
        var completedItems = defaults.integer(forKey: CheckpointKey.processedCount)
        var totalItems = defaults.integer(forKey: CheckpointKey.expectedCount)
        var completedPages = pageCount(for: completedItems)
        var insertedItems = 0
        var enrichedItems = 0
        var cursorsSeen = Set<String>()
        if let cursor { cursorsSeen.insert(cursor) }

        let initial = ExerciseCatalogSyncProgress(
            completedItems: completedItems,
            totalItems: totalItems,
            completedPages: completedPages,
            insertedItems: insertedItems,
            enrichedItems: enrichedItems
        )
        state = .syncing(initial)
        progressHandler?(initial)

        do {
            while true {
                try Task.checkCancellation()
                let page = try await fetchPage(after: cursor, matchingName: nil)
                guard page.success else { throw ExerciseCatalogError.unsuccessfulResponse }
                guard !page.data.isEmpty || !page.meta.hasNextPage else {
                    throw ExerciseCatalogError.stalledPagination
                }

                let result = try merge(page.data, into: context)
                try context.save()

                totalItems = page.meta.total
                completedItems = min(totalItems, completedItems + page.data.count)
                completedPages += 1
                insertedItems += result.inserted
                enrichedItems += result.enriched

                // Save first, then advance the checkpoint. Replaying a page after an
                // interruption is safe because merge keys on external ID and name.
                defaults.set(totalItems, forKey: CheckpointKey.expectedCount)
                defaults.set(completedItems, forKey: CheckpointKey.processedCount)
                if let nextCursor = page.meta.nextCursor, page.meta.hasNextPage {
                    defaults.set(nextCursor, forKey: CheckpointKey.nextCursor)
                } else {
                    defaults.removeObject(forKey: CheckpointKey.nextCursor)
                }

                let current = ExerciseCatalogSyncProgress(
                    completedItems: completedItems,
                    totalItems: totalItems,
                    completedPages: completedPages,
                    insertedItems: insertedItems,
                    enrichedItems: enrichedItems
                )
                state = .syncing(current)
                progressHandler?(current)

                guard page.meta.hasNextPage else {
                    defaults.set(true, forKey: CheckpointKey.isComplete)
                    defaults.set(try catalogRecordCount(in: context), forKey: CheckpointKey.storedRecordCount)
                    state = .complete(current)
                    return ExerciseCatalogSyncSummary(
                        totalItems: totalItems,
                        insertedItems: insertedItems,
                        enrichedItems: enrichedItems,
                        didSkipCompletedCatalog: false
                    )
                }

                guard let nextCursor = page.meta.nextCursor,
                      !nextCursor.isEmpty,
                      cursorsSeen.insert(nextCursor).inserted
                else {
                    throw ExerciseCatalogError.stalledPagination
                }
                cursor = nextCursor
            }
        } catch is CancellationError {
            state = .idle
            throw CancellationError()
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Imports the first page of server-side fuzzy name matches. This makes uncommon
    /// searches useful immediately instead of waiting for the full background sync.
    /// The API's documented fuzzy parameter is named `name` (not `search`).
    @discardableResult
    func searchAndImport(query: String, in context: ModelContext) async throws -> Int {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw ExerciseCatalogError.invalidSearchQuery }
        try Task.checkCancellation()

        let page = try await fetchPage(after: nil, matchingName: query)
        guard page.success else { throw ExerciseCatalogError.unsuccessfulResponse }
        let result = try merge(page.data, into: context)
        try context.save()
        return result.inserted + result.enriched
    }

    /// Finds the closest server-side name match and adds its form media/instructions
    /// to one existing exercise. Nothing is fetched when media is already available.
    @discardableResult
    func enrichIfNeeded(_ exercise: Exercise, in context: ModelContext) async throws -> Bool {
        guard exercise.mediaURLString?.isEmpty != false else { return false }
        let candidates = try await searchCandidates(for: exercise.name, maximumPages: 8)
        guard let match = bestCandidate(for: exercise, from: candidates) else { return false }

        let allExercises = try context.fetch(FetchDescriptor<Exercise>())
        if let owner = allExercises.first(where: { $0.externalCatalogID == match.exerciseId }),
           owner.id != exercise.id {
            return false
        }

        let didChange = enrich(exercise, from: match, preserveCuratedClassification: true)
        if didChange { try context.save() }
        return didChange
    }

    // This spelling makes the intent discoverable at call sites without breaking the
    // concise API above.
    @discardableResult
    func enrichExerciseIfNeeded(_ exercise: Exercise, in context: ModelContext) async throws -> Bool {
        try await enrichIfNeeded(exercise, in: context)
    }

    /// Copies form media (and any missing instructions) from already-imported catalog
    /// exercises onto exercises that still lack media, matching purely on local name
    /// tokens. This gives curated seed exercises artwork after a catalog sync without
    /// any extra network requests, so common lifts stop showing a blank thumbnail.
    @discardableResult
    func backfillMissingMediaLocally(in context: ModelContext) throws -> Int {
        let all = try context.fetch(FetchDescriptor<Exercise>())
        let donors: [(tokens: Set<String>, exercise: Exercise)] = all.compactMap { exercise in
            guard exercise.mediaURLString?.isEmpty == false else { return nil }
            let tokens = Set(normalizedSearchText(exercise.name).split(separator: " ").map(String.init))
            guard !tokens.isEmpty else { return nil }
            return (tokens, exercise)
        }
        guard !donors.isEmpty else { return 0 }

        var changed = 0
        for recipient in all where recipient.mediaURLString?.isEmpty != false {
            let wantedTokens = Set(normalizedSearchText(recipient.name).split(separator: " ").map(String.init))
            guard !wantedTokens.isEmpty else { continue }

            let candidates = donors.filter { $0.exercise.id != recipient.id && wantedTokens.isSubset(of: $0.tokens) }
            guard let match = candidates.min(by: { lhs, rhs in
                localMatchCost(recipient: recipient, wantedTokens: wantedTokens, donor: lhs)
                    < localMatchCost(recipient: recipient, wantedTokens: wantedTokens, donor: rhs)
            }) else { continue }

            guard let media = match.exercise.mediaURLString, !media.isEmpty else { continue }
            recipient.mediaURLString = media
            if recipient.instructions.isEmpty, !match.exercise.instructions.isEmpty {
                recipient.instructions = match.exercise.instructions
            }
            recipient.touch()
            changed += 1
        }

        if changed > 0 { try context.save() }
        return changed
    }

    /// Lower is a closer match: fewest extra donor tokens wins, with equipment and
    /// primary-muscle agreement breaking ties.
    private func localMatchCost(
        recipient: Exercise,
        wantedTokens: Set<String>,
        donor: (tokens: Set<String>, exercise: Exercise)
    ) -> Int {
        var cost = (donor.tokens.count - wantedTokens.count) * 10
        if donor.exercise.equipment != recipient.equipment { cost += 4 }
        if donor.exercise.primaryMuscleGroup != recipient.primaryMuscleGroup { cost += 2 }
        return cost
    }
}

// MARK: - Networking

private extension ExerciseDBCatalogService {
    struct APIErrorEnvelope: Decodable {
        struct Detail: Decodable {
            let message: String?
        }
        let error: Detail?
    }

    func fetchPage(after cursor: String?, matchingName name: String?) async throws -> ExerciseDBPageResponse {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem(name: "limit", value: String(pageSize))]
        if let cursor, !cursor.isEmpty {
            query.append(URLQueryItem(name: "after", value: cursor))
        }
        if let name, !name.isEmpty {
            query.append(URLQueryItem(name: "name", value: name))
        }
        components.queryItems = query
        guard let url = components.url else { throw ExerciseCatalogError.invalidResponse }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ExerciseCatalogError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    if isRetryable(http.statusCode), attempt < 3 {
                        attempt += 1
                        try await retryDelay(attempt: attempt, response: http)
                        continue
                    }
                    let message = try? decoder.decode(APIErrorEnvelope.self, from: data).error?.message
                    throw ExerciseCatalogError.http(statusCode: http.statusCode, message: message)
                }
                do {
                    return try decoder.decode(ExerciseDBPageResponse.self, from: data)
                } catch {
                    throw ExerciseCatalogError.invalidResponse
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ExerciseCatalogError {
                throw error
            } catch {
                if attempt < 3 {
                    attempt += 1
                    try await retryDelay(attempt: attempt, response: nil)
                    continue
                }
                throw error
            }
        }
    }

    func searchCandidates(for name: String, maximumPages: Int) async throws -> [ExerciseDBExerciseDTO] {
        var matches: [ExerciseDBExerciseDTO] = []
        var cursor: String?
        var seen = Set<String>()

        for _ in 0..<maximumPages {
            try Task.checkCancellation()
            let page = try await fetchPage(after: cursor, matchingName: name)
            guard page.success else { throw ExerciseCatalogError.unsuccessfulResponse }
            matches.append(contentsOf: page.data)

            // An exact match cannot be improved by reading more fuzzy pages.
            let normalizedName = ExerciseNameNormalizer.normalize(name)
            if matches.contains(where: { ExerciseNameNormalizer.normalize($0.name) == normalizedName }) {
                break
            }
            guard page.meta.hasNextPage,
                  let next = page.meta.nextCursor,
                  seen.insert(next).inserted
            else { break }
            cursor = next
        }
        return matches
    }

    func isRetryable(_ statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }

    func retryDelay(attempt: Int, response: HTTPURLResponse?) async throws {
        let retryAfter = response?
            .value(forHTTPHeaderField: "Retry-After")
            .flatMap(TimeInterval.init)
        let seconds = min(30, max(0.25, retryAfter ?? pow(2, Double(attempt - 1))))
        try await Task.sleep(for: .seconds(seconds))
    }
}

// MARK: - Durable merge

private extension ExerciseDBCatalogService {
    struct MergeResult {
        var inserted = 0
        var enriched = 0
    }

    func merge(_ remoteExercises: [ExerciseDBExerciseDTO], into context: ModelContext) throws -> MergeResult {
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        var byExternalID: [String: Exercise] = [:]
        var byNormalizedName: [String: Exercise] = [:]
        for exercise in existing {
            if let externalID = exercise.externalCatalogID, byExternalID[externalID] == nil {
                byExternalID[externalID] = exercise
            }
            if byNormalizedName[exercise.normalizedName] == nil {
                byNormalizedName[exercise.normalizedName] = exercise
            }
        }

        var result = MergeResult()
        for remote in remoteExercises {
            try Task.checkCancellation()
            let normalizedName = ExerciseNameNormalizer.normalize(remote.name)

            if let exercise = byExternalID[remote.exerciseId] ?? byNormalizedName[normalizedName] {
                if enrich(exercise, from: remote, preserveCuratedClassification: true) {
                    result.enriched += 1
                }
                byExternalID[remote.exerciseId] = exercise
                byNormalizedName[normalizedName] = exercise
                continue
            }

            let mapped = mappedClassification(for: remote)
            let name = displayName(for: remote.name)
            let exercise = Exercise(
                name: name,
                primaryMuscleGroup: mapped.primaryMuscle,
                secondaryMuscleGroups: mapped.secondaryMuscles,
                equipment: mapped.equipment,
                measurementType: mapped.measurement,
                instructions: joinedInstructions(remote.instructions),
                externalCatalogID: remote.exerciseId,
                mediaURLString: validatedMediaURLString(remote.gifUrl),
                sourceURLString: Self.sourceURLString,
                sourceName: Self.sourceName,
                searchAliases: aliases(for: remote, mapped: mapped),
                popularityRank: ExercisePopularity.rank(for: name)
            )
            context.insert(exercise)
            byExternalID[remote.exerciseId] = exercise
            byNormalizedName[normalizedName] = exercise
            result.inserted += 1
        }
        return result
    }

    @discardableResult
    func enrich(
        _ exercise: Exercise,
        from remote: ExerciseDBExerciseDTO,
        preserveCuratedClassification: Bool
    ) -> Bool {
        let mapped = mappedClassification(for: remote)
        let wasCatalogExercise = exercise.externalCatalogID != nil
        var changed = false

        func setIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<Exercise, T>, _ value: T) {
            guard exercise[keyPath: keyPath] != value else { return }
            exercise[keyPath: keyPath] = value
            changed = true
        }

        setIfChanged(\.externalCatalogID, remote.exerciseId)
        setIfChanged(\.sourceName, Self.sourceName)
        setIfChanged(\.sourceURLString, Self.sourceURLString)

        if exercise.popularityRank == ExercisePopularity.unrankedRank,
           let rank = ExercisePopularity.rank(forNormalizedName: exercise.normalizedName) {
            setIfChanged(\.popularityRank, rank)
        }

        if let mediaURL = validatedMediaURLString(remote.gifUrl),
           wasCatalogExercise || exercise.mediaURLString?.isEmpty != false {
            setIfChanged(\.mediaURLString, mediaURL)
        }

        let remoteInstructions = joinedInstructions(remote.instructions)
        if !remoteInstructions.isEmpty, wasCatalogExercise || exercise.instructions.isEmpty {
            setIfChanged(\.instructions, remoteInstructions)
        }

        let combinedAliases = uniqueAliases(
            exercise.searchAliases + aliases(for: remote, mapped: mapped)
        )
        setIfChanged(\.searchAliases, combinedAliases)

        if preserveCuratedClassification {
            let combinedSecondary = uniqueMuscles(
                exercise.secondaryMuscleGroups + mapped.secondaryMuscles
                    + (mapped.primaryMuscle == exercise.primaryMuscleGroup ? [] : [mapped.primaryMuscle])
            ).filter { $0 != exercise.primaryMuscleGroup }
            let secondaryRaws = combinedSecondary.map(\.rawValue)
            setIfChanged(\.secondaryMuscleGroupRaws, secondaryRaws)
        } else {
            setIfChanged(\.primaryMuscleGroupRaw, mapped.primaryMuscle.rawValue)
            setIfChanged(\.secondaryMuscleGroupRaws, mapped.secondaryMuscles.map(\.rawValue))
            setIfChanged(\.equipmentRaw, mapped.equipment.rawValue)
            setIfChanged(\.measurementTypeRaw, mapped.measurement.rawValue)
        }

        if changed { exercise.touch() }
        return changed
    }

    func bestCandidate(for exercise: Exercise, from candidates: [ExerciseDBExerciseDTO]) -> ExerciseDBExerciseDTO? {
        let wantedName = normalizedSearchText(exercise.name)
        let wantedTokens = Set(wantedName.split(separator: " ").map(String.init))

        guard let best = candidates.max(by: { lhs, rhs in
            candidateScore(lhs, exercise: exercise, wantedName: wantedName, wantedTokens: wantedTokens)
                < candidateScore(rhs, exercise: exercise, wantedName: wantedName, wantedTokens: wantedTokens)
        }) else { return nil }

        // Fuzzy server queries can return a loosely related tail of results. Never
        // attach form media unless the name/classification provides real evidence.
        let score = candidateScore(
            best,
            exercise: exercise,
            wantedName: wantedName,
            wantedTokens: wantedTokens
        )
        return score >= 200 ? best : nil
    }

    func candidateScore(
        _ candidate: ExerciseDBExerciseDTO,
        exercise: Exercise,
        wantedName: String,
        wantedTokens: Set<String>
    ) -> Int {
        let candidateName = normalizedSearchText(candidate.name)
        let candidateTokens = Set(candidateName.split(separator: " ").map(String.init))
        var score = wantedTokens.intersection(candidateTokens).count * 100
        if candidateName == wantedName { score += 10_000 }
        else if candidateName.hasPrefix(wantedName) || wantedName.hasPrefix(candidateName) { score += 1_000 }
        else if candidateName.contains(wantedName) { score += 500 }

        let mapped = mappedClassification(for: candidate)
        if mapped.equipment == exercise.equipment { score += 80 }
        if mapped.primaryMuscle == exercise.primaryMuscleGroup
            || mapped.secondaryMuscles.contains(exercise.primaryMuscleGroup) {
            score += 60
        }
        return score
    }

    func catalogRecordCount(in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<Exercise>()).lazy.filter {
            $0.externalCatalogID?.isEmpty == false
        }.count
    }

    func catalogIsAlreadyComplete(in context: ModelContext) throws -> Bool {
        guard defaults.bool(forKey: CheckpointKey.isComplete) else { return false }
        let storedCount = defaults.integer(forKey: CheckpointKey.storedRecordCount)
        guard storedCount > 0 else { return false }
        return try catalogRecordCount(in: context) >= storedCount
    }

    func resetCheckpoint() {
        defaults.removeObject(forKey: CheckpointKey.isComplete)
        defaults.removeObject(forKey: CheckpointKey.nextCursor)
        defaults.removeObject(forKey: CheckpointKey.processedCount)
        defaults.removeObject(forKey: CheckpointKey.expectedCount)
        defaults.removeObject(forKey: CheckpointKey.storedRecordCount)
    }

    func pageCount(for itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        return Int(ceil(Double(itemCount) / Double(pageSize)))
    }
}

// MARK: - Domain mapping

private extension ExerciseDBCatalogService {
    struct MappedClassification {
        let primaryMuscle: MuscleGroup
        let secondaryMuscles: [MuscleGroup]
        let equipment: Equipment
        let measurement: MeasurementType
    }

    func mappedClassification(for remote: ExerciseDBExerciseDTO) -> MappedClassification {
        let targets = remote.targetMuscles.compactMap(mapMuscle)
        let bodyParts = remote.bodyParts.compactMap(mapBodyPart)
        let primary = targets.first ?? bodyParts.first ?? .other
        let secondary = uniqueMuscles(
            Array(targets.dropFirst())
                + remote.secondaryMuscles.compactMap(mapMuscle)
                + bodyParts
        ).filter { $0 != primary }
        let equipment = mapEquipment(remote.equipments)
        let measurement = mapMeasurement(
            name: remote.name,
            bodyParts: remote.bodyParts,
            equipmentNames: remote.equipments,
            equipment: equipment
        )
        return MappedClassification(
            primaryMuscle: primary,
            secondaryMuscles: secondary,
            equipment: equipment,
            measurement: measurement
        )
    }

    func mapMuscle(_ rawValue: String) -> MuscleGroup? {
        switch normalizedSearchText(rawValue) {
        case "pectorals", "chest", "upper chest", "serratus anterior": .chest
        case "latissimus dorsi", "lats", "back", "upper back", "lower back", "spine",
             "trapezius", "traps", "rhomboids", "levator scapulae": .back
        case "deltoids", "delts", "rear deltoids", "shoulders", "rotator cuff": .shoulders
        case "biceps", "brachialis", "forearms", "wrist extensors", "wrist flexors",
             "wrists", "hands", "grip muscles": .biceps
        case "triceps": .triceps
        case "quadriceps", "quads", "hip flexors", "adductors", "abductors", "inner thighs", "groin": .quadriceps
        case "hamstrings": .hamstrings
        case "glutes": .glutes
        case "calves", "soleus", "shins", "ankles", "ankle stabilizers", "feet": .calves
        case "abs", "abdominals", "lower abs", "core", "obliques": .core
        case "cardiovascular system": .fullBody
        case "sternocleidomastoid": .other
        default: nil
        }
    }

    func mapBodyPart(_ rawValue: String) -> MuscleGroup? {
        switch normalizedSearchText(rawValue) {
        case "chest": .chest
        case "back": .back
        case "shoulders": .shoulders
        case "upper arms", "lower arms": .biceps
        case "upper legs": .quadriceps
        case "lower legs": .calves
        case "waist": .core
        case "cardio": .fullBody
        case "neck": .other
        default: nil
        }
    }

    func mapEquipment(_ rawValues: [String]) -> Equipment {
        let values = rawValues.map(normalizedSearchText)
        if values.contains("smith machine") { return .smithMachine }
        if values.contains("kettlebell") { return .kettlebell }
        if values.contains("dumbbell") { return .dumbbell }
        if values.contains(where: { $0 == "barbell" || $0 == "olympic barbell" || $0 == "ez barbell" || $0 == "trap bar" }) {
            return .barbell
        }
        if values.contains("cable") { return .cable }
        if values.contains("body weight") { return .bodyweight }
        if values.contains("assisted") || values.contains(where: { $0.contains("machine") }) { return .machine }
        return .other
    }

    func mapMeasurement(
        name: String,
        bodyParts: [String],
        equipmentNames: [String],
        equipment: Equipment
    ) -> MeasurementType {
        let normalizedName = normalizedSearchText(name)
        let normalizedEquipment = equipmentNames.map(normalizedSearchText)
        if normalizedEquipment.contains("assisted") { return .assistedBodyweight }
        if bodyParts.map(normalizedSearchText).contains("cardio") { return .distanceAndDuration }
        if equipment == .bodyweight {
            if normalizedName.contains("weighted") { return .bodyweightPlusAddedWeight }
            let timedTerms = ["plank", "hold", "stretch", "pose", "wall sit", "isometric", "yoga"]
            if timedTerms.contains(where: normalizedName.contains) { return .duration }
            return .bodyweightAndRepetitions
        }
        return .weightAndRepetitions
    }

    func aliases(for remote: ExerciseDBExerciseDTO, mapped: MappedClassification) -> [String] {
        var aliases = remote.bodyParts
            + remote.equipments
            + remote.targetMuscles
            + remote.secondaryMuscles
            + [mapped.primaryMuscle.displayName, mapped.equipment.displayName]
            + mapped.secondaryMuscles.map(\.displayName)

        let terms = Set(aliases.map(normalizedSearchText))
        if !terms.isDisjoint(with: ["pectorals", "chest", "upper chest"]) { aliases += ["pecs", "chest"] }
        if !terms.isDisjoint(with: ["latissimus dorsi", "lats", "upper back", "lower back", "spine"]) { aliases += ["back", "lats"] }
        if !terms.isDisjoint(with: ["abs", "abdominals", "lower abs", "obliques", "waist"]) { aliases += ["abs", "core"] }
        if !terms.isDisjoint(with: ["quadriceps", "quads", "upper legs"]) { aliases += ["quads", "legs"] }
        if terms.contains("body weight") { aliases.append("bodyweight") }
        if terms.contains("deltoids") || terms.contains("delts") { aliases += ["delts", "shoulders"] }
        return uniqueAliases(aliases)
    }

    func uniqueMuscles(_ muscles: [MuscleGroup]) -> [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        return muscles.filter { seen.insert($0).inserted }
    }

    func uniqueAliases(_ aliases: [String]) -> [String] {
        var seen = Set<String>()
        return aliases.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return seen.insert(normalizedSearchText(trimmed)).inserted ? trimmed : nil
        }
    }

    func joinedInstructions(_ instructions: [String]) -> String {
        ExerciseInstructionFormatter.joined(from: instructions)
    }

    func validatedMediaURLString(_ value: String) -> String? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else { return nil }
        return url.absoluteString
    }

    func displayName(for rawName: String) -> String {
        rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized(with: Locale(identifier: "en_US_POSIX"))
    }

    func normalizedSearchText(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let sanitized = String(folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        })
        return sanitized
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }
}
