import Foundation
import SwiftData

@Model
final class BodyweightEntry {
    @Attribute(.unique) var id: UUID
    var measuredAt: Date
    var weightKilograms: Double
    var notes: String
    var sourceRaw: String
    var createdAt: Date
    var updatedAt: Date

    var source: BodyweightSource {
        get { BodyweightSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue; updatedAt = .now }
    }

    init(
        id: UUID = UUID(),
        measuredAt: Date = .now,
        weightKilograms: Double,
        notes: String = "",
        source: BodyweightSource = .manual,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.measuredAt = measuredAt
        self.weightKilograms = weightKilograms
        self.notes = notes
        sourceRaw = source.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}
