import Foundation
import SwiftData

@Model
final class LearnedPattern {
    @Attribute(.unique) var id: UUID
    var signature: String
    var typeRaw: String
    var subjectID: UUID?
    var candidateID: UUID?
    var confidence: Double
    var supportingObservationCount: Int
    var lastObservedAt: Date
    var explanation: String
    var dismissedCount: Int
    var isSuppressed: Bool
    var createdAt: Date
    var updatedAt: Date

    var type: PatternType {
        get { PatternType(rawValue: typeRaw) ?? .weekdayRoutine }
        set { typeRaw = newValue.rawValue; updatedAt = .now }
    }

    init(
        id: UUID = UUID(),
        signature: String,
        type: PatternType,
        subjectID: UUID? = nil,
        candidateID: UUID? = nil,
        confidence: Double,
        supportingObservationCount: Int,
        lastObservedAt: Date,
        explanation: String,
        dismissedCount: Int = 0,
        isSuppressed: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.signature = signature
        typeRaw = type.rawValue
        self.subjectID = subjectID
        self.candidateID = candidateID
        self.confidence = min(max(confidence, 0), 1)
        self.supportingObservationCount = max(0, supportingObservationCount)
        self.lastObservedAt = lastObservedAt
        self.explanation = explanation
        self.dismissedCount = max(0, dismissedCount)
        self.isSuppressed = isSuppressed
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    func dismiss(at date: Date = .now, suppressionThreshold: Int = PatternConfiguration.default.suppressionDismissalCount) {
        dismissedCount += 1
        isSuppressed = dismissedCount >= suppressionThreshold
        updatedAt = date
    }
}
