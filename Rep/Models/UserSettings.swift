import Foundation
import SwiftData
import SwiftUI

@Model
final class UserSettings {
    @Attribute(.unique) var id: UUID
    var preferredWeightUnitRaw: String
    var appearancePreferenceRaw: String?
    var lightThemePresetRaw: String?
    var darkThemePresetRaw: String?
    var themeHue: Double?
    var backgroundGlow: Double?
    var surfaceBackdrop: Double?
    var lightBackgroundDepth: Double?
    var lightBackgroundGlow: Double?
    var lightSurfaceBackdrop: Double?
    var darkBackgroundDepth: Double?
    var darkBackgroundGlow: Double?
    var darkSurfaceBackdrop: Double?
    var lightAccentRGBA: String?
    var lightBackgroundRGBA: String?
    var lightSurfaceRGBA: String?
    var lightBackdropShadowRGBA: String?
    var lightControlsRGBA: String?
    var lightSecondaryTextRGBA: String?
    var darkAccentRGBA: String?
    var darkBackgroundRGBA: String?
    var darkSurfaceRGBA: String?
    var darkBackdropShadowRGBA: String?
    var darkControlsRGBA: String?
    var darkSecondaryTextRGBA: String?
    var themeResetGeneration: Int?
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

    var appearancePreference: AppAppearance {
        get { AppAppearance(rawValue: appearancePreferenceRaw ?? "") ?? .system }
        set { appearancePreferenceRaw = newValue.rawValue; updatedAt = .now }
    }

    init(
        id: UUID = UUID(),
        preferredWeightUnit: WeightUnit = .kilograms,
        appearancePreference: AppAppearance = .system,
        themeHue: Double = 0.60,
        defaultRestSeconds: Int = 90,
        hapticsEnabled: Bool = true,
        patternSuggestionsEnabled: Bool = true,
        hasGeneratedSampleData: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        preferredWeightUnitRaw = preferredWeightUnit.rawValue
        appearancePreferenceRaw = appearancePreference.rawValue
        lightThemePresetRaw = nil
        darkThemePresetRaw = nil
        self.themeHue = themeHue
        let lightPalette = RepThemeDefaults.light
        let darkPalette = RepThemeDefaults.dark
        lightAccentRGBA = lightPalette.accent.serialized
        lightBackgroundRGBA = lightPalette.background.serialized
        lightSurfaceRGBA = lightPalette.surface.serialized
        lightBackdropShadowRGBA = lightPalette.backdropShadow.serialized
        lightControlsRGBA = lightPalette.controls.serialized
        lightSecondaryTextRGBA = lightPalette.secondaryText.serialized
        darkAccentRGBA = darkPalette.accent.serialized
        darkBackgroundRGBA = darkPalette.background.serialized
        darkSurfaceRGBA = darkPalette.surface.serialized
        darkBackdropShadowRGBA = darkPalette.backdropShadow.serialized
        darkControlsRGBA = darkPalette.controls.serialized
        darkSecondaryTextRGBA = darkPalette.secondaryText.serialized
        self.defaultRestSeconds = max(0, defaultRestSeconds)
        self.hapticsEnabled = hapticsEnabled
        self.patternSuggestionsEnabled = patternSuggestionsEnabled
        self.hasGeneratedSampleData = hasGeneratedSampleData
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

enum UserSettingsThemeMigration {
    private static let currentThemeResetGeneration = 3

    static func resetColorsToDefaults(_ settings: UserSettings) {
        settings.setColorPalette(RepThemeDefaults.light, for: .light)
        settings.setColorPalette(RepThemeDefaults.dark, for: .dark)
    }

    static func backfill(_ settings: UserSettings) {
        if (settings.themeResetGeneration ?? 0) < currentThemeResetGeneration {
            let light = RepThemeDefaults.migratedPalette(
                presetID: settings.lightThemePresetRaw,
                colorScheme: .light
            )
            let dark = RepThemeDefaults.migratedPalette(
                presetID: settings.darkThemePresetRaw,
                colorScheme: .dark
            )
            settings.setColorPalette(light, for: .light)
            settings.setColorPalette(dark, for: .dark)
            settings.themeResetGeneration = currentThemeResetGeneration
        }
    }
}

extension UserSettings {
    func resolvedColorPalette(for colorScheme: ColorScheme) -> RepThemePalette {
        let fallback = RepThemeDefaults.palette(for: colorScheme)
        let values: (String?, String?, String?, String?, String?, String?) = colorScheme == .dark
            ? (darkAccentRGBA, darkBackgroundRGBA, darkSurfaceRGBA, darkBackdropShadowRGBA, darkControlsRGBA, darkSecondaryTextRGBA)
            : (lightAccentRGBA, lightBackgroundRGBA, lightSurfaceRGBA, lightBackdropShadowRGBA, lightControlsRGBA, lightSecondaryTextRGBA)

        return RepThemePalette(
            accent: values.0.flatMap(RepRGBAColor.init(serialized:)) ?? fallback.accent,
            background: values.1.flatMap(RepRGBAColor.init(serialized:)) ?? fallback.background,
            surface: values.2.flatMap(RepRGBAColor.init(serialized:)) ?? fallback.surface,
            backdropShadow: values.3.flatMap(RepRGBAColor.init(serialized:)) ?? fallback.backdropShadow,
            controls: values.4.flatMap(RepRGBAColor.init(serialized:)) ?? fallback.controls,
            secondaryText: values.5.flatMap(RepRGBAColor.init(serialized:)) ?? fallback.secondaryText
        )
    }

    func setColorPalette(_ palette: RepThemePalette, for colorScheme: ColorScheme) {
        if colorScheme == .dark {
            darkAccentRGBA = palette.accent.serialized
            darkBackgroundRGBA = palette.background.serialized
            darkSurfaceRGBA = palette.surface.serialized
            darkBackdropShadowRGBA = palette.backdropShadow.serialized
            darkControlsRGBA = palette.controls.serialized
            darkSecondaryTextRGBA = palette.secondaryText.serialized
        } else {
            lightAccentRGBA = palette.accent.serialized
            lightBackgroundRGBA = palette.background.serialized
            lightSurfaceRGBA = palette.surface.serialized
            lightBackdropShadowRGBA = palette.backdropShadow.serialized
            lightControlsRGBA = palette.controls.serialized
            lightSecondaryTextRGBA = palette.secondaryText.serialized
        }
        updatedAt = .now
    }
}
