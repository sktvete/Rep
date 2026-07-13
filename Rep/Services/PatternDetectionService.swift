import Foundation

struct PatternConfiguration: Sendable {
    var minimumObservations: Int
    var mediumConfidenceThreshold: Double
    var highConfidenceThreshold: Double
    var recencyHalfLifeDays: Double
    var fullEvidenceObservationCount: Int
    var dismissalConfidencePenalty: Double
    var suppressionDismissalCount: Int

    static let `default` = PatternConfiguration(
        minimumObservations: 3,
        mediumConfidenceThreshold: 0.55,
        highConfidenceThreshold: 0.75,
        recencyHalfLifeDays: 56,
        fullEvidenceObservationCount: 6,
        dismissalConfidencePenalty: 0.18,
        suppressionDismissalCount: 3
    )
}

struct RoutineSuggestion: Identifiable, Equatable, Sendable {
    let signature: String
    let routineID: UUID
    let type: PatternType
    let confidence: Double
    let observationCount: Int
    let lastObservedAt: Date
    let explanation: String

    var id: String { signature }
    var isHighConfidence: Bool { confidence >= PatternConfiguration.default.highConfidenceThreshold }
}

protocol PatternDetecting {
    func suggestion(
        for date: Date,
        sessions: [WorkoutSession],
        routines: [Routine],
        learnedPatterns: [LearnedPattern]
    ) -> RoutineSuggestion?
}

struct PatternDetectionService: PatternDetecting {
    private struct CompletedRoutine {
        let routineID: UUID
        let date: Date
    }

    private struct Candidate {
        let signature: String
        let routineID: UUID
        let type: PatternType
        let subjectID: UUID?
        let count: Int
        let totalCount: Int
        let weightedSupport: Double
        let weightedTotal: Double
        let lastObservedAt: Date
        let explanation: String
    }

    let configuration: PatternConfiguration
    let calendar: Calendar

    init(
        configuration: PatternConfiguration = .default,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.configuration = configuration
        self.calendar = calendar
    }

    func suggestion(
        for date: Date = .now,
        sessions: [WorkoutSession],
        routines: [Routine],
        learnedPatterns: [LearnedPattern] = []
    ) -> RoutineSuggestion? {
        let names = Dictionary(uniqueKeysWithValues: routines.map { ($0.id, $0.name) })
        let validRoutineIDs = Set(names.keys)
        let records = sessions.compactMap { session -> CompletedRoutine? in
            guard session.state == .completed,
                  let routineID = session.routineID,
                  validRoutineIDs.contains(routineID) else { return nil }
            let observedAt = session.completedAt ?? session.startedAt
            guard observedAt < date else { return nil }
            return CompletedRoutine(routineID: routineID, date: observedAt)
        }.sorted { $0.date < $1.date }

        var candidates: [Candidate] = []
        candidates.append(contentsOf: weekdayCandidates(for: date, records: records, names: names))
        candidates.append(contentsOf: transitionCandidates(for: date, records: records, names: names))
        candidates.append(contentsOf: rotationCandidates(for: date, records: records, names: names))

        return candidates.compactMap { candidate in
            surfacedSuggestion(from: candidate, learnedPatterns: learnedPatterns)
        }.max { lhs, rhs in
            if lhs.confidence != rhs.confidence { return lhs.confidence < rhs.confidence }
            if lhs.observationCount != rhs.observationCount { return lhs.observationCount < rhs.observationCount }
            return priority(lhs.type) < priority(rhs.type)
        }
    }

    func learnedPattern(from suggestion: RoutineSuggestion, createdAt: Date = .now) -> LearnedPattern {
        LearnedPattern(
            signature: suggestion.signature,
            type: suggestion.type,
            candidateID: suggestion.routineID,
            confidence: suggestion.confidence,
            supportingObservationCount: suggestion.observationCount,
            lastObservedAt: suggestion.lastObservedAt,
            explanation: suggestion.explanation,
            createdAt: createdAt
        )
    }

    private func weekdayCandidates(
        for date: Date,
        records: [CompletedRoutine],
        names: [UUID: String]
    ) -> [Candidate] {
        let weekday = calendar.component(.weekday, from: date)
        let observations = records.filter { calendar.component(.weekday, from: $0.date) == weekday }
        guard observations.count >= configuration.minimumObservations else { return [] }
        let totalWeight = observations.reduce(0.0) { $0 + recencyWeight(observedAt: $1.date, relativeTo: date) }
        let weekdayName = date.formatted(.dateTime.weekday(.wide).locale(calendar.locale ?? Locale(identifier: "en_US_POSIX")))

        return Dictionary(grouping: observations, by: \.routineID).compactMap { routineID, matches in
            guard matches.count >= configuration.minimumObservations, let name = names[routineID] else { return nil }
            let support = matches.reduce(0.0) { $0 + recencyWeight(observedAt: $1.date, relativeTo: date) }
            let signature = "weekday:\(weekday):\(routineID.uuidString)"
            return Candidate(
                signature: signature,
                routineID: routineID,
                type: .weekdayRoutine,
                subjectID: nil,
                count: matches.count,
                totalCount: observations.count,
                weightedSupport: support,
                weightedTotal: totalWeight,
                lastObservedAt: matches.map(\.date).max() ?? date,
                explanation: "You trained \(name) on \(matches.count) of your last \(observations.count) \(weekdayName)s."
            )
        }
    }

    private func transitionCandidates(
        for date: Date,
        records: [CompletedRoutine],
        names: [UUID: String]
    ) -> [Candidate] {
        guard let latest = records.last, records.count > 1 else { return [] }
        let transitions = zip(records.dropLast(), records.dropFirst()).filter { $0.0.routineID == latest.routineID }
        guard transitions.count >= configuration.minimumObservations,
              let latestName = names[latest.routineID] else { return [] }
        let totalWeight = transitions.reduce(0.0) { $0 + recencyWeight(observedAt: $1.1.date, relativeTo: date) }

        return Dictionary(grouping: transitions, by: { $0.1.routineID }).compactMap { routineID, matches in
            guard matches.count >= configuration.minimumObservations, let name = names[routineID] else { return nil }
            let support = matches.reduce(0.0) { $0 + recencyWeight(observedAt: $1.1.date, relativeTo: date) }
            return Candidate(
                signature: "transition:\(latest.routineID.uuidString):\(routineID.uuidString)",
                routineID: routineID,
                type: .routineTransition,
                subjectID: latest.routineID,
                count: matches.count,
                totalCount: transitions.count,
                weightedSupport: support,
                weightedTotal: totalWeight,
                lastObservedAt: matches.map { $0.1.date }.max() ?? date,
                explanation: "You usually perform \(name) after \(latestName) (\(matches.count) of \(transitions.count) times)."
            )
        }
    }

    private func rotationCandidates(
        for date: Date,
        records: [CompletedRoutine],
        names: [UUID: String]
    ) -> [Candidate] {
        guard records.count >= configuration.minimumObservations + 2 else { return [] }
        var candidates: [Candidate] = []

        for sequenceLength in 2...min(3, records.count - 1) {
            let suffix = Array(records.suffix(sequenceLength).map(\.routineID))
            var observations: [CompletedRoutine] = []
            for start in 0..<(records.count - sequenceLength) {
                let prior = Array(records[start..<(start + sequenceLength)].map(\.routineID))
                if prior == suffix { observations.append(records[start + sequenceLength]) }
            }
            guard observations.count >= configuration.minimumObservations else { continue }
            let totalWeight = observations.reduce(0.0) { $0 + recencyWeight(observedAt: $1.date, relativeTo: date) }
            let suffixNames = suffix.compactMap { names[$0] }.joined(separator: " → ")

            for (routineID, matches) in Dictionary(grouping: observations, by: \.routineID) {
                guard matches.count >= configuration.minimumObservations, let name = names[routineID] else { continue }
                let support = matches.reduce(0.0) { $0 + recencyWeight(observedAt: $1.date, relativeTo: date) }
                candidates.append(Candidate(
                    signature: "rotation:\(suffix.map(\.uuidString).joined(separator: ":")):\(routineID.uuidString)",
                    routineID: routineID,
                    type: .rotation,
                    subjectID: suffix.last,
                    count: matches.count,
                    totalCount: observations.count,
                    weightedSupport: support,
                    weightedTotal: totalWeight,
                    lastObservedAt: matches.map(\.date).max() ?? date,
                    explanation: "After \(suffixNames), you usually perform \(name) (\(matches.count) of \(observations.count) times)."
                ))
            }
        }
        return candidates
    }

    private func surfacedSuggestion(
        from candidate: Candidate,
        learnedPatterns: [LearnedPattern]
    ) -> RoutineSuggestion? {
        guard candidate.count >= configuration.minimumObservations,
              candidate.weightedTotal > 0 else { return nil }
        let persisted = learnedPatterns.first {
            $0.signature == candidate.signature ||
                ($0.type == candidate.type && $0.candidateID == candidate.routineID && $0.subjectID == candidate.subjectID)
        }
        let candidateIsSuppressed = learnedPatterns.contains {
            $0.isSuppressed && ($0.signature == candidate.signature || $0.candidateID == candidate.routineID)
        }
        guard !candidateIsSuppressed else { return nil }

        let frequency = candidate.weightedSupport / candidate.weightedTotal
        let evidence = 0.7 + 0.3 * min(1, Double(candidate.count) / Double(configuration.fullEvidenceObservationCount))
        let penalty = max(0, 1 - Double(persisted?.dismissedCount ?? 0) * configuration.dismissalConfidencePenalty)
        let confidence = min(1, max(0, frequency * evidence * penalty))
        guard confidence >= configuration.mediumConfidenceThreshold else { return nil }

        return RoutineSuggestion(
            signature: candidate.signature,
            routineID: candidate.routineID,
            type: candidate.type,
            confidence: confidence,
            observationCount: candidate.count,
            lastObservedAt: candidate.lastObservedAt,
            explanation: candidate.explanation
        )
    }

    private func recencyWeight(observedAt: Date, relativeTo date: Date) -> Double {
        let ageDays = max(0, date.timeIntervalSince(observedAt) / 86_400)
        return pow(0.5, ageDays / configuration.recencyHalfLifeDays)
    }

    private func priority(_ type: PatternType) -> Int {
        switch type {
        case .rotation: 3
        case .routineTransition: 2
        case .weekdayRoutine: 1
        default: 0
        }
    }
}
