import Foundation
import XCTest
@testable import DayNightCore

final class DayNightCoreTests: XCTestCase {
    func testPresetDefaultsClampingAndPersistence() {
        let (defaults, domain) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }

        let store = PresetStore(defaults: defaults)
        XCTAssertEqual(store.day, .defaultDay)
        XCTAssertEqual(store.night, .defaultNight)

        store.day = BrightnessPreset(screen: 1.8, keyboard: -0.2)
        store.night = BrightnessPreset(screen: 0.33, keyboard: 0.44)

        let reloaded = PresetStore(defaults: defaults)
        XCTAssertEqual(reloaded.day.screen, 1)
        XCTAssertEqual(reloaded.day.keyboard, 0)
        XCTAssertEqual(reloaded.night.screen, 0.33, accuracy: 0.0001)
        XCTAssertEqual(reloaded.night.keyboard, 0.44, accuracy: 0.0001)
        XCTAssertEqual(BrightnessPreset.clamp(.nan), 0)
    }

    func testLastAppliedModePersistence() {
        let (defaults, domain) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = PresetStore(defaults: defaults)

        XCTAssertNil(store.lastAppliedMode)
        store.lastAppliedMode = .night
        XCTAssertEqual(PresetStore(defaults: defaults).lastAppliedMode, .night)
        store.lastAppliedMode = nil
        XCTAssertNil(PresetStore(defaults: defaults).lastAppliedMode)
    }

    func testStateInferenceRequiresEveryAvailableChannelWithinTolerance() {
        let day = BrightnessPreset.defaultDay
        let night = BrightnessPreset.defaultNight
        let daySnapshot = HardwareSnapshot(
            displayValues: [1: 0.981, 2: 1],
            keyboardValue: 0.99
        )
        XCTAssertEqual(
            StateEngine.infer(snapshot: daySnapshot, day: day, night: night),
            .day
        )

        let outsideTolerance = HardwareSnapshot(
            displayValues: [1: 0.979, 2: 1],
            keyboardValue: 1
        )
        XCTAssertEqual(
            StateEngine.infer(
                snapshot: outsideTolerance, day: day, night: night
            ),
            .custom
        )

        let nightSnapshot = HardwareSnapshot(
            displayValues: [1: 0.2, 2: 0.219],
            keyboardValue: 0.081
        )
        XCTAssertEqual(
            StateEngine.infer(snapshot: nightSnapshot, day: day, night: night),
            .night
        )
        XCTAssertEqual(
            StateEngine.infer(
                snapshot: HardwareSnapshot(), day: day, night: night
            ),
            .custom
        )
    }

    func testCustomClickUsesNearestPresetAndTieRules() {
        let day = BrightnessPreset.defaultDay
        let night = BrightnessPreset.defaultNight

        let nearNight = HardwareSnapshot(
            displayValues: [1: 0.25, 2: 0.2], keyboardValue: 0.12
        )
        XCTAssertEqual(
            StateEngine.modeForClick(
                inferredState: .custom,
                snapshot: nearNight,
                day: day,
                night: night,
                lastAppliedMode: .night
            ),
            .day
        )

        let nearDay = HardwareSnapshot(
            displayValues: [1: 0.9, 2: 1], keyboardValue: 0.95
        )
        XCTAssertEqual(
            StateEngine.modeForClick(
                inferredState: .custom,
                snapshot: nearDay,
                day: day,
                night: night,
                lastAppliedMode: .day
            ),
            .night
        )

        let tie = HardwareSnapshot(
            displayValues: [1: 0.6], keyboardValue: 0.55
        )
        XCTAssertEqual(
            StateEngine.modeForClick(
                inferredState: .custom,
                snapshot: tie,
                day: day,
                night: night,
                lastAppliedMode: nil
            ),
            .night
        )
        XCTAssertEqual(
            StateEngine.modeForClick(
                inferredState: .custom,
                snapshot: tie,
                day: day,
                night: night,
                lastAppliedMode: .night
            ),
            .day
        )
        XCTAssertEqual(
            StateEngine.modeForClick(
                inferredState: .day,
                snapshot: nearDay,
                day: day,
                night: night,
                lastAppliedMode: nil
            ),
            .night
        )
    }

    func testTransitionCalculation() {
        XCTAssertEqual(TransitionMath.easedProgress(-1), 0)
        XCTAssertEqual(TransitionMath.easedProgress(0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(TransitionMath.easedProgress(2), 1)
        XCTAssertEqual(
            TransitionMath.interpolate(from: 0.2, to: 1, progress: 0.5),
            0.6,
            accuracy: 0.0001
        )
        XCTAssertEqual(TransitionMath.stepCount(duration: 0.6), 18)
        XCTAssertEqual(TransitionMath.stepCount(duration: 0), 1)
    }

    func testMissingAndFailingDisplaysDoNotBlockAvailableChannels() {
        let displays = MockDisplayController(
            identifiers: [1, 2, 3],
            controllable: [1, 2],
            values: [1: 0.5],
            failingSetIDs: [1]
        )
        let keyboard = MockKeyboardController(
            brightnessValue: 0.4,
            setBrightnessSucceeds: false
        )

        let snapshot = HardwareReader.capture(
            displayController: displays,
            keyboardController: keyboard
        )
        XCTAssertEqual(snapshot.displayValues, [1: 0.5])
        XCTAssertEqual(snapshot.keyboardValue, 0.4)

        let report = TransitionRunner.run(
            displayController: displays,
            keyboardController: keyboard,
            preset: .defaultNight,
            duration: 0
        )
        XCTAssertEqual(report.displayIDsAttempted, [1])
        XCTAssertEqual(report.failedDisplayIDs, [1])
        XCTAssertTrue(report.keyboardAttempted)
        XCTAssertTrue(report.keyboardFailed)
        XCTAssertEqual(displays.setAttempts.map(\.0), [1])
    }

    func testCoordinatorReturnsImmediatelyWhileTransitionRunsOffMainThread() {
        let displays = MockDisplayController(
            identifiers: [1],
            controllable: [1],
            values: [1: 1]
        )
        let keyboard = MockKeyboardController(brightnessValue: 1)
        let coordinator = HardwareCoordinator(
            displayController: displays,
            keyboardController: keyboard
        )
        let completed = expectation(description: "transition completion")

        let start = ProcessInfo.processInfo.systemUptime
        coordinator.transition(to: .defaultNight, duration: 0.12) { report in
            XCTAssertGreaterThanOrEqual(report.elapsed, 0.10)
            completed.fulfill()
        }
        let callElapsed = ProcessInfo.processInfo.systemUptime - start
        XCTAssertLessThan(callElapsed, 0.05)
        wait(for: [completed], timeout: 1)
    }

    func testLivePreviewPolicy() {
        XCTAssertTrue(
            LivePreviewPolicy.shouldPreview(
                editedMode: .day, inferredState: .day, applyingMode: nil
            )
        )
        XCTAssertTrue(
            LivePreviewPolicy.shouldPreview(
                editedMode: .night,
                inferredState: .custom,
                applyingMode: .night
            )
        )
        XCTAssertFalse(
            LivePreviewPolicy.shouldPreview(
                editedMode: .night, inferredState: .custom, applyingMode: nil
            )
        )
    }

    func testAutoBrightnessRecoveryAfterQuitAndAbnormalExit() {
        let (defaults, domain) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let keyboard = MockKeyboardController(
            brightnessValue: 0.5,
            autoBrightness: true
        )
        var recovery = KeyboardAutoBrightnessRecovery(
            keyboardController: keyboard,
            defaults: defaults
        )

        XCTAssertEqual(recovery.prepareForControl(), .succeeded)
        XCTAssertEqual(keyboard.autoBrightness, false)
        XCTAssertTrue(recovery.hasRecoveryMarker)
        XCTAssertEqual(recovery.restoreOnQuit(), .succeeded)
        XCTAssertEqual(keyboard.autoBrightness, true)
        XCTAssertFalse(recovery.hasRecoveryMarker)

        XCTAssertEqual(recovery.prepareForControl(), .succeeded)
        XCTAssertEqual(keyboard.autoBrightness, false)
        recovery = KeyboardAutoBrightnessRecovery(
            keyboardController: keyboard,
            defaults: defaults
        )
        XCTAssertEqual(recovery.recoverIfNeeded(), .succeeded)
        XCTAssertEqual(keyboard.autoBrightness, true)
        XCTAssertFalse(recovery.hasRecoveryMarker)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let domain = "DayNightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        return (defaults, domain)
    }
}

private final class MockDisplayController: DisplayControlling {
    let identifiers: [UInt32]
    let controllable: Set<UInt32>
    var values: [UInt32: Double]
    let failingSetIDs: Set<UInt32>
    var setAttempts: [(UInt32, Double)] = []

    init(
        identifiers: [UInt32],
        controllable: Set<UInt32>,
        values: [UInt32: Double],
        failingSetIDs: Set<UInt32> = []
    ) {
        self.identifiers = identifiers
        self.controllable = controllable
        self.values = values
        self.failingSetIDs = failingSetIDs
    }

    func onlineDisplayIDs() -> [UInt32] { identifiers }

    func canControlBrightness(displayID: UInt32) -> Bool {
        controllable.contains(displayID)
    }

    func brightness(displayID: UInt32) -> Double? {
        values[displayID]
    }

    func setBrightness(_ value: Double, displayID: UInt32) -> Bool {
        setAttempts.append((displayID, value))
        guard !failingSetIDs.contains(displayID) else { return false }
        values[displayID] = value
        return true
    }
}

private final class MockKeyboardController: KeyboardControlling {
    var brightnessValue: Double?
    var autoBrightness: Bool
    let setBrightnessSucceeds: Bool
    let setAutoSucceeds: Bool

    init(
        brightnessValue: Double?,
        autoBrightness: Bool = true,
        setBrightnessSucceeds: Bool = true,
        setAutoSucceeds: Bool = true
    ) {
        self.brightnessValue = brightnessValue
        self.autoBrightness = autoBrightness
        self.setBrightnessSucceeds = setBrightnessSucceeds
        self.setAutoSucceeds = setAutoSucceeds
    }

    var isAvailable: Bool { brightnessValue != nil }
    func brightness() -> Double? { brightnessValue }

    func setBrightness(_ value: Double) -> Bool {
        guard setBrightnessSucceeds else { return false }
        brightnessValue = value
        return true
    }

    func autoBrightnessEnabled() -> Bool? {
        isAvailable ? autoBrightness : nil
    }

    func setAutoBrightnessEnabled(_ enabled: Bool) -> Bool {
        guard isAvailable, setAutoSucceeds else { return false }
        autoBrightness = enabled
        return true
    }
}
