import DayNightCore
import SwiftUI

extension Mode {
    var title: String { self == .day ? "Day" : "Night" }
    var symbolName: String { self == .day ? "sun.max.fill" : "moon.fill" }
    var tint: Color { self == .day ? .orange : .indigo }
}

extension BrightnessState {
    var title: String { mode?.title ?? "Custom" }

    /// Custom is drawn as a half-filled circle: literally "in between" Day and
    /// Night, the same weight as the sun and moon, and the glyph macOS already
    /// uses for an appearance that is neither light nor dark.
    var symbolName: String { mode?.symbolName ?? "circle.lefthalf.filled" }
}
