import Foundation

public final class PresetStore {
    private enum Key {
        static let dayScreen = "preset.day.screen"
        static let dayKeyboard = "preset.day.keyboard"
        static let nightScreen = "preset.night.screen"
        static let nightKeyboard = "preset.night.keyboard"
        static let lastAppliedMode = "state.lastAppliedMode"
        static let launchAtLoginDesired = "login.desired"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var day: BrightnessPreset {
        get {
            BrightnessPreset(
                screen: value(forKey: Key.dayScreen, fallback: 1),
                keyboard: value(forKey: Key.dayKeyboard, fallback: 1)
            )
        }
        set {
            defaults.set(BrightnessPreset.clamp(newValue.screen),
                         forKey: Key.dayScreen)
            defaults.set(BrightnessPreset.clamp(newValue.keyboard),
                         forKey: Key.dayKeyboard)
        }
    }

    public var night: BrightnessPreset {
        get {
            BrightnessPreset(
                screen: value(forKey: Key.nightScreen, fallback: 0.2),
                keyboard: value(forKey: Key.nightKeyboard, fallback: 0.1)
            )
        }
        set {
            defaults.set(BrightnessPreset.clamp(newValue.screen),
                         forKey: Key.nightScreen)
            defaults.set(BrightnessPreset.clamp(newValue.keyboard),
                         forKey: Key.nightKeyboard)
        }
    }

    public var lastAppliedMode: DayNightMode? {
        get {
            guard let raw = defaults.string(forKey: Key.lastAppliedMode) else {
                return nil
            }
            let mode = DayNightMode(rawValue: raw)
            return mode == .custom ? nil : mode
        }
        set {
            if let newValue, newValue != .custom {
                defaults.set(newValue.rawValue, forKey: Key.lastAppliedMode)
            } else {
                defaults.removeObject(forKey: Key.lastAppliedMode)
            }
        }
    }

    public var launchAtLoginDesired: Bool {
        get {
            guard defaults.object(forKey: Key.launchAtLoginDesired) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.launchAtLoginDesired)
        }
        set {
            defaults.set(newValue, forKey: Key.launchAtLoginDesired)
        }
    }

    private func value(forKey key: String, fallback: Double) -> Double {
        guard let number = defaults.object(forKey: key) as? NSNumber else {
            return fallback
        }
        return BrightnessPreset.clamp(number.doubleValue)
    }
}
