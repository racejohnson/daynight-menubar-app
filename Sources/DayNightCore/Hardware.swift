import CoreGraphics
import DayNightPrivateAPI
import Foundation

public protocol DisplayControlling: AnyObject {
    func onlineDisplayIDs() -> [UInt32]
    func canControlBrightness(displayID: UInt32) -> Bool
    func brightness(displayID: UInt32) -> Double?
    @discardableResult
    func setBrightness(_ value: Double, displayID: UInt32) -> Bool
}

public protocol KeyboardControlling: AnyObject {
    var isAvailable: Bool { get }
    func brightness() -> Double?
    @discardableResult
    func setBrightness(_ value: Double) -> Bool
    func autoBrightnessEnabled() -> Bool?
    @discardableResult
    func setAutoBrightnessEnabled(_ enabled: Bool) -> Bool
}

public final class NativeDisplayController: DisplayControlling {
    public init() {}

    public func onlineDisplayIDs() -> [UInt32] {
        var displayIDs = Array(repeating: CGDirectDisplayID(), count: 16)
        var count: UInt32 = 0
        let error = CGGetOnlineDisplayList(
            UInt32(displayIDs.count), &displayIDs, &count
        )
        guard error == .success else { return [] }
        return Array(displayIDs.prefix(Int(count)))
    }

    public func canControlBrightness(displayID: UInt32) -> Bool {
        DNDisplayCanChangeBrightness(displayID)
    }

    public func brightness(displayID: UInt32) -> Double? {
        var value: Float = 0
        guard DNDisplayGetBrightness(displayID, &value) else { return nil }
        return Double(value)
    }

    @discardableResult
    public func setBrightness(_ value: Double, displayID: UInt32) -> Bool {
        DNDisplaySetBrightness(displayID, Float(BrightnessPreset.clamp(value)))
    }
}

public final class NativeKeyboardController: KeyboardControlling {
    public init() {}

    public var isAvailable: Bool {
        DNKeyboardAvailable()
    }

    public func brightness() -> Double? {
        var value: Float = 0
        guard DNKeyboardGetBrightness(&value) else { return nil }
        return Double(value)
    }

    @discardableResult
    public func setBrightness(_ value: Double) -> Bool {
        DNKeyboardSetBrightness(Float(BrightnessPreset.clamp(value)))
    }

    public func autoBrightnessEnabled() -> Bool? {
        var enabled = false
        guard DNKeyboardGetAutoBrightness(&enabled) else { return nil }
        return enabled
    }

    @discardableResult
    public func setAutoBrightnessEnabled(_ enabled: Bool) -> Bool {
        DNKeyboardSetAutoBrightness(enabled)
    }
}

public enum HardwareReader {
    public static func capture(
        displayController: DisplayControlling,
        keyboardController: KeyboardControlling
    ) -> HardwareSnapshot {
        var values: [UInt32: Double] = [:]
        for displayID in displayController.onlineDisplayIDs() {
            guard displayController.canControlBrightness(displayID: displayID),
                  let value = displayController.brightness(displayID: displayID)
            else {
                continue
            }
            values[displayID] = value
        }

        let keyboardValue = keyboardController.isAvailable
            ? keyboardController.brightness()
            : nil
        return HardwareSnapshot(
            displayValues: values,
            keyboardValue: keyboardValue
        )
    }
}

public enum TransitionRunner {
    public static func run(
        displayController: DisplayControlling,
        keyboardController: KeyboardControlling,
        preset: BrightnessPreset,
        duration: TimeInterval,
        selectedDisplayIDs: Set<UInt32>? = nil,
        includeKeyboard: Bool = true,
        shouldContinue: () -> Bool = { true }
    ) -> TransitionReport {
        let startTime = ProcessInfo.processInfo.systemUptime
        let snapshot = HardwareReader.capture(
            displayController: displayController,
            keyboardController: keyboardController
        )
        let availableIDs = Set(snapshot.displayValues.keys)
        let attemptedIDs = selectedDisplayIDs.map {
            availableIDs.intersection($0)
        } ?? availableIDs
        let keyboardAttempted = includeKeyboard && snapshot.keyboardValue != nil
        var failedDisplayIDs = Set<UInt32>()
        var keyboardFailed = false
        var cancelled = false

        let steps = TransitionMath.stepCount(duration: duration)
        for step in 1...steps {
            if !shouldContinue() {
                cancelled = true
                break
            }

            if duration > 0 {
                let deadline = startTime + duration * Double(step) / Double(steps)
                let delay = deadline - ProcessInfo.processInfo.systemUptime
                if delay > 0 {
                    Thread.sleep(forTimeInterval: delay)
                }
            }

            let progress = Double(step) / Double(steps)
            for displayID in attemptedIDs {
                guard let initial = snapshot.displayValues[displayID] else {
                    continue
                }
                let value = TransitionMath.interpolate(
                    from: initial, to: preset.screen, progress: progress
                )
                if !displayController.setBrightness(
                    value, displayID: displayID
                ) {
                    failedDisplayIDs.insert(displayID)
                }
            }

            if keyboardAttempted, let initial = snapshot.keyboardValue {
                let value = TransitionMath.interpolate(
                    from: initial, to: preset.keyboard, progress: progress
                )
                if !keyboardController.setBrightness(value) {
                    keyboardFailed = true
                }
            }
        }

        return TransitionReport(
            elapsed: ProcessInfo.processInfo.systemUptime - startTime,
            displayIDsAttempted: attemptedIDs,
            failedDisplayIDs: failedDisplayIDs,
            keyboardAttempted: keyboardAttempted,
            keyboardFailed: keyboardFailed,
            cancelled: cancelled
        )
    }
}

public final class HardwareCoordinator {
    private let displayController: DisplayControlling
    private let keyboardController: KeyboardControlling
    private let queue = DispatchQueue(
        label: "com.racejohnson.DayNight.hardware",
        qos: .userInitiated
    )
    private let generationLock = NSLock()
    private var generation: UInt64 = 0
    private var knownDisplayIDs = Set<UInt32>()

    public init(
        displayController: DisplayControlling = NativeDisplayController(),
        keyboardController: KeyboardControlling = NativeKeyboardController()
    ) {
        self.displayController = displayController
        self.keyboardController = keyboardController
    }

    public func poll(completion: @escaping (HardwarePollResult) -> Void) {
        queue.async {
            let snapshot = HardwareReader.capture(
                displayController: self.displayController,
                keyboardController: self.keyboardController
            )
            let availableIDs = Set(snapshot.displayValues.keys)
            let newIDs = availableIDs.subtracting(self.knownDisplayIDs)
            self.knownDisplayIDs = availableIDs
            DispatchQueue.main.async {
                completion(HardwarePollResult(
                    snapshot: snapshot,
                    newlyAvailableDisplayIDs: newIDs
                ))
            }
        }
    }

    public func transition(
        to preset: BrightnessPreset,
        duration: TimeInterval = 0.6,
        selectedDisplayIDs: Set<UInt32>? = nil,
        includeKeyboard: Bool = true,
        completion: ((TransitionReport) -> Void)? = nil
    ) {
        let token = nextGeneration()
        queue.async {
            let report = TransitionRunner.run(
                displayController: self.displayController,
                keyboardController: self.keyboardController,
                preset: preset,
                duration: duration,
                selectedDisplayIDs: selectedDisplayIDs,
                includeKeyboard: includeKeyboard,
                shouldContinue: { self.currentGeneration() == token }
            )
            DispatchQueue.main.async {
                completion?(report)
            }
        }
    }

    public func cancelTransitions() {
        _ = nextGeneration()
    }

    private func nextGeneration() -> UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        generation &+= 1
        return generation
    }

    private func currentGeneration() -> UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation
    }
}
