import Foundation

public enum AutoBrightnessRecoveryResult: Equatable {
    case nothingToDo
    case succeeded
    case keyboardUnavailable
    case failed
}

public final class KeyboardAutoBrightnessRecovery {
    private enum Key {
        static let pending = "keyboard.autoBrightness.recoveryPending"
        static let priorEnabled = "keyboard.autoBrightness.priorEnabled"
    }

    private let keyboardController: KeyboardControlling
    private let defaults: UserDefaults
    private var preparedThisSession = false

    public init(
        keyboardController: KeyboardControlling,
        defaults: UserDefaults = .standard
    ) {
        self.keyboardController = keyboardController
        self.defaults = defaults
    }

    public var hasRecoveryMarker: Bool {
        defaults.bool(forKey: Key.pending)
    }

    @discardableResult
    public func recoverIfNeeded() -> AutoBrightnessRecoveryResult {
        guard hasRecoveryMarker else { return .nothingToDo }
        guard keyboardController.isAvailable else {
            return .keyboardUnavailable
        }

        let priorState = defaults.bool(forKey: Key.priorEnabled)
        guard keyboardController.setAutoBrightnessEnabled(priorState) else {
            return .failed
        }
        clearMarker()
        preparedThisSession = false
        return .succeeded
    }

    @discardableResult
    public func prepareForControl() -> AutoBrightnessRecoveryResult {
        if preparedThisSession { return .nothingToDo }
        guard keyboardController.isAvailable,
              let current = keyboardController.autoBrightnessEnabled()
        else {
            return .keyboardUnavailable
        }

        defaults.set(current, forKey: Key.priorEnabled)
        defaults.set(true, forKey: Key.pending)
        defaults.synchronize()

        guard keyboardController.setAutoBrightnessEnabled(false) else {
            return .failed
        }
        preparedThisSession = true
        return .succeeded
    }

    @discardableResult
    public func restoreOnQuit() -> AutoBrightnessRecoveryResult {
        guard hasRecoveryMarker else { return .nothingToDo }
        guard keyboardController.isAvailable else {
            return .keyboardUnavailable
        }

        let priorState = defaults.bool(forKey: Key.priorEnabled)
        guard keyboardController.setAutoBrightnessEnabled(priorState) else {
            return .failed
        }
        clearMarker()
        preparedThisSession = false
        return .succeeded
    }

    private func clearMarker() {
        defaults.removeObject(forKey: Key.pending)
        defaults.removeObject(forKey: Key.priorEnabled)
        defaults.synchronize()
    }
}
