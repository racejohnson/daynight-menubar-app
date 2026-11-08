import Dispatch
import Foundation

/// The outcome of one transition.
public struct TransitionReport: Equatable, Sendable {
    public var elapsed: Duration = .zero
    public var failedDisplays: Set<UInt32> = []
    public var keyboardFailed = false
    public var autoBrightnessFailed = false
    public var cancelled = false

    public var hasFailures: Bool {
        !failedDisplays.isEmpty || keyboardFailed || autoBrightnessFailed
    }
}

/// A hardware reading plus the displays that appeared since the previous one.
public struct HardwareReading: Equatable, Sendable {
    public var snapshot: HardwareSnapshot
    public var newDisplays: Set<UInt32>
}

/// Owns every read and write of display and keyboard brightness.
///
/// The actor runs on its own serial queue, so the private frameworks' blocking
/// calls never occupy the main thread or the cooperative pool. Only one
/// transition runs at a time: starting another cancels it.
public actor BrightnessController {
    public static let fadeDuration: Duration = .milliseconds(600)
    static let frameInterval: Duration = .seconds(1) / 60

    private let displays: any DisplayControlling
    private let keyboard: any KeyboardControlling
    private var autoBrightness: AutoBrightnessGuard
    private var knownDisplays: Set<UInt32>?
    private var current: Task<TransitionReport, Never>?
    /// Set at quit: no write may follow the auto-brightness restore.
    private var isClosed = false
    private let queue = DispatchSerialQueue(label: "com.racejohnson.DayNight.hardware", qos: .userInitiated)

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    public init(
        displays: any DisplayControlling = SystemDisplays(),
        keyboard: any KeyboardControlling = SystemKeyboard(),
        defaultsSuite: String? = nil
    ) {
        self.displays = displays
        self.keyboard = keyboard
        autoBrightness = AutoBrightnessGuard(
            keyboard: keyboard,
            defaults: defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        )
    }

    // MARK: Reading

    public func snapshot() -> HardwareSnapshot {
        var values: [UInt32: Double] = [:]
        for id in displays.onlineDisplayIDs() where displays.canControlBrightness(of: id) {
            values[id] = displays.brightness(of: id)
        }
        return HardwareSnapshot(
            displays: values,
            keyboard: keyboard.isAvailable ? keyboard.brightness() : nil
        )
    }

    /// Reads the hardware and reports displays that are new since the last
    /// reading. The first reading establishes the baseline and reports none.
    public func read() -> HardwareReading {
        let snapshot = snapshot()
        let ids = Set(snapshot.displays.keys)
        defer { knownDisplays = ids }
        return HardwareReading(
            snapshot: snapshot,
            newDisplays: knownDisplays.map { ids.subtracting($0) } ?? []
        )
    }

    // MARK: Writing

    /// Fades to `preset`, cancelling any transition already running.
    /// A zero duration applies it in a single step.
    public func transition(
        to preset: BrightnessPreset,
        duration: Duration = fadeDuration,
        displays only: Set<UInt32>? = nil,
        includeKeyboard: Bool = true
    ) async -> TransitionReport {
        guard !isClosed else { return TransitionReport(cancelled: true) }
        let previous = current
        previous?.cancel()
        let task = Task {
            _ = await previous?.value
            return await run(to: preset, duration: duration, only: only, includeKeyboard: includeKeyboard)
        }
        current = task
        let report = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if current == task { current = nil }
        return report
    }

    // MARK: Keyboard auto-brightness

    public func recoverLeftoverAutoBrightness() -> AutoBrightnessResult {
        autoBrightness.recoverLeftover()
    }

    /// Stops any transition, refuses new ones, and restores keyboard
    /// auto-brightness. Call once, at quit.
    public func restoreAutoBrightness() async -> AutoBrightnessResult {
        isClosed = true
        let running = current
        running?.cancel()
        _ = await running?.value
        return autoBrightness.restore()
    }

    // MARK: Private

    private func run(
        to preset: BrightnessPreset,
        duration: Duration,
        only: Set<UInt32>?,
        includeKeyboard: Bool
    ) async -> TransitionReport {
        let clock = ContinuousClock()
        let start = clock.now
        var report = TransitionReport()
        guard !Task.isCancelled else {
            report.cancelled = true
            return report
        }

        let initial = snapshot()
        let displayStarts = initial.displays.filter { only?.contains($0.key) ?? true }
        let keyboardStart = includeKeyboard ? initial.keyboard : nil
        if keyboardStart != nil, autoBrightness.prepare() == .failed {
            report.autoBrightnessFailed = true
        }

        let steps = max(1, Int((duration / Self.frameInterval).rounded(.up)))
        for step in 1...steps {
            if steps > 1 {
                try? await clock.sleep(
                    until: start + duration * (Double(step) / Double(steps)),
                    tolerance: .milliseconds(2)
                )
            }
            if Task.isCancelled {
                report.cancelled = true
                break
            }
            let progress = Double(step) / Double(steps)
            for (id, from) in displayStarts {
                let value = Easing.interpolate(from: from, to: preset.screen, progress: progress)
                if !displays.setBrightness(value, of: id) { report.failedDisplays.insert(id) }
            }
            if let from = keyboardStart {
                let value = Easing.interpolate(from: from, to: preset.keyboard, progress: progress)
                if !keyboard.setBrightness(value) { report.keyboardFailed = true }
            }
        }
        report.elapsed = clock.now - start
        return report
    }
}
