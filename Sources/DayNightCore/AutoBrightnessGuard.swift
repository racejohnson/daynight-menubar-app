import Foundation

public enum AutoBrightnessResult: Equatable, Sendable {
    case nothingToDo
    case succeeded
    case keyboardUnavailable
    case failed

    /// Whether the setting is still waiting to be put back.
    public var isStillPending: Bool { self == .keyboardUnavailable || self == .failed }
}

/// Keyboard auto-brightness would fight a preset, so it is switched off before
/// DayNight first touches the keyboard and switched back on at quit. A marker in
/// UserDefaults survives a crash, so the next launch can still put it back.
struct AutoBrightnessGuard {
    enum Key {
        static let pending = "keyboard.autoBrightness.recoveryPending"
        static let priorEnabled = "keyboard.autoBrightness.priorEnabled"
    }

    private let keyboard: any KeyboardControlling
    private let defaults: UserDefaults
    private var preparedThisSession = false

    init(keyboard: any KeyboardControlling, defaults: UserDefaults) {
        self.keyboard = keyboard
        self.defaults = defaults
    }

    var isPending: Bool { defaults.bool(forKey: Key.pending) }

    /// Restores a setting left behind by a session that did not quit cleanly.
    mutating func recoverLeftover() -> AutoBrightnessResult {
        guard isPending, !preparedThisSession else { return .nothingToDo }
        return restore()
    }

    /// Snapshots and disables auto-brightness once per session.
    mutating func prepare() -> AutoBrightnessResult {
        guard !preparedThisSession else { return .nothingToDo }
        guard keyboard.isAvailable, let current = keyboard.isAutoBrightnessEnabled() else {
            return .keyboardUnavailable
        }
        // A leftover marker still holds the user's real setting; the current
        // value is the one an earlier session forced off.
        if !isPending {
            defaults.set(current, forKey: Key.priorEnabled)
            defaults.set(true, forKey: Key.pending)
        }
        guard keyboard.setAutoBrightnessEnabled(false) else { return .failed }
        preparedThisSession = true
        return .succeeded
    }

    /// Puts the snapshotted setting back and clears the marker.
    mutating func restore() -> AutoBrightnessResult {
        guard isPending else { return .nothingToDo }
        guard keyboard.isAvailable else { return .keyboardUnavailable }
        guard keyboard.setAutoBrightnessEnabled(defaults.bool(forKey: Key.priorEnabled)) else {
            return .failed
        }
        defaults.removeObject(forKey: Key.pending)
        defaults.removeObject(forKey: Key.priorEnabled)
        preparedThisSession = false
        return .succeeded
    }
}
