import Foundation

/// Persistent settings. The keys are shared with DayNight 1.x, so existing
/// presets and preferences carry over unchanged.
public struct SettingsStore {
    enum Key {
        static let dayScreen = "preset.day.screen"
        static let dayKeyboard = "preset.day.keyboard"
        static let dimScreen = "preset.dim.screen"
        static let dimKeyboard = "preset.dim.keyboard"
        static let nightScreen = "preset.night.screen"
        static let nightKeyboard = "preset.night.keyboard"
        static let lastApplied = "state.lastAppliedMode"
        static let launchAtLogin = "login.desired"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func preset(for mode: Mode) -> BrightnessPreset {
        let fallback = Presets()[mode]
        let keys = Self.keys(for: mode)
        return BrightnessPreset(
            screen: double(keys.screen) ?? fallback.screen,
            keyboard: double(keys.keyboard) ?? fallback.keyboard
        )
    }

    public var presets: Presets {
        Presets(day: preset(for: .day), dim: preset(for: .dim), night: preset(for: .night))
    }

    public func setPreset(_ preset: BrightnessPreset, for mode: Mode) {
        let keys = Self.keys(for: mode)
        defaults.set(preset.screen, forKey: keys.screen)
        defaults.set(preset.keyboard, forKey: keys.keyboard)
    }

    public var lastApplied: Mode? {
        get { defaults.string(forKey: Key.lastApplied).flatMap(Mode.init(rawValue:)) }
        nonmutating set { defaults.set(newValue?.rawValue, forKey: Key.lastApplied) }
    }

    /// Launch at login is wanted unless it was explicitly turned off.
    public var launchAtLogin: Bool {
        get { defaults.object(forKey: Key.launchAtLogin) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    private static func keys(for mode: Mode) -> (screen: String, keyboard: String) {
        switch mode {
        case .day: (Key.dayScreen, Key.dayKeyboard)
        case .dim: (Key.dimScreen, Key.dimKeyboard)
        case .night: (Key.nightScreen, Key.nightKeyboard)
        }
    }

    private func double(_ key: String) -> Double? {
        (defaults.object(forKey: key) as? NSNumber).map { BrightnessPreset.clamp($0.doubleValue) }
    }
}
