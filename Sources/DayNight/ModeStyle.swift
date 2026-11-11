import DayNightCore
import SwiftUI

extension Mode {
    var title: String {
        switch self {
        case .day: "Day"
        case .dim: "Dim"
        case .night: "Night"
        }
    }

    var symbolName: String {
        switch self {
        case .day: "sun.max.fill"
        case .dim: "sun.horizon.fill"
        case .night: "moon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .day: .orange
        case .dim: .teal
        case .night: .indigo
        }
    }
}

extension BrightnessState {
    var title: String { mode?.title ?? "Custom" }

    /// Custom is drawn as a half-filled circle: the same weight as the sun and
    /// moon, and the glyph macOS already uses for an appearance that is
    /// neither light nor dark.
    var symbolName: String { mode?.symbolName ?? "circle.lefthalf.filled" }
}
