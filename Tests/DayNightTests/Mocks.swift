import DayNightCore
import Foundation
import Synchronization

final class MockDisplays: DisplayControlling {
    struct State {
        var values: [UInt32: Double]
        var online: [UInt32]
        var writes: [(id: UInt32, value: Double)] = []
    }

    let state: Mutex<State>
    private let controllable: Set<UInt32>?
    private let failing: Set<UInt32>

    init(
        _ values: [UInt32: Double],
        online: [UInt32]? = nil,
        controllable: Set<UInt32>? = nil,
        failing: Set<UInt32> = []
    ) {
        state = Mutex(State(values: values, online: online ?? values.keys.sorted()))
        self.controllable = controllable
        self.failing = failing
    }

    var values: [UInt32: Double] { state.withLock { $0.values } }
    var writes: [(id: UInt32, value: Double)] { state.withLock { $0.writes } }

    func connect(_ id: UInt32, at value: Double) {
        state.withLock {
            $0.online.append(id)
            $0.values[id] = value
        }
    }

    func onlineDisplayIDs() -> [UInt32] { state.withLock { $0.online } }
    func canControlBrightness(of display: UInt32) -> Bool { controllable?.contains(display) ?? true }
    func brightness(of display: UInt32) -> Double? { state.withLock { $0.values[display] } }

    func setBrightness(_ value: Double, of display: UInt32) -> Bool {
        state.withLock { state in
            state.writes.append((display, value))
            guard !failing.contains(display) else { return false }
            state.values[display] = value
            return true
        }
    }
}

final class MockKeyboard: KeyboardControlling {
    struct State {
        var brightness: Double?
        var autoBrightness: Bool
    }

    let state: Mutex<State>
    private let setSucceeds: Bool

    init(_ brightness: Double?, autoBrightness: Bool = true, setSucceeds: Bool = true) {
        state = Mutex(State(brightness: brightness, autoBrightness: autoBrightness))
        self.setSucceeds = setSucceeds
    }

    var autoBrightness: Bool { state.withLock { $0.autoBrightness } }
    var level: Double? { state.withLock { $0.brightness } }

    func plug(at value: Double) { state.withLock { $0.brightness = value } }

    var isAvailable: Bool { state.withLock { $0.brightness != nil } }
    func brightness() -> Double? { state.withLock { $0.brightness } }

    func setBrightness(_ value: Double) -> Bool {
        guard setSucceeds else { return false }
        state.withLock { $0.brightness = value }
        return true
    }

    func isAutoBrightnessEnabled() -> Bool? {
        state.withLock { $0.brightness == nil ? nil : $0.autoBrightness }
    }

    func setAutoBrightnessEnabled(_ enabled: Bool) -> Bool {
        state.withLock { state in
            guard state.brightness != nil else { return false }
            state.autoBrightness = enabled
            return true
        }
    }
}

/// A throwaway UserDefaults suite, removed when the value is released.
final class IsolatedDefaults {
    let suite = "DayNightTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suite)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suite)
    }
}
