import Foundation
import Testing
@testable import Rep

@Suite("Weight unit conversion")
struct UnitConversionTests {
    @Test("Kilograms convert to pounds")
    func kilogramsToPounds() {
        #expect(abs(UnitConversion.kilogramsToPounds(100) - 220.462_262) < 0.000_1)
    }

    @Test("Pounds convert to kilograms")
    func poundsToKilograms() {
        #expect(abs(UnitConversion.poundsToKilograms(220.462_262) - 100) < 0.000_1)
    }

    @Test("Round-trip conversion preserves canonical weight")
    func roundTrip() {
        let original = 83.75
        let roundTripped = UnitConversion.poundsToKilograms(UnitConversion.kilogramsToPounds(original))
        #expect(abs(roundTripped - original) < 0.000_000_1)
    }

    @Test("Display formatting includes selected unit")
    func displayFormatting() {
        let locale = Locale(identifier: "en_US_POSIX")
        #expect(UnitConversion.displayWeight(kilograms: 100, unit: .kilograms, locale: locale) == "100 kg")
        #expect(UnitConversion.displayWeight(kilograms: 100, unit: .pounds, locale: locale) == "220.5 lb")
    }
}
