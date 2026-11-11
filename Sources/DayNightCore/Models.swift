/// One of the three brightness presets, brightest to darkest.
public enum Mode: String, CaseIterable, Sendable {
    case day
    case away
    case night
}

/// What the hardware currently looks like: one of the presets, or none of them.
public enum BrightnessState: Equatable, Sendable {
    case day
    case away
    case night
    case custom

    public init(_ mode: Mode) {
        switch mode {
        case .day: self = .day
        case .away: self = .away
        case .night: self = .night
        }
    }

    public var mode: Mode? {
        switch self {
        case .day: .day
        case .away: .away
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
    public static let defaultAway = BrightnessPreset(screen: 0.5, keyboard: 0.5)
    public static let defaultNight = BrightnessPreset(screen: 0.2, keyboard: 0.1)

    public static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}

/// The preset for each mode.
public struct Presets: Equatable, Sendable {
    public var day: BrightnessPreset
    public var away: BrightnessPreset
    public var night: BrightnessPreset

    public init(
        day: BrightnessPreset = .defaultDay,
        away: BrightnessPreset = .defaultAway,
        night: BrightnessPreset = .defaultNight
    ) {
        self.day = day
        self.away = away
        self.night = night
    }

    public subscript(mode: Mode) -> BrightnessPreset {
        get {
            switch mode {
            case .day: day
            case .away: away
            case .night: night
            }
        }
        set {
            switch mode {
            case .day: day = newValue
            case .away: away = newValue
            case .night: night = newValue
            }
        }
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
