import SwiftUI
import UIKit

struct RepRGBAColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    init?(serialized: String) {
        let fields = serialized.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count == 4,
              let red = Double(fields[0]),
              let green = Double(fields[1]),
              let blue = Double(fields[2]),
              let alpha = Double(fields[3]) else { return nil }
        self.init(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    init(color: Color) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let uiColor = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))

        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            self.init(
                red: Double(red),
                green: Double(green),
                blue: Double(blue),
                alpha: Double(alpha)
            )
        } else {
            self.init(red: 0, green: 0, blue: 0)
        }
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var serialized: String {
        [red, green, blue, alpha].map { String($0) }.joined(separator: ",")
    }

    var rgbaDescription: String {
        "rgba(\(redByte), \(greenByte), \(blueByte), \(alpha.formatted(.number.precision(.fractionLength(2)))))"
    }

    var hexaDescription: String {
        String(
            format: "#%02X%02X%02X%02X",
            redByte,
            greenByte,
            blueByte,
            Int((alpha * 255).rounded())
        )
    }

    var redByte: Int {
        get { Int((red * 255).rounded()) }
        set { red = Self.clamp(Double(newValue) / 255) }
    }

    var greenByte: Int {
        get { Int((green * 255).rounded()) }
        set { green = Self.clamp(Double(newValue) / 255) }
    }

    var blueByte: Int {
        get { Int((blue * 255).rounded()) }
        set { blue = Self.clamp(Double(newValue) / 255) }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct RepHSVColor: Equatable, Sendable {
    var hue: Double
    var saturation: Double
    var value: Double
    var alpha: Double

    init(hue: Double, saturation: Double, value: Double, alpha: Double = 1) {
        self.hue = min(max(hue, 0), 1)
        self.saturation = min(max(saturation, 0), 1)
        self.value = min(max(value, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    init(rgba: RepRGBAColor) {
        let maximum = max(rgba.red, rgba.green, rgba.blue)
        let minimum = min(rgba.red, rgba.green, rgba.blue)
        let delta = maximum - minimum

        let hue: Double
        if delta == 0 {
            hue = 0
        } else if maximum == rgba.red {
            hue = ((rgba.green - rgba.blue) / delta).truncatingRemainder(dividingBy: 6) / 6
        } else if maximum == rgba.green {
            hue = (((rgba.blue - rgba.red) / delta) + 2) / 6
        } else {
            hue = (((rgba.red - rgba.green) / delta) + 4) / 6
        }

        self.init(
            hue: hue < 0 ? hue + 1 : hue,
            saturation: maximum == 0 ? 0 : delta / maximum,
            value: maximum,
            alpha: rgba.alpha
        )
    }

    var rgba: RepRGBAColor {
        let chroma = value * saturation
        let hueSector = hue * 6
        let intermediate = chroma * (1 - abs(hueSector.truncatingRemainder(dividingBy: 2) - 1))
        let offset = value - chroma

        let components: (Double, Double, Double) = switch Int(floor(hueSector)) % 6 {
        case 0: (chroma, intermediate, 0)
        case 1: (intermediate, chroma, 0)
        case 2: (0, chroma, intermediate)
        case 3: (0, intermediate, chroma)
        case 4: (intermediate, 0, chroma)
        default: (chroma, 0, intermediate)
        }

        return RepRGBAColor(
            red: components.0 + offset,
            green: components.1 + offset,
            blue: components.2 + offset,
            alpha: alpha
        )
    }
}

struct RepThemePalette: Equatable, Sendable {
    var accent: RepRGBAColor
    var background: RepRGBAColor
    var surface: RepRGBAColor
    var backdropShadow: RepRGBAColor
    var controls: RepRGBAColor
    var secondaryText: RepRGBAColor
}

enum RepThemeDefaults {
    static let light = RepThemePalette(
        accent: RepRGBAColor(red: 0.144, green: 0.446, blue: 0.9),
        background: RepRGBAColor(red: 239 / 255, green: 239 / 255, blue: 243 / 255),
        surface: RepRGBAColor(red: 1, green: 1, blue: 1),
        backdropShadow: RepRGBAColor(red: 0, green: 0, blue: 0, alpha: 0.1),
        controls: RepRGBAColor(red: 229 / 255, green: 229 / 255, blue: 234 / 255),
        secondaryText: RepHSVColor(
            hue: 2 / 3,
            saturation: 7 / 67,
            value: 0.16,
            alpha: 1
        ).rgba
    )

    static let dark = RepThemePalette(
        accent: RepRGBAColor(red: 0.238, green: 0.434, blue: 0.85),
        background: RepRGBAColor(red: 18 / 255, green: 18 / 255, blue: 20 / 255),
        surface: RepRGBAColor(red: 34 / 255, green: 34 / 255, blue: 38 / 255),
        backdropShadow: RepRGBAColor(red: 0, green: 0, blue: 0, alpha: 0.35),
        controls: RepRGBAColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255),
        secondaryText: RepRGBAColor(red: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: 0.6)
    )

    static func palette(for colorScheme: ColorScheme) -> RepThemePalette {
        colorScheme == .dark ? dark : light
    }

    // Converts the old preset selection once so existing development installs
    // keep their current accent when moving to the manual color editor.
    static func migratedPalette(presetID: String?, colorScheme: ColorScheme) -> RepThemePalette {
        var palette = palette(for: colorScheme)
        let hsv: (Double, Double, Double)? = switch presetID {
        case "light-alpine": (0.60, 0.84, 0.90)
        case "light-meadow": (0.42, 0.74, 0.64)
        case "light-sunrise": (0.055, 0.86, 0.90)
        case "light-wildflower": (0.78, 0.62, 0.80)
        case "light-parchment": (0.105, 0.62, 0.70)
        case "dark-midnight": (0.61, 0.72, 0.85)
        case "dark-oled": (0.51, 0.70, 0.96)
        case "dark-evergreen": (0.42, 0.70, 0.88)
        case "dark-ember": (0.055, 0.82, 1.0)
        case "dark-ultraviolet": (0.78, 0.66, 1.0)
        default: nil
        }
        if let hsv {
            palette.accent = rgb(hue: hsv.0, saturation: hsv.1, brightness: hsv.2)
        }
        if presetID == "dark-oled" {
            palette.background = RepRGBAColor(red: 0, green: 0, blue: 0)
            palette.surface = RepRGBAColor(red: 24 / 255, green: 24 / 255, blue: 26 / 255)
            palette.controls = RepRGBAColor(red: 36 / 255, green: 36 / 255, blue: 38 / 255)
        }
        return palette
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> RepRGBAColor {
        let color = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        return RepRGBAColor(color: Color(uiColor: color))
    }
}

struct RepThemeSettings: Equatable, Sendable {
    var lightPalette = RepThemeDefaults.light
    var darkPalette = RepThemeDefaults.dark

    func palette(for colorScheme: ColorScheme) -> RepThemePalette {
        colorScheme == .dark ? darkPalette : lightPalette
    }

    func resolved(for colorScheme: ColorScheme) -> RepTheme {
        RepTheme(palette: palette(for: colorScheme))
    }

    mutating func setPalette(_ palette: RepThemePalette, for colorScheme: ColorScheme) {
        if colorScheme == .dark {
            darkPalette = palette
        } else {
            lightPalette = palette
        }
    }

    mutating func reset(_ colorScheme: ColorScheme) {
        setPalette(RepThemeDefaults.palette(for: colorScheme), for: colorScheme)
    }
}

struct RepTheme: Equatable, Sendable {
    var palette: RepThemePalette

    var accent: Color { palette.accent.color }
    var canvasColor: Color { palette.background.color }
    var surfaceColor: Color { palette.surface.color }
    var backdropShadow: Color { palette.backdropShadow.color }
    var neutralControlTint: Color { palette.controls.color }
    var secondaryText: Color { palette.secondaryText.color }

    var accentContent: Color {
        // WCAG relative luminance gives a dependable black/white label choice.
        let components = [palette.accent.red, palette.accent.green, palette.accent.blue].map {
            $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
        }
        let luminance = (0.2126 * components[0]) + (0.7152 * components[1]) + (0.0722 * components[2])
        return luminance > 0.36 ? .black : .white
    }
}

private struct RepThemeSettingsKey: EnvironmentKey {
    static let defaultValue = RepThemeSettings()
}

private struct RepThemeKey: EnvironmentKey {
    static let defaultValue = RepTheme(palette: RepThemeDefaults.light)
}

extension EnvironmentValues {
    var repThemeSettings: RepThemeSettings {
        get { self[RepThemeSettingsKey.self] }
        set { self[RepThemeSettingsKey.self] = newValue }
    }

    var repTheme: RepTheme {
        get { self[RepThemeKey.self] }
        set { self[RepThemeKey.self] = newValue }
    }
}

extension RepThemeSettings {
    init(settings: UserSettings) {
        lightPalette = settings.resolvedColorPalette(for: .light)
        darkPalette = settings.resolvedColorPalette(for: .dark)
    }

    func apply(to settings: UserSettings) {
        settings.setColorPalette(lightPalette, for: .light)
        settings.setColorPalette(darkPalette, for: .dark)
    }
}
