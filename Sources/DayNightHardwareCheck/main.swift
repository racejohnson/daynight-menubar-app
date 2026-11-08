// Exercises the real displays and keyboard backlight end to end, then puts
// every level and the keyboard auto-brightness setting back as it found them.
// Needs the built-in display, a second Apple display and a backlit keyboard.

import DayNightCore
import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw CheckFailure(description: message()) }
}

func describe(_ snapshot: HardwareSnapshot) -> String {
    let displays = snapshot.displays.keys.sorted().map {
        String(format: "0x%x=%.1f%%", $0, snapshot.displays[$0]! * 100)
    }
    let keyboard = snapshot.keyboard.map { String(format: "%.1f%%", $0 * 100) } ?? "unavailable"
    return "displays [\(displays.joined(separator: ", "))], keyboard \(keyboard)"
}

func verify(_ snapshot: HardwareSnapshot, matches preset: BrightnessPreset, _ label: String) throws {
    try require(StateEngine.matches(snapshot, preset), "\(label): \(describe(snapshot))")
}

func verifyFade(_ report: TransitionReport, _ label: String) throws {
    let seconds = report.elapsed / .seconds(1)
    try require(!report.hasFailures, "\(label): a control reported failure")
    try require((0.55...1.2).contains(seconds), "\(label): fade took \(seconds) s")
    print(String(format: "%@ fade (%.3f s): PASS", label, seconds))
}

let displays = SystemDisplays()
let keyboard = SystemKeyboard()
let suite = "DayNightHardwareCheck.\(UUID().uuidString)"
let controller = BrightnessController(displays: displays, keyboard: keyboard, defaultsSuite: suite)

let baseline = await controller.snapshot()
let baselineAuto = keyboard.isAutoBrightnessEnabled()
print("Baseline: \(describe(baseline)); keyboard auto-brightness \(baselineAuto.map(String.init) ?? "unknown")")

func restoreBaseline() async {
    for (id, value) in baseline.displays { _ = displays.setBrightness(value, of: id) }
    if let value = baseline.keyboard { _ = keyboard.setBrightness(value) }
    if let baselineAuto { _ = keyboard.setAutoBrightnessEnabled(baselineAuto) }
    UserDefaults.standard.removePersistentDomain(forName: suite)
    try? await Task.sleep(for: .milliseconds(150))
    print("Restored: \(describe(await controller.snapshot()))")
}

do {
    try require(baseline.displays.count >= 2, "Expected the built-in display and a second Apple display")
    try require(baseline.keyboard != nil, "Built-in keyboard backlight is unavailable")
    try require(baselineAuto != nil, "Could not read keyboard auto-brightness")

    let day = await controller.transition(to: .defaultDay)
    try verify(await controller.snapshot(), matches: .defaultDay, "Day")
    try verifyFade(day, "Day")
    try require(keyboard.isAutoBrightnessEnabled() == false, "Auto-brightness was not turned off")
    print("Auto-brightness snapshot and disable: PASS")

    let night = await controller.transition(to: .defaultNight)
    try verify(await controller.snapshot(), matches: .defaultNight, "Night")
    try verifyFade(night, "Night")

    let instant = await controller.transition(to: .defaultDay, duration: .zero)
    try verify(await controller.snapshot(), matches: .defaultDay, "Instant Day")
    try require(!instant.hasFailures, "Instant apply reported a failure")
    print("Instant apply: PASS")
    _ = await controller.transition(to: .defaultNight, duration: .zero)

    let manual = baseline.displays.keys.sorted()[0]
    try require(displays.setBrightness(0.35, of: manual), "Could not make a manual display change")
    try await Task.sleep(for: .milliseconds(120))
    let custom = await controller.snapshot()
    let state = StateEngine.infer(custom, day: .defaultDay, night: .defaultNight)
    try require(state == .custom, "A manual change did not read as Custom")
    let target = StateEngine.clickTarget(
        from: state, snapshot: custom, day: .defaultDay, night: .defaultNight, lastApplied: .night
    )
    try require(target == .day, "Custom near Night should click to Day")
    print("Manual change → Custom → next click Day: PASS")

    try require(await controller.restoreAutoBrightness() == .succeeded, "Quit restoration failed")
    try require(keyboard.isAutoBrightnessEnabled() == baselineAuto, "Quit restored the wrong setting")
    print("Quit restoration: PASS")

    // The first session is closed now; a second one stands in for a crashed run.
    let crashed = BrightnessController(displays: displays, keyboard: keyboard, defaultsSuite: suite)
    _ = await crashed.transition(to: .defaultNight, duration: .zero)
    let relaunched = BrightnessController(displays: displays, keyboard: keyboard, defaultsSuite: suite)
    try require(await relaunched.recoverLeftoverAutoBrightness() == .succeeded, "Crash recovery failed")
    try require(keyboard.isAutoBrightnessEnabled() == baselineAuto, "Crash recovery restored the wrong setting")
    print("Abnormal-exit next-launch recovery: PASS")

    await restoreBaseline()
    print("DAYNIGHT HARDWARE CHECK: PASS")
} catch {
    await restoreBaseline()
    FileHandle.standardError.write(Data("DAYNIGHT HARDWARE CHECK: FAIL — \(error)\n".utf8))
    exit(1)
}
