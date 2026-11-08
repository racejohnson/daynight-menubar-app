import DayNightCore
import Foundation
import Testing

struct AutoBrightnessTests {
    let isolated = IsolatedDefaults()

    var pending: Bool { isolated.defaults.bool(forKey: "keyboard.autoBrightness.recoveryPending") }

    @Test func firstKeyboardWriteDisablesAndQuitRestores() async {
        let keyboard = MockKeyboard(0.5, autoBrightness: true)
        let hardware = BrightnessController(displays: MockDisplays([:]), keyboard: keyboard, defaultsSuite: isolated.suite)

        _ = await hardware.transition(to: .defaultNight, duration: .zero)
        #expect(!keyboard.autoBrightness)
        #expect(pending)
        #expect(isolated.defaults.object(forKey: "keyboard.autoBrightness.priorEnabled") as? Bool == true)

        #expect(await hardware.restoreAutoBrightness() == .succeeded)
        #expect(keyboard.autoBrightness)
        #expect(!pending)
        #expect(await hardware.restoreAutoBrightness() == .nothingToDo)
    }

    @Test func nextLaunchRecoversAfterACrash() async {
        let keyboard = MockKeyboard(0.5, autoBrightness: true)
        let crashed = BrightnessController(displays: MockDisplays([:]), keyboard: keyboard, defaultsSuite: isolated.suite)
        _ = await crashed.transition(to: .defaultDay, duration: .zero)
        #expect(!keyboard.autoBrightness)

        let relaunched = BrightnessController(displays: MockDisplays([:]), keyboard: keyboard, defaultsSuite: isolated.suite)
        #expect(pending)
        #expect(await relaunched.recoverLeftoverAutoBrightness() == .succeeded)
        #expect(keyboard.autoBrightness)
        #expect(!pending)
    }

    @Test func aLeftoverMarkerKeepsTheOriginalSetting() async {
        // A crash left auto-brightness forced off; the keyboard was missing at
        // the next launch, so recovery could not run before DayNight wrote again.
        isolated.defaults.set(true, forKey: "keyboard.autoBrightness.recoveryPending")
        isolated.defaults.set(true, forKey: "keyboard.autoBrightness.priorEnabled")
        let keyboard = MockKeyboard(nil, autoBrightness: false)
        let hardware = BrightnessController(displays: MockDisplays([:]), keyboard: keyboard, defaultsSuite: isolated.suite)

        #expect(await hardware.recoverLeftoverAutoBrightness() == .keyboardUnavailable)
        keyboard.plug(at: 0.3)
        _ = await hardware.transition(to: .defaultNight, duration: .zero)
        #expect(await hardware.recoverLeftoverAutoBrightness() == .nothingToDo, "this session now owns the marker")

        #expect(await hardware.restoreAutoBrightness() == .succeeded)
        #expect(keyboard.autoBrightness, "restores the user's setting, not the forced-off one")
    }

    @Test func noWriteFollowsTheQuitRestore() async {
        let keyboard = MockKeyboard(0.5, autoBrightness: true)
        let hardware = BrightnessController(displays: MockDisplays([1: 1]), keyboard: keyboard, defaultsSuite: isolated.suite)
        _ = await hardware.transition(to: .defaultNight, duration: .zero)
        #expect(await hardware.restoreAutoBrightness() == .succeeded)

        #expect(await hardware.transition(to: .defaultDay, duration: .zero).cancelled)
        #expect(keyboard.autoBrightness, "a late write must not switch it off again")
        #expect(!pending)
        #expect(keyboard.level == 0.1)
    }

    @Test func nothingHappensWithoutAKeyboard() async {
        let keyboard = MockKeyboard(nil)
        let hardware = BrightnessController(displays: MockDisplays([1: 1]), keyboard: keyboard, defaultsSuite: isolated.suite)
        _ = await hardware.transition(to: .defaultNight, duration: .zero)
        #expect(!pending)
        #expect(await hardware.restoreAutoBrightness() == .nothingToDo)
    }
}
