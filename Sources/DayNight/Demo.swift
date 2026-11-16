import DayNightCore
import Foundation
import ServiceManagement
import Synchronization

/// A made-up Mac: two displays and a keyboard light that exist only in
/// memory, with throwaway settings. The README's pictures and the self-test
/// run on it, so they never touch the real brightness, the real settings or
/// the login item.
struct Demo {
    let model: AppModel
    let displays: DemoDisplays
    let keyboard: DemoKeyboard

    private static let suite = "com.racejohnson.DayNight.demo"

    @MainActor
    init() {
        UserDefaults.standard.removePersistentDomain(forName: Self.suite)
        displays = DemoDisplays([1: 1, 2: 1])
        keyboard = DemoKeyboard(1)
        model = AppModel(defaultsSuite: Self.suite, displays: displays, keyboard: keyboard, loginService: DemoLoginItem())
    }

    /// Puts the made-up hardware at `preset` and has the model read it.
    @MainActor
    func show(_ preset: BrightnessPreset) async {
        displays.set(preset.screen)
        keyboard.set(preset.keyboard)
        await model.refresh()
    }

    static func cleanUp() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }
}

final class DemoDisplays: DisplayControlling {
    private let values: Mutex<[UInt32: Double]>

    init(_ values: [UInt32: Double]) {
        self.values = Mutex(values)
    }

    var levels: [UInt32: Double] { values.withLock { $0 } }

    func set(_ value: Double) {
        values.withLock { values in
            for id in values.keys { values[id] = value }
        }
    }

    func onlineDisplayIDs() -> [UInt32] { values.withLock { $0.keys.sorted() } }
    func canControlBrightness(of display: UInt32) -> Bool { true }
    func brightness(of display: UInt32) -> Double? { values.withLock { $0[display] } }

    func setBrightness(_ value: Double, of display: UInt32) -> Bool {
        values.withLock { $0[display] = value }
        return true
    }
}

final class DemoKeyboard: KeyboardControlling {
    private let state: Mutex<(level: Double, auto: Bool)>

    init(_ level: Double) {
        state = Mutex((level, true))
    }

    var level: Double { state.withLock { $0.level } }

    func set(_ value: Double) { state.withLock { $0.level = value } }

    var isAvailable: Bool { true }
    func brightness() -> Double? { level }

    func setBrightness(_ value: Double) -> Bool {
        set(value)
        return true
    }

    func isAutoBrightnessEnabled() -> Bool? { state.withLock { $0.auto } }

    func setAutoBrightnessEnabled(_ enabled: Bool) -> Bool {
        state.withLock { $0.auto = enabled }
        return true
    }
}

private struct DemoLoginItem: LoginItemService {
    var status: SMAppService.Status { .enabled }
    func register() throws {}
    func unregister() throws {}
}
