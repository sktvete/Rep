import Foundation

enum UnitConversion {
    static let poundsPerKilogram = 2.204_622_621_8

    static func kilogramsToPounds(_ kilograms: Double) -> Double {
        kilograms * poundsPerKilogram
    }

    static func poundsToKilograms(_ pounds: Double) -> Double {
        pounds / poundsPerKilogram
    }

    static func weight(_ value: Double, from source: WeightUnit, to destination: WeightUnit) -> Double {
        guard source != destination else { return value }
        switch (source, destination) {
        case (.kilograms, .pounds): return kilogramsToPounds(value)
        case (.pounds, .kilograms): return poundsToKilograms(value)
        default: return value
        }
    }

    static func displayWeight(
        kilograms: Double,
        unit: WeightUnit,
        maximumFractionDigits: Int = 1,
        locale: Locale = .current
    ) -> String {
        let value = unit == .kilograms ? kilograms : kilogramsToPounds(kilograms)
        let format = FloatingPointFormatStyle<Double>.number
            .locale(locale)
            .precision(.fractionLength(0...max(0, maximumFractionDigits)))
        return "\(value.formatted(format)) \(unit.symbol)"
    }
}
