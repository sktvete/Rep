import Foundation
import SwiftData

@Model
final class UserSettings {
    @Attribute(.unique) var id: UUID
    var preferredWeightUnitRaw: String
    var defaultRestSeconds: Int
    var hapticsEnabled: Bool
    var patternSuggestionsEnabled: Bool
    var hasGeneratedSampleData: Bool
    var createdAt: Date
    var updatedAt: Date

    var preferredWeightUnit: WeightUnit {
        get { WeightUnit(rawValue: preferredWeightUnitRaw) ?? .kilograms }
        set { preferredWeightUnitRaw = newValue.rawValue; updatedAt = .now }
    }

    init(
        id: UUID = UUID(),
        preferredWeightUnit: WeightUnit = .kilograms,
        defaultRestSeconds: Int = 90,
        hapticsEnabled: Bool = true,
        patternSuggestionsEnabled: Bool = true,
        hasGeneratedSampleData: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        preferredWeightUnitRaw = preferredWeightUnit.rawValue
        self.defaultRestSeconds = max(0, defaultRestSeconds)
        self.hapticsEnabled = hapticsEnabled
        self.patternSuggestionsEnabled = patternSuggestionsEnabled
        self.hasGeneratedSampleData = hasGeneratedSampleData
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}
