/// One of the two brightness presets.
public enum Mode: String, Sendable {
    case day
    case night

    public var opposite: Mode { self == .day ? .night : .day }
}

/// What the hardware currently looks like: one of the presets, or neither.
public enum BrightnessState: Equatable, Sendable {
    case day
    case night
    case custom

    public init(_ mode: Mode) {
        self = mode == .day ? .day : .night
    }

    public var mode: Mode? {
        switch self {
        case .day: .day
        case .night: .night
        case .custom: nil
        }
    }
}

/// Screen and keyboard-backlight levels, each clamped to 0...1.
public struct BrightnessPreset: Equatable, Sendable {
    public var screen: Double { didSet { screen = Self.clamp(screen) } }
    public var keyboard: Double { didSet { keyboard = Self.clamp(keyboard) } }

    public init(screen: Double, keyboard: Double) {
        self.screen = Self.clamp(screen)
        self.keyboard = Self.clamp(keyboard)
    }

    public static let defaultDay = BrightnessPreset(screen: 1, keyboard: 1)
    public static let defaultNight = BrightnessPreset(screen: 0.2, keyboard: 0.1)

    public static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}

/// Brightness of every controllable display, plus the keyboard backlight when present.
public struct HardwareSnapshot: Equatable, Sendable {
    public var displays: [UInt32: Double]
    public var keyboard: Double?

    public init(displays: [UInt32: Double] = [:], keyboard: Double? = nil) {
        self.displays = displays.mapValues(BrightnessPreset.clamp)
        self.keyboard = keyboard.map(BrightnessPreset.clamp)
    }

    public var channelCount: Int {
        displays.count + (keyboard == nil ? 0 : 1)
    }
}
