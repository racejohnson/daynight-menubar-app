import Combine
import DayNightCore
import Foundation

final class DayNightViewModel: ObservableObject {
    @Published private(set) var state: DayNightMode = .custom
    @Published private(set) var day: BrightnessPreset
    @Published private(set) var night: BrightnessPreset
    @Published private(set) var applyingMode: DayNightMode?
    @Published private(set) var hardwareSummary = "Checking displays…"
    @Published private(set) var detailMessage = ""

    let launchAtLogin: LaunchAtLoginController

    private let store: PresetStore
    private let hardware: HardwareCoordinator
    private let recovery: KeyboardAutoBrightnessRecovery
    private var latestSnapshot = HardwareSnapshot()
    private var pollTimer: Timer?
    private var pollInFlight = false
    private var applicationSequence: UInt64 = 0

    init(
        defaults: UserDefaults = .standard,
        displayController: DisplayControlling = NativeDisplayController(),
        keyboardController: KeyboardControlling = NativeKeyboardController()
    ) {
        let store = PresetStore(defaults: defaults)
        self.store = store
        day = store.day
        night = store.night
        hardware = HardwareCoordinator(
            displayController: displayController,
            keyboardController: keyboardController
        )
        recovery = KeyboardAutoBrightnessRecovery(
            keyboardController: keyboardController,
            defaults: defaults
        )
        launchAtLogin = LaunchAtLoginController(store: store)
    }

    func start() {
        switch recovery.recoverIfNeeded() {
        case .failed:
            detailMessage = "Could not restore keyboard auto-brightness"
        case .keyboardUnavailable:
            detailMessage = "Keyboard auto-brightness recovery is pending"
        case .nothingToDo, .succeeded:
            break
        }

        // This only registers the login item. It intentionally never applies
        // a brightness preset during launch.
        launchAtLogin.syncOnLaunch()
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in
            self?.poll()
        }
    }

    func handlePrimaryClick() {
        hardware.poll { [weak self] result in
            guard let self else { return }
            self.latestSnapshot = result.snapshot
            let actualState = StateEngine.infer(
                snapshot: result.snapshot,
                day: self.day,
                night: self.night,
                lastAppliedMode: self.store.lastAppliedMode
            )
            self.state = actualState
            let target = StateEngine.modeForClick(
                inferredState: actualState,
                snapshot: result.snapshot,
                day: self.day,
                night: self.night,
                lastAppliedMode: self.store.lastAppliedMode
            )
            self.apply(target)
        }
    }

    func apply(_ mode: DayNightMode) {
        guard mode == .day || mode == .night else { return }
        let recoveryResult = recovery.prepareForControl()
        if recoveryResult == .failed {
            detailMessage = "Keyboard auto-brightness could not be disabled"
        } else if recoveryResult == .keyboardUnavailable {
            detailMessage = "Keyboard unavailable; applying displays only"
        }

        applicationSequence &+= 1
        let sequence = applicationSequence
        applyingMode = mode
        store.lastAppliedMode = mode
        let preset = preset(for: mode)

        hardware.transition(to: preset) { [weak self] report in
            guard let self, sequence == self.applicationSequence else { return }
            self.applyingMode = nil
            if !report.failedDisplayIDs.isEmpty || report.keyboardFailed {
                var failures: [String] = []
                if !report.failedDisplayIDs.isEmpty {
                    failures.append(
                        "\(report.failedDisplayIDs.count) display control failed"
                    )
                }
                if report.keyboardFailed {
                    failures.append("keyboard control failed")
                }
                self.detailMessage = failures.joined(separator: " · ")
            } else if !report.cancelled {
                self.detailMessage = String(
                    format: "%@ applied in %.2f s",
                    mode == .day ? "Day" : "Night",
                    report.elapsed
                )
            }
            self.poll()
        }
    }

    func setScreenValue(_ value: Double, for mode: DayNightMode) {
        let shouldPreview = LivePreviewPolicy.shouldPreview(
            editedMode: mode,
            inferredState: state,
            applyingMode: applyingMode
        )
        updatePreset(mode) { $0.screen = value }
        if shouldPreview { apply(mode) }
    }

    func setKeyboardValue(_ value: Double, for mode: DayNightMode) {
        let shouldPreview = LivePreviewPolicy.shouldPreview(
            editedMode: mode,
            inferredState: state,
            applyingMode: applyingMode
        )
        updatePreset(mode) { $0.keyboard = value }
        if shouldPreview { apply(mode) }
    }

    func prepareToQuit() {
        pollTimer?.invalidate()
        pollTimer = nil
        hardware.cancelTransitions()
        let result = recovery.restoreOnQuit()
        if result == .failed || result == .keyboardUnavailable {
            detailMessage = "Keyboard auto-brightness recovery remains pending"
        }
    }

    private func updatePreset(
        _ mode: DayNightMode,
        mutation: (inout BrightnessPreset) -> Void
    ) {
        switch mode {
        case .day:
            var updated = day
            mutation(&updated)
            updated = BrightnessPreset(
                screen: updated.screen, keyboard: updated.keyboard
            )
            day = updated
            store.day = updated
        case .night:
            var updated = night
            mutation(&updated)
            updated = BrightnessPreset(
                screen: updated.screen, keyboard: updated.keyboard
            )
            night = updated
            store.night = updated
        case .custom:
            break
        }
    }

    private func preset(for mode: DayNightMode) -> BrightnessPreset {
        mode == .day ? day : night
    }

    private func poll() {
        guard !pollInFlight else { return }
        pollInFlight = true
        let stateBeforePoll = state
        hardware.poll { [weak self] result in
            guard let self else { return }
            self.pollInFlight = false
            self.latestSnapshot = result.snapshot
            self.hardwareSummary = self.summary(for: result.snapshot)

            if !result.newlyAvailableDisplayIDs.isEmpty,
               stateBeforePoll == .day || stateBeforePoll == .night {
                let mode = stateBeforePoll
                self.hardware.transition(
                    to: self.preset(for: mode),
                    selectedDisplayIDs: result.newlyAvailableDisplayIDs,
                    includeKeyboard: false
                ) { [weak self] report in
                    if !report.failedDisplayIDs.isEmpty {
                        self?.detailMessage = "Reconnected display control failed"
                    }
                    self?.poll()
                }
                return
            }

            self.state = StateEngine.infer(
                snapshot: result.snapshot,
                day: self.day,
                night: self.night,
                lastAppliedMode: self.store.lastAppliedMode
            )
        }
    }

    private func summary(for snapshot: HardwareSnapshot) -> String {
        let displayCount = snapshot.displayValues.count
        let displays = displayCount == 1 ? "1 display" : "\(displayCount) displays"
        let keyboard = snapshot.keyboardValue == nil
            ? "keyboard unavailable"
            : "keyboard available"
        return "\(displays) · \(keyboard)"
    }
}
