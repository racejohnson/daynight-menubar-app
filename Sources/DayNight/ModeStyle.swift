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

    /// The fill of the row that is on, under white text. Day is the app icon's
    /// sun, deeper than system orange so the text reads. Night is the icon's
    /// night sky in light mode, and the lighter blue of its glow in dark mode,
    /// where the sky colour would vanish.
    var tint: Color {
        switch self {
        case .day: Color(light: (224, 94, 38), dark: (238, 116, 69))
        case .away: Color(light: (140, 78, 181), dark: (173, 106, 219))
        case .night: Color(light: (42, 50, 111), dark: (74, 86, 184))
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
}
