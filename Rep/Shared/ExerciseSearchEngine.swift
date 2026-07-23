import Foundation

/// A small, deterministic search index tuned for an exercise picker.
///
/// Name matches are strongest, followed by aliases, muscle groups, and equipment.
/// Matching every word in a query is rewarded heavily, while useful partial matches
/// remain available below the complete matches.
enum ExerciseSearchEngine {
    /// Ranks exercises for the picker.
    ///
    /// - When the query is empty, exercises are ordered by popularity: the user's own
    ///   usage first, then curated public popularity, then alphabetically.
    /// - When the query is present, match relevance dominates and popularity/usage act
    ///   only as tie-breakers so a strong text match is never buried under a popular one.
    ///
    /// `usage` maps an exercise id to how many times the user has logged it.
    static func search(
        _ exercises: [Exercise],
        query: String,
        usage: [UUID: Int] = [:]
    ) -> [Exercise] {
        let queryPhrase = normalize(query)
        guard !queryPhrase.isEmpty else {
            return exercises
                .map { RankedExercise(exercise: $0, score: 0) }
                .sorted { orderedBefore($0, $1, usage: usage) }
                .map(\.exercise)
        }

        let queryTokens = tokens(in: queryPhrase)
        guard !queryTokens.isEmpty else { return [] }

        return exercises.compactMap { exercise -> RankedExercise? in
            let score = score(SearchDocument(exercise), queryPhrase: queryPhrase, queryTokens: queryTokens)
            return score > 0 ? RankedExercise(exercise: exercise, score: score) : nil
        }
        .sorted { orderedBefore($0, $1, usage: usage) }
        .map(\.exercise)
    }

    /// Shared ranking order: relevance, then user usage, then public popularity, then name.
    static func orderedBefore(
        _ lhs: RankedExercise,
        _ rhs: RankedExercise,
        usage: [UUID: Int]
    ) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }

        let leftUsage = usage[lhs.exercise.id] ?? 0
        let rightUsage = usage[rhs.exercise.id] ?? 0
        if leftUsage != rightUsage { return leftUsage > rightUsage }

        if lhs.exercise.popularityRank != rhs.exercise.popularityRank {
            return lhs.exercise.popularityRank < rhs.exercise.popularityRank
        }
        return alphabeticalOrder(lhs.exercise, rhs.exercise)
    }

    struct RankedExercise {
        let exercise: Exercise
        let score: Int
    }

    struct SearchDocument {
        let namePhrase: String
        let nameCompact: String
        let nameTokens: [String]
        let aliasPhrases: [String]
        let aliasCompacts: [String]
        let aliasTokens: [String]
        let muscleTokens: [String]
        let equipmentTokens: [String]
        let tokenCompactPhrases: [String]
        /// All normalized tokens joined for cheap substring pre-filtering.
        let searchableBlob: String
        let searchableCompact: String

        init(_ exercise: Exercise) {
            namePhrase = normalize(exercise.name)
            nameCompact = compact(namePhrase)
            nameTokens = tokens(in: namePhrase)
            aliasPhrases = exercise.searchAliases.map(normalize).filter { !$0.isEmpty }
            aliasCompacts = aliasPhrases.map(compact)
            aliasTokens = aliasPhrases.flatMap(tokens)
            muscleTokens = tokens(in: exercise.primaryMuscleGroup.displayName)
                + exercise.secondaryMuscleGroups.flatMap { tokens(in: $0.displayName) }
            equipmentTokens = tokens(in: exercise.equipment.displayName)
            tokenCompactPhrases = Self.compactPhrases(from: nameTokens)
                + aliasPhrases.flatMap { Self.compactPhrases(from: tokens(in: $0)) }
            searchableBlob = ([namePhrase] + aliasPhrases + muscleTokens + equipmentTokens)
                .joined(separator: " ")
            searchableCompact = ([nameCompact] + aliasCompacts + muscleTokens + equipmentTokens)
                .joined()
        }

        private static func compactPhrases(from tokens: [String]) -> [String] {
            guard !tokens.isEmpty else { return [] }
            var phrases: [String] = []
            for start in tokens.indices {
                var joined = ""
                for index in start..<tokens.count {
                    joined += tokens[index]
                    phrases.append(joined)
                }
            }
            return phrases
        }

        func mightMatch(queryPhrase: String, queryTokens: [String]) -> Bool {
            let queryCompact = compact(queryPhrase)

            if !queryCompact.isEmpty {
                if nameCompact.contains(queryCompact) { return true }
                if aliasCompacts.contains(where: { $0.contains(queryCompact) }) { return true }
                if tokenCompactPhrases.contains(where: { $0.contains(queryCompact) }) { return true }
                if searchableCompact.contains(queryCompact) { return true }
                if queryCompact.count >= 5,
                   isCloseTypo(queryCompact, nameCompact)
                    || aliasCompacts.contains(where: { isCloseTypo(queryCompact, $0) })
                    || tokenCompactPhrases.contains(where: { isCloseTypo(queryCompact, $0) }) {
                    return true
                }
            }

            if namePhrase.contains(queryPhrase) { return true }
            if aliasPhrases.contains(where: { $0.contains(queryPhrase) }) { return true }
            if searchableBlob.contains(queryPhrase) { return true }
            return queryTokens.allSatisfy { token in
                nameTokens.contains(where: { $0.hasPrefix(token) || $0.contains(token) })
                    || aliasTokens.contains(where: { $0.hasPrefix(token) || $0.contains(token) })
                    || muscleTokens.contains(where: { $0.hasPrefix(token) || $0.contains(token) })
                    || equipmentTokens.contains(where: { $0.hasPrefix(token) || $0.contains(token) })
            }
        }
    }

    static func score(
        _ document: SearchDocument,
        queryPhrase: String,
        queryTokens: [String]
    ) -> Int {
        var total = phraseScore(queryPhrase, document: document)
        var matchedTokenCount = 0

        for queryToken in queryTokens {
            let tokenScore = max(
                bestMatch(for: queryToken, candidates: document.nameTokens, weights: .name, allowFuzzy: queryToken.count >= 4),
                bestMatch(for: queryToken, candidates: document.aliasTokens, weights: .alias, allowFuzzy: queryToken.count >= 4),
                bestMatch(for: queryToken, candidates: document.muscleTokens, weights: .muscle, allowFuzzy: false),
                bestMatch(for: queryToken, candidates: document.equipmentTokens, weights: .equipment, allowFuzzy: false)
            )

            if tokenScore > 0 {
                matchedTokenCount += 1
                total += tokenScore
            }
        }

        guard matchedTokenCount > 0 || total > 0 else { return 0 }

        if matchedTokenCount == 0 {
            return max(total, 1)
        }

        if matchedTokenCount == queryTokens.count {
            total += 4_000 + (queryTokens.count * 100)
        } else {
            // Keep partial matches useful, but always below comparably strong matches
            // that explain the whole query.
            total -= (queryTokens.count - matchedTokenCount) * 125
        }

        return max(total, 1)
    }

    private static func phraseScore(_ query: String, document: SearchDocument) -> Int {
        if document.namePhrase == query { return 10_000 }
        if document.aliasPhrases.contains(query) { return 10_000 }
        // A query that equals a whole name token (e.g. "squat" in "Back Squat") should
        // not lose to a name-prefix match on a longer first token (e.g. "Squat Jerk").
        if document.nameTokens.contains(query) { return 3_200 }
        if document.namePhrase.hasPrefix(query) { return 3_000 }
        if document.namePhrase.contains(query) { return 2_200 }
        if document.aliasPhrases.contains(where: { $0.hasPrefix(query) }) { return 1_900 }
        if document.aliasPhrases.contains(where: { $0.contains(query) }) { return 1_400 }

        let queryCompact = compact(query)
        guard !queryCompact.isEmpty else { return 0 }

        if document.nameCompact == queryCompact { return 9_800 }
        if document.aliasCompacts.contains(queryCompact) { return 8_300 }
        if document.nameCompact.hasPrefix(queryCompact) { return 2_900 }
        if document.nameCompact.contains(queryCompact) { return 2_100 }
        if document.aliasCompacts.contains(where: { $0.hasPrefix(queryCompact) }) { return 1_850 }
        if document.aliasCompacts.contains(where: { $0.contains(queryCompact) }) { return 1_350 }

        if let phraseScore = bestCompactPhraseScore(queryCompact, phrases: document.tokenCompactPhrases) {
            return phraseScore
        }

        if queryCompact.count >= 5 {
            if isCloseTypo(queryCompact, document.nameCompact) {
                return 1_750 - (editDistance(queryCompact, document.nameCompact) * 35)
            }
            if let alias = document.aliasCompacts.first(where: { isCloseTypo(queryCompact, $0) }) {
                return 1_550 - (editDistance(queryCompact, alias) * 35)
            }
        }

        return 0
    }

    private static func bestCompactPhraseScore(_ queryCompact: String, phrases: [String]) -> Int? {
        var best: Int?
        for phrase in phrases {
            let score: Int
            if phrase == queryCompact {
                score = 9_200
            } else if phrase.hasPrefix(queryCompact) {
                score = 2_750
            } else if phrase.contains(queryCompact) {
                score = 2_050
            } else if queryCompact.count >= 5, isCloseTypo(queryCompact, phrase) {
                score = 1_800 - (editDistance(queryCompact, phrase) * 35)
            } else {
                score = 0
            }
            if score > 0 {
                best = max(best ?? 0, score)
            }
        }
        return best
    }

    private struct MatchWeights {
        let exact: Int
        let prefix: Int
        let substring: Int
        let fuzzy: Int

        static let name = MatchWeights(exact: 700, prefix: 560, substring: 400, fuzzy: 340)
        static let alias = MatchWeights(exact: 620, prefix: 500, substring: 350, fuzzy: 300)
        static let muscle = MatchWeights(exact: 300, prefix: 240, substring: 180, fuzzy: 130)
        static let equipment = MatchWeights(exact: 250, prefix: 200, substring: 150, fuzzy: 110)
    }

    private static func bestMatch(
        for query: String,
        candidates: [String],
        weights: MatchWeights,
        allowFuzzy: Bool
    ) -> Int {
        candidates.reduce(into: 0) { best, candidate in
            let score: Int
            if candidate == query {
                score = weights.exact
            } else if candidate.hasPrefix(query) {
                score = weights.prefix + prefixCloseness(query: query, candidate: candidate)
            } else if query.count >= 2, candidate.contains(query) {
                score = weights.substring
            } else if allowFuzzy, isCloseTypo(query, candidate) {
                score = weights.fuzzy - (editDistance(query, candidate) * 25)
            } else {
                score = 0
            }
            best = max(best, score)
        }
    }

    private static func prefixCloseness(query: String, candidate: String) -> Int {
        max(0, 40 - ((candidate.count - query.count) * 4))
    }

    private static func isCloseTypo(_ query: String, _ candidate: String) -> Bool {
        guard query.count >= 3, candidate.count >= 3 else { return false }
        let longestCount = max(query.count, candidate.count)
        let allowedDistance: Int
        switch longestCount {
        case ..<6:
            allowedDistance = 1
        case 6..<10:
            allowedDistance = 2
        default:
            allowedDistance = min(4, max(3, longestCount / 3))
        }
        guard abs(query.count - candidate.count) <= allowedDistance else { return false }
        return editDistance(query, candidate) <= allowedDistance
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftIndex + 1
            for (rightIndex, rightCharacter) in right.enumerated() {
                let substitutionCost = leftCharacter == rightCharacter ? 0 : 1
                current[rightIndex + 1] = min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + substitutionCost
                )
            }
            previous = current
        }
        return previous[right.count]
    }

    static func normalize(_ value: String) -> String {
        ExerciseNameNormalizer.normalize(value)
    }

    static func tokens(in value: String) -> [String] {
        normalize(value).split(separator: " ").map(String.init)
    }

    static func compact(_ value: String) -> String {
        normalize(value).replacingOccurrences(of: " ", with: "")
    }

    private static func alphabeticalOrder(_ lhs: Exercise, _ rhs: Exercise) -> Bool {
        let leftName = normalize(lhs.name)
        let rightName = normalize(rhs.name)
        if leftName != rightName { return leftName < rightName }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// A stateful wrapper over ``ExerciseSearchEngine`` that caches the per-exercise search
/// documents so typing does not re-tokenize the whole catalog on every keystroke.
///
/// Documents are keyed by exercise id and invalidated when an exercise's `updatedAt`
/// changes, so catalog syncs and edits stay correct while repeated searches over an
/// unchanged catalog are cheap.
@MainActor
final class ExerciseSearchIndex {
    private struct Entry {
        let updatedAt: Date
        let document: ExerciseSearchEngine.SearchDocument
    }

    private var cache: [UUID: Entry] = [:]
    private var browseOrderIDs: [UUID] = []
    private var browseOrderKey: UInt64 = 0
    private var cachedCandidates: [SearchCandidate] = []
    private var candidatesKey: UInt64 = 0

    func invalidateBrowseOrder() {
        browseOrderIDs = []
        browseOrderKey = 0
        cachedCandidates = []
        candidatesKey = 0
    }

    func rebuildDocuments(for exercises: [Exercise]) {
        cache.removeAll(keepingCapacity: true)
        for exercise in exercises {
            cache[exercise.id] = Entry(
                updatedAt: exercise.updatedAt,
                document: ExerciseSearchEngine.SearchDocument(exercise)
            )
        }
    }

    func browseOrder(for exercises: [Exercise], usage: [UUID: Int], limit: Int) -> [Exercise] {
        let key = browseKey(for: exercises, usage: usage)
        if browseOrderKey == key, !browseOrderIDs.isEmpty {
            return resolve(ids: browseOrderIDs, from: exercises, limit: limit)
        }

        var top: [ExerciseSearchEngine.RankedExercise] = []
        top.reserveCapacity(limit)

        for exercise in exercises {
            let candidate = ExerciseSearchEngine.RankedExercise(exercise: exercise, score: 0)
            if top.count < limit {
                top.append(candidate)
                if top.count == limit {
                    top.sort { ExerciseSearchEngine.orderedBefore($0, $1, usage: usage) }
                }
                continue
            }
            guard let worst = top.last else { continue }
            if ExerciseSearchEngine.orderedBefore(candidate, worst, usage: usage) {
                let index = top.firstIndex {
                    ExerciseSearchEngine.orderedBefore(candidate, $0, usage: usage)
                } ?? top.count
                top.insert(candidate, at: index)
                top.removeLast()
            }
        }

        if top.count > 1, top.count < limit {
            top.sort { ExerciseSearchEngine.orderedBefore($0, $1, usage: usage) }
        }
        browseOrderKey = key
        browseOrderIDs = top.map(\.exercise.id)
        return top.map(\.exercise)
    }

    private func resolve(ids: [UUID], from exercises: [Exercise], limit: Int) -> [Exercise] {
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        var results: [Exercise] = []
        results.reserveCapacity(min(limit, ids.count))
        for id in ids where results.count < limit {
            if let exercise = byID[id] { results.append(exercise) }
        }
        return results
    }

    func search(
        for exercises: [Exercise],
        query: String,
        usage: [UUID: Int],
        limit: Int
    ) -> [Exercise] {
        let queryPhrase = ExerciseSearchEngine.normalize(query)
        guard !queryPhrase.isEmpty else {
            return browseOrder(for: exercises, usage: usage, limit: limit)
        }

        let queryTokens = ExerciseSearchEngine.tokens(in: queryPhrase)
        guard !queryTokens.isEmpty else { return [] }

        var ranked: [ExerciseSearchEngine.RankedExercise] = []
        ranked.reserveCapacity(min(limit * 2, exercises.count))

        for exercise in exercises {
            let document = document(for: exercise)
            guard document.mightMatch(queryPhrase: queryPhrase, queryTokens: queryTokens) else { continue }
            let score = ExerciseSearchEngine.score(document, queryPhrase: queryPhrase, queryTokens: queryTokens)
            guard score > 0 else { continue }
            ranked.append(ExerciseSearchEngine.RankedExercise(exercise: exercise, score: score))
        }

        ranked.sort { ExerciseSearchEngine.orderedBefore($0, $1, usage: usage) }
        if ranked.count > limit {
            ranked.removeSubrange(limit...)
        }
        return ranked.map(\.exercise)
    }

    func candidates(for exercises: [Exercise]) -> [SearchCandidate] {
        let key = catalogKey(for: exercises)
        if candidatesKey == key, !cachedCandidates.isEmpty {
            return cachedCandidates
        }

        cachedCandidates = exercises.map { exercise in
            let document = document(for: exercise)
            return SearchCandidate(
                id: exercise.id,
                document: document,
                popularityRank: exercise.popularityRank,
                namePhrase: ExerciseSearchEngine.normalize(exercise.name),
                prefixKeys: Self.prefixKeys(for: document)
            )
        }
        candidatesKey = key
        return cachedCandidates
    }

    private static func prefixKeys(for document: ExerciseSearchEngine.SearchDocument) -> [String] {
        var keys = Set<String>()
        let pools = document.nameTokens + document.aliasTokens + document.muscleTokens + document.equipmentTokens
        for token in pools where token.count >= 2 {
            keys.insert(String(token.prefix(2)))
        }
        let compact = document.nameCompact
        if compact.count >= 2 {
            keys.insert(String(compact.prefix(2)))
        }
        return Array(keys)
    }

    func prewarm(for exercises: [Exercise]) {
        _ = candidates(for: exercises)
    }

    func resolve(ids: [UUID], from exercises: [Exercise]) -> [Exercise] {
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    private func document(for exercise: Exercise) -> ExerciseSearchEngine.SearchDocument {
        if let entry = cache[exercise.id], entry.updatedAt == exercise.updatedAt {
            return entry.document
        }
        let document = ExerciseSearchEngine.SearchDocument(exercise)
        cache[exercise.id] = Entry(updatedAt: exercise.updatedAt, document: document)
        return document
    }

    private func catalogKey(for exercises: [Exercise]) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(exercises.count)
        if let newest = exercises.max(by: { $0.updatedAt < $1.updatedAt }) {
            hasher.combine(newest.updatedAt)
        }
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    private func browseKey(for exercises: [Exercise], usage: [UUID: Int]) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(exercises.count)
        hasher.combine(usage.count)
        if let peakUsage = usage.values.max() { hasher.combine(peakUsage) }
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }
}

struct SearchCandidate: Sendable {
    let id: UUID
    let document: ExerciseSearchEngine.SearchDocument
    let popularityRank: Int
    let namePhrase: String
    /// First two characters of every searchable token — used to skip cold scans.
    let prefixKeys: [String]
}

extension ExerciseSearchEngine {
    static func searchIDs(
        _ candidates: [SearchCandidate],
        query: String,
        usage: [UUID: Int] = [:],
        limit: Int
    ) -> [UUID] {
        (try? searchIDsCancellable(candidates, query: query, usage: usage, limit: limit)) ?? []
    }

    static func searchIDsCancellable(
        _ candidates: [SearchCandidate],
        query: String,
        usage: [UUID: Int] = [:],
        limit: Int
    ) throws -> [UUID] {
        try Task.checkCancellation()
        let queryPhrase = normalize(query)
        guard !queryPhrase.isEmpty else { return [] }

        let queryTokens = tokens(in: queryPhrase)
        guard !queryTokens.isEmpty else { return [] }

        let scoped = scopedCandidates(candidates, queryTokens: queryTokens)
        var ranked: [RankedSearchID] = []
        ranked.reserveCapacity(min(limit * 2, scoped.count))

        for (index, candidate) in scoped.enumerated() {
            if index.isMultiple(of: 32) {
                try Task.checkCancellation()
            }
            guard candidate.document.mightMatch(queryPhrase: queryPhrase, queryTokens: queryTokens) else {
                continue
            }
            let score = score(candidate.document, queryPhrase: queryPhrase, queryTokens: queryTokens)
            guard score > 0 else { continue }
            ranked.append(
                RankedSearchID(
                    id: candidate.id,
                    score: score,
                    usage: usage[candidate.id] ?? 0,
                    popularityRank: candidate.popularityRank,
                    namePhrase: candidate.namePhrase
                )
            )
        }

        try Task.checkCancellation()
        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.usage != rhs.usage { return lhs.usage > rhs.usage }
            if lhs.popularityRank != rhs.popularityRank { return lhs.popularityRank < rhs.popularityRank }
            return lhs.namePhrase < rhs.namePhrase
        }

        if ranked.count > limit {
            ranked.removeSubrange(limit...)
        }
        try Task.checkCancellation()
        return ranked.map(\.id)
    }

    /// Prefer candidates whose tokens share a 2-char prefix with the query.
    private static func scopedCandidates(
        _ candidates: [SearchCandidate],
        queryTokens: [String]
    ) -> [SearchCandidate] {
        guard let first = queryTokens.first, first.count >= 2 else { return candidates }
        let key = String(first.prefix(2))
        let filtered = candidates.filter { $0.prefixKeys.contains(key) }
        // Fall back if the prefix index is too aggressive (typos / short aliases).
        return filtered.count >= 8 ? filtered : candidates
    }

    private struct RankedSearchID: Sendable {
        let id: UUID
        let score: Int
        let usage: Int
        let popularityRank: Int
        let namePhrase: String
    }
}
