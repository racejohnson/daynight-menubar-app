import DayNightCore
import Foundation
import Testing

struct BrightnessControllerTests {
    let isolated = IsolatedDefaults()

    func controller(_ displays: MockDisplays, _ keyboard: MockKeyboard) -> BrightnessController {
        BrightnessController(displays: displays, keyboard: keyboard, defaultsSuite: isolated.suite)
    }

    /// Waits until a fade has really started, without guessing at timing.
    func firstWrite(_ displays: MockDisplays) async {
        while displays.writes.isEmpty { await Task.yield() }
    }

    @Test func snapshotSkipsDisplaysThatCannotBeControlled() async {
        let displays = MockDisplays([1: 0.5], online: [1, 2, 3], controllable: [1, 2])
        let hardware = controller(displays, MockKeyboard(0.4))
        #expect(await hardware.snapshot() == HardwareSnapshot(displays: [1: 0.5], keyboard: 0.4))
    }

    @Test func fadeEndsExactlyAtTheTarget() async {
        let displays = MockDisplays([1: 1, 2: 0.8])
        let keyboard = MockKeyboard(1)
        let hardware = controller(displays, keyboard)

        let report = await hardware.transition(to: .defaultNight, duration: .milliseconds(120))

        #expect(!report.cancelled && !report.hasFailures)
        #expect(report.elapsed >= .milliseconds(110))
        #expect(displays.values == [1: 0.2, 2: 0.2])
        #expect(keyboard.level == 0.1)
        #expect(displays.writes.count > 4, "a fade moves in many small steps")
    }

    @Test func newerTransitionCancelsTheRunningOne() async {
        let displays = MockDisplays([1: 1])
        let keyboard = MockKeyboard(1)
        let hardware = controller(displays, keyboard)

        let slow = Task { await hardware.transition(to: .defaultNight, duration: .seconds(2)) }
        await firstWrite(displays)
        let fast = await hardware.transition(to: .defaultDay, duration: .milliseconds(60))
        let interrupted = await slow.value

        #expect(interrupted.cancelled)
        #expect(interrupted.elapsed < .seconds(1))
        #expect(!fast.cancelled)
        #expect(displays.values[1] == 1)
        #expect(keyboard.level == 1)
    }

    @Test func cancellingTheCallerCancelsTheFade() async {
        let displays = MockDisplays([1: 1])
        let hardware = controller(displays, MockKeyboard(1))
        let task = Task { await hardware.transition(to: .defaultNight, duration: .seconds(2)) }
        await firstWrite(displays)
        task.cancel()
        #expect(await task.value.cancelled)
    }

    @Test func zeroDurationAppliesInOneStep() async {
        let displays = MockDisplays([1: 1, 2: 1])
        let keyboard = MockKeyboard(1)
        let hardware = controller(displays, keyboard)

        let report = await hardware.transition(to: .defaultNight, duration: .zero)

        #expect(!report.cancelled && !report.hasFailures)
        #expect(displays.writes.count == 2)
        #expect(displays.values == [1: 0.2, 2: 0.2])
        #expect(keyboard.level == 0.1)
    }

    @Test func failingChannelsDoNotBlockTheOthers() async {
        let displays = MockDisplays([1: 0.5, 2: 0.5], failing: [1])
        let keyboard = MockKeyboard(0.4, setSucceeds: false)
        let hardware = controller(displays, keyboard)

        let report = await hardware.transition(to: .defaultNight, duration: .zero)

        #expect(report.failedDisplays == [1])
        #expect(report.keyboardFailed)
        #expect(displays.values[2] == 0.2)
    }

    @Test func transitionCanTargetOnlySomeDisplays() async {
        let displays = MockDisplays([1: 0.5, 2: 0.5])
        let keyboard = MockKeyboard(0.5)
        let hardware = controller(displays, keyboard)

        let report = await hardware.transition(to: .defaultNight, duration: .zero, displays: [2], includeKeyboard: false)

        #expect(!report.hasFailures)
        #expect(displays.writes.map(\.id) == [2])
        #expect(displays.values == [1: 0.5, 2: 0.2])
        #expect(keyboard.level == 0.5)
        #expect(keyboard.autoBrightness, "auto-brightness is untouched when the keyboard is not")
    }

    @Test func readReportsDisplaysThatAppearAfterTheFirstReading() async {
        let displays = MockDisplays([1: 1])
        let hardware = controller(displays, MockKeyboard(nil))
        #expect(await hardware.read().newDisplays.isEmpty, "the first reading is the baseline")
        displays.connect(7, at: 0.4)
        #expect(await hardware.read().newDisplays == [7])
        #expect(await hardware.read().newDisplays.isEmpty)
    }

    @Test func instantApplyDuringAFadeWinsImmediately() async {
        let displays = MockDisplays([1: 1])
        let hardware = controller(displays, MockKeyboard(nil))
        let fade = Task { await hardware.transition(to: .defaultNight, duration: .seconds(2)) }
        await firstWrite(displays)
        _ = await hardware.transition(to: BrightnessPreset(screen: 0.7, keyboard: 0), duration: .zero)
        #expect(await fade.value.cancelled)
        #expect(displays.values[1] == 0.7)
    }
}
