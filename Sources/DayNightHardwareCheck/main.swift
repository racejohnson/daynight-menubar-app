import DayNightCore
import Foundation

private enum CheckError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String)
throws {
    if !condition() { throw CheckError.failed(message) }
}

private func describe(_ snapshot: HardwareSnapshot) -> String {
    let displays = snapshot.displayValues.keys.sorted().map {
        String(format: "0x%x=%.1f%%", $0, (snapshot.displayValues[$0] ?? 0) * 100)
    }.joined(separator: ", ")
    let keyboard = snapshot.keyboardValue.map {
        String(format: "%.1f%%", $0 * 100)
    } ?? "unavailable"
    return "displays [\(displays)], keyboard \(keyboard)"
}

private func verify(
    _ snapshot: HardwareSnapshot,
    preset: BrightnessPreset,
    label: String
) throws {
    try require(snapshot.displayValues.count >= 2,
                "\(label): fewer than two controllable Apple displays")
    for (id, value) in snapshot.displayValues {
        try require(
            abs(value - preset.screen) <= 0.02,
            String(format: "%@: display 0x%x is %.1f%%", label, id, value * 100)
        )
    }
    guard let keyboard = snapshot.keyboardValue else {
        throw CheckError.failed("\(label): keyboard unavailable")
    }
    try require(
        abs(keyboard - preset.keyboard) <= 0.02,
        String(format: "%@: keyboard is %.1f%%", label, keyboard * 100)
    )
}

private func runCheck() throws {
    let displays = NativeDisplayController()
    let keyboard = NativeKeyboardController()
    let baseline = HardwareReader.capture(
        displayController: displays,
        keyboardController: keyboard
    )
    let baselineAuto = keyboard.autoBrightnessEnabled()
    print("Baseline: \(describe(baseline)); keyboard auto \(String(describing: baselineAuto))")

    try require(baseline.displayValues.count >= 2,
                "Expected both built-in and Studio Display")
    try require(baseline.keyboardValue != nil, "Built-in keyboard is unavailable")
    guard let baselineAuto else {
        throw CheckError.failed("Could not read keyboard auto-brightness")
    }

    let suite = "DayNightHardwareCheck.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let recovery = KeyboardAutoBrightnessRecovery(
        keyboardController: keyboard,
        defaults: defaults
    )

    defer {
        for (id, value) in baseline.displayValues {
            _ = displays.setBrightness(value, displayID: id)
        }
        if let value = baseline.keyboardValue {
            _ = keyboard.setBrightness(value)
        }
        _ = recovery.restoreOnQuit()
        _ = keyboard.setAutoBrightnessEnabled(baselineAuto)
        defaults.removePersistentDomain(forName: suite)
        Thread.sleep(forTimeInterval: 0.15)
        let restored = HardwareReader.capture(
            displayController: displays,
            keyboardController: keyboard
        )
        print("Restored: \(describe(restored)); keyboard auto \(String(describing: keyboard.autoBrightnessEnabled()))")
    }

    try require(recovery.prepareForControl() == .succeeded,
                "Could not snapshot/disable keyboard auto-brightness")
    try require(keyboard.autoBrightnessEnabled() == false,
                "Keyboard auto-brightness did not disable")
    print("Auto-brightness snapshot and disable: PASS")

    let dayReport = TransitionRunner.run(
        displayController: displays,
        keyboardController: keyboard,
        preset: .defaultDay,
        duration: 0.6
    )
    let daySnapshot = HardwareReader.capture(
        displayController: displays,
        keyboardController: keyboard
    )
    try verify(daySnapshot, preset: .defaultDay, label: "Day")
    try require(dayReport.elapsed >= 0.55 && dayReport.elapsed <= 1.2,
                "Day fade timing was \(dayReport.elapsed) seconds")
    try require(dayReport.failedDisplayIDs.isEmpty && !dayReport.keyboardFailed,
                "Day transition reported a control failure")
    print(String(format: "Day target and fade (%.3f s): PASS — %@",
                 dayReport.elapsed, describe(daySnapshot)))

    let nightReport = TransitionRunner.run(
        displayController: displays,
        keyboardController: keyboard,
        preset: .defaultNight,
        duration: 0.6
    )
    let nightSnapshot = HardwareReader.capture(
        displayController: displays,
        keyboardController: keyboard
    )
    try verify(nightSnapshot, preset: .defaultNight, label: "Night")
    try require(nightReport.elapsed >= 0.55 && nightReport.elapsed <= 1.2,
                "Night fade timing was \(nightReport.elapsed) seconds")
    try require(nightReport.failedDisplayIDs.isEmpty && !nightReport.keyboardFailed,
                "Night transition reported a control failure")
    print(String(format: "Night target and fade (%.3f s): PASS — %@",
                 nightReport.elapsed, describe(nightSnapshot)))

    guard let changedDisplayID = nightSnapshot.displayValues.keys.sorted().first
    else {
        throw CheckError.failed("No display available for Custom-state check")
    }
    try require(displays.setBrightness(0.35, displayID: changedDisplayID),
                "Could not make a manual display-brightness change")
    Thread.sleep(forTimeInterval: 0.12)
    let customSnapshot = HardwareReader.capture(
        displayController: displays,
        keyboardController: keyboard
    )
    let inferred = StateEngine.infer(
        snapshot: customSnapshot,
        day: .defaultDay,
        night: .defaultNight
    )
    let clickTarget = StateEngine.modeForClick(
        inferredState: inferred,
        snapshot: customSnapshot,
        day: .defaultDay,
        night: .defaultNight,
        lastAppliedMode: .night
    )
    try require(inferred == .custom, "Manual change did not infer Custom")
    try require(clickTarget == .day,
                "Custom click did not choose the opposite of nearest Night")
    print("Manual change → Custom → next click Day: PASS")

    try require(recovery.restoreOnQuit() == .succeeded,
                "Quit restoration of keyboard auto-brightness failed")
    try require(keyboard.autoBrightnessEnabled() == baselineAuto,
                "Quit restoration produced the wrong auto-brightness state")
    print("Quit restoration: PASS")

    try require(recovery.prepareForControl() == .succeeded,
                "Could not prepare abnormal-exit recovery test")
    let relaunchedRecovery = KeyboardAutoBrightnessRecovery(
        keyboardController: keyboard,
        defaults: defaults
    )
    try require(relaunchedRecovery.recoverIfNeeded() == .succeeded,
                "Abnormal-exit recovery failed")
    try require(keyboard.autoBrightnessEnabled() == baselineAuto,
                "Abnormal-exit recovery restored the wrong state")
    print("Abnormal-exit next-launch recovery: PASS")
}

do {
    try runCheck()
    print("DAYNIGHT HARDWARE CHECK: PASS")
} catch {
    fputs("DAYNIGHT HARDWARE CHECK: FAIL — \(error)\n", stderr)
    exit(1)
}
