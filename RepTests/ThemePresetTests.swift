import SwiftUI
import Testing
@testable import Rep

@Suite("Manual app colors")
struct ManualAppColorTests {
    @Test("RGBA values serialize without losing channels")
    func rgbaRoundTrip() {
        let original = RepRGBAColor(red: 12 / 255, green: 128 / 255, blue: 0.9, alpha: 0.42)
        let restored = RepRGBAColor(serialized: original.serialized)

        #expect(restored == original)
        #expect(restored?.redByte == 12)
        #expect(restored?.greenByte == 128)
        #expect(restored?.alpha == 0.42)
        #expect(RepRGBAColor(red: 1, green: 0.5, blue: 0, alpha: 0.5).hexaDescription == "#FF800080")
        #expect(RepRGBAColor(serialized: "0.2,invalid,0.4,1") == nil)
    }

    @Test("Manual channel input is clamped to valid RGBA ranges")
    func channelsAreClamped() {
        var color = RepRGBAColor(red: -1, green: 2, blue: 0.5, alpha: 4)
        color.redByte = 999
        color.greenByte = -20

        #expect(color.red == 1)
        #expect(color.green == 0)
        #expect(color.blue == 0.5)
        #expect(color.alpha == 1)
    }

    @Test("HSV sliders round-trip through stored RGBA colors")
    func hsvRoundTrip() {
        let hsv = RepHSVColor(hue: 0.73, saturation: 0.64, value: 0.82, alpha: 0.55)
        let restored = RepHSVColor(rgba: hsv.rgba)

        #expect(abs(restored.hue - hsv.hue) < 0.000_001)
        #expect(abs(restored.saturation - hsv.saturation) < 0.000_001)
        #expect(abs(restored.value - hsv.value) < 0.000_001)
        #expect(restored.alpha == hsv.alpha)
    }

    @Test("Light and dark color groups persist independently")
    func persistenceRoundTrip() {
        let userSettings = UserSettings()
        var colors = RepThemeSettings()
        var light = colors.palette(for: .light)
        var dark = colors.palette(for: .dark)
        light.accent = RepRGBAColor(red: 1, green: 0.2, blue: 0.1, alpha: 0.8)
        dark.surface = RepRGBAColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.7)
        dark.backdropShadow = RepRGBAColor(red: 0.4, green: 0.1, blue: 0.2, alpha: 0.45)
        dark.secondaryText = RepRGBAColor(red: 0.7, green: 0.65, blue: 0.8, alpha: 0.75)
        colors.setPalette(light, for: .light)
        colors.setPalette(dark, for: .dark)

        colors.apply(to: userSettings)
        let restored = RepThemeSettings(settings: userSettings)

        #expect(restored.lightPalette.accent == light.accent)
        #expect(restored.darkPalette.surface == dark.surface)
        #expect(restored.darkPalette.backdropShadow == dark.backdropShadow)
        #expect(restored.darkPalette.secondaryText == dark.secondaryText)
        #expect(restored.darkPalette.accent == RepThemeDefaults.dark.accent)
    }

    @Test("Existing preset selection migrates to editable colors")
    func presetMigration() {
        let userSettings = UserSettings()
        userSettings.themeResetGeneration = 2
        userSettings.lightThemePresetRaw = "light-meadow"
        userSettings.darkThemePresetRaw = "dark-oled"
        userSettings.lightAccentRGBA = nil
        userSettings.darkAccentRGBA = nil

        UserSettingsThemeMigration.backfill(userSettings)

        let colors = RepThemeSettings(settings: userSettings)
        #expect(colors.lightPalette.accent.green > colors.lightPalette.accent.red)
        #expect(colors.darkPalette.background == RepRGBAColor(red: 0, green: 0, blue: 0))
        #expect(userSettings.themeResetGeneration == 3)
    }
}
