import AppKit
import DayNightCore
import SwiftUI

extension Mode {
    var title: String {
        switch self {
        case .day: "Day"
        case .away: "Away"
        case .night: "Night"
        }
    }

    var symbolName: String {
        switch self {
        case .day: "sun.max.fill"
        case .away: "figure.walk"
        case .night: "moon.fill"
        }
    }

    /// Night's blue is the app icon's: its night sky in light mode, and the
    /// lighter blue of its glow in dark mode, where the sky colour would vanish.
    var tint: Color {
        switch self {
        case .day: .orange
        case .away: Color(light: (140, 78, 181), dark: (173, 106, 219))
        case .night: Color(light: (42, 50, 111), dark: (74, 86, 184))
        }
    }

    /// How strongly the active card is filled with the tint. The darker tints
    /// need more, or the card reads as grey.
    func fillOpacity(_ scheme: ColorScheme) -> Double {
        let isDark = scheme == .dark
        return switch self {
        case .day: isDark ? 0.15 : 0.11
        case .away: isDark ? 0.16 : 0.12
        case .night: isDark ? 0.20 : 0.16
        }
    }
}

private extension Color {
    /// An opaque colour with its own value for each appearance, as 0–255 sRGB.
    init(light: (Double, Double, Double), dark: (Double, Double, Double)) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1)
        })
    }
}

extension BrightnessState {
    var title: String { mode?.title ?? "Custom" }

    /// Custom is drawn as a half-filled circle: the same weight as the sun and
    /// moon, and the glyph macOS already uses for an appearance that is
    /// neither light nor dark.
    var symbolName: String { mode?.symbolName ?? "circle.lefthalf.filled" }
}
