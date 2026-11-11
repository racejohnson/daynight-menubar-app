import AppKit
import DayNightCore
import Observation
import ServiceManagement

/// Everything the status item and the panel show, and every action they take.
@Observable
@MainActor
final class AppModel {
    /// What the hardware reads as, inferred after every refresh.
    private(set) var state: BrightnessState = .custom
    /// The mode a running fade is heading to.
    private(set) var fadingTo: Mode?
    private(set) var presets: Presets
    private(set) var displayCount = 0
    private(set) var hasKeyboard = false
    private(set) var controlProblem: String?
    /// The last attempt to restore auto-brightness left by an unclean quit.
    private(set) var leftoverRecovery: AutoBrightnessResult = .nothingToDo
    let launchAtLogin: LaunchAtLogin

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let hardware: BrightnessController
    @ObservationIgnored private var transitionID = 0
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var isShuttingDown = false
    @ObservationIgnored private var toggleTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPreview: BrightnessPreset?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    init(
        defaultsSuite: String? = nil,
        displays: any DisplayControlling = SystemDisplays(),
        keyboard: any KeyboardControlling = SystemKeyboard(),
        loginService: any LoginItemService = SMAppService.mainApp
    ) {
        settings = SettingsStore(defaults: defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard)
        hardware = BrightnessController(displays: displays, keyboard: keyboard, defaultsSuite: defaultsSuite)
        presets = settings.presets
        launchAtLogin = LaunchAtLogin(settings: settings, service: loginService)
    }

    // MARK: Derived

    /// The state to show: a fade already counts as its destination.
    var displayedState: BrightnessState {
        fadingTo.map(BrightnessState.init) ?? state
    }

    var hardwareSummary: String {
        let displays = switch displayCount {
        case 0: "No displays"
        case 1: "1 display"
        default: "\(displayCount) displays"
        }
        return "\(displays) · \(hasKeyboard ? "Keyboard" : "No keyboard")"
    }

    var problem: String? {
        if let controlProblem { return controlProblem }
        return switch leftoverRecovery {
        case .keyboardUnavailable: "Keyboard auto-brightness will be restored when the keyboard is back."
        case .failed: "Couldn’t restore keyboard auto-brightness."
        case .nothingToDo, .succeeded: nil
        }
    }

    func preset(for mode: Mode) -> BrightnessPreset {
        presets[mode]
    }

    // MARK: Lifecycle

    func start() {
        launchAtLogin.sync()
        Task {
            leftoverRecovery = await hardware.recoverLeftoverAutoBrightness()
            await refresh()
        }
        observe(NSApplication.didChangeScreenParametersNotification, on: .default)
        observe(NSWorkspace.didWakeNotification, on: NSWorkspace.shared.notificationCenter)
        observe(NSWorkspace.screensDidWakeNotification, on: NSWorkspace.shared.notificationCenter)
        // A light poll keeps the icon honest after brightness-key changes.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2), tolerance: .seconds(1))
                await self?.refresh()
            }
        }
    }

    /// Stops all writes and background work, then restores keyboard auto-brightness.
    func shutdown() async {
        isShuttingDown = true
        pollTask?.cancel()
        toggleTask?.cancel()
        previewTask?.cancel()
        pendingPreview = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        _ = await hardware.restoreAutoBrightness()
    }

    func panelDidOpen() {
        launchAtLogin.refresh()
        Task { await refresh() }
    }

    // MARK: Actions

    /// The menu-bar click: Day ⇄ Away, or to and from Night when `alternate`.
    /// A click during a fade counts from the fade's destination.
    func toggle(alternate: Bool = false) {
        guard !isShuttingDown else { return }
        let previous = toggleTask
        toggleTask = Task {
            await previous?.value
            let snapshot = await hardware.snapshot()
            if fadingTo == nil { state = infer(snapshot) }
            apply(StateEngine.clickTarget(
                from: displayedState, snapshot: snapshot, presets: presets,
                lastApplied: settings.lastApplied, alternate: alternate
            ))
        }
    }

    /// Fades every display and the keyboard to `mode`.
    func apply(_ mode: Mode) {
        guard !isShuttingDown else { return }
        transitionID += 1
        let id = transitionID
        pendingPreview = nil
        fadingTo = mode
        settings.lastApplied = mode
        Task {
            guard id == transitionID else { return }
            let report = await hardware.transition(to: preset(for: mode))
            guard id == transitionID else { return }
            if !report.cancelled { controlProblem = Self.problem(in: report) }
            state = BrightnessState(mode)
            fadingTo = nil
            await refresh()
        }
    }

    func setScreen(_ value: Double, for mode: Mode) {
        var preset = preset(for: mode)
        preset.screen = value
        update(preset, for: mode)
    }

    func setKeyboard(_ value: Double, for mode: Mode) {
        var preset = preset(for: mode)
        preset.keyboard = value
        update(preset, for: mode)
    }

    // MARK: Refresh

    /// Reads the hardware, brings newly connected displays into the current
    /// mode, and re-infers the state. Skipped while DayNight itself is writing.
    /// A failed auto-brightness recovery is retried only on events
    /// (`retryingRecovery`) or when the keyboard comes back, never on the poll.
    func refresh(retryingRecovery: Bool = false) async {
        guard !isRefreshing, !isWriting else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let reading = await hardware.read()
        var snapshot = reading.snapshot
        let keyboardAppeared = snapshot.keyboard != nil && !hasKeyboard
        displayCount = snapshot.displays.count
        hasKeyboard = snapshot.keyboard != nil

        if leftoverRecovery.isStillPending, hasKeyboard, retryingRecovery || keyboardAppeared {
            leftoverRecovery = await hardware.recoverLeftoverAutoBrightness()
        }

        if !reading.newDisplays.isEmpty, !isWriting,
           let mode = reconnectMode(snapshot, newDisplays: reading.newDisplays) {
            let report = await hardware.transition(
                to: preset(for: mode), displays: reading.newDisplays, includeKeyboard: false
            )
            if !report.failedDisplays.isEmpty {
                controlProblem = "Couldn’t set the brightness of a reconnected display."
            }
            snapshot = await hardware.snapshot()
        }

        guard !isWriting else { return }
        state = infer(snapshot)
    }

    // MARK: Private

    private var isWriting: Bool { fadingTo != nil || previewTask != nil }

    private func infer(_ snapshot: HardwareSnapshot) -> BrightnessState {
        StateEngine.infer(snapshot, presets: presets, lastApplied: settings.lastApplied)
    }

    /// The mode the already-known channels are in, which a newly connected
    /// display should join. Falls back to the last state when nothing else is left.
    private func reconnectMode(_ snapshot: HardwareSnapshot, newDisplays: Set<UInt32>) -> Mode? {
        var known = snapshot
        known.displays = known.displays.filter { !newDisplays.contains($0.key) }
        return known.channelCount > 0 ? infer(known).mode : state.mode
    }

    private func update(_ preset: BrightnessPreset, for mode: Mode) {
        let isLive = StateEngine.shouldPreview(edited: mode, state: state, fadingTo: fadingTo)
        presets[mode] = preset
        settings.setPreset(preset, for: mode)
        guard isLive, !isShuttingDown else { return }
        // A live edit writes the whole preset, so the hardware is in `mode`;
        // it also supersedes any fade still running.
        transitionID += 1
        fadingTo = nil
        state = BrightnessState(mode)
        preview(preset)
    }

    /// Applies slider edits instantly. Edits that arrive while a write is in
    /// flight collapse into one, so a fast drag never queues a backlog.
    private func preview(_ preset: BrightnessPreset) {
        pendingPreview = preset
        guard previewTask == nil else { return }
        previewTask = Task {
            while let next = pendingPreview {
                pendingPreview = nil
                let report = await hardware.transition(to: next, duration: .zero)
                if !report.cancelled { controlProblem = Self.problem(in: report) }
            }
            previewTask = nil
            await refresh()
        }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh(retryingRecovery: true) }
            }
        }
        observers.append((center, observer))
    }

    private static func problem(in report: TransitionReport) -> String? {
        if report.autoBrightnessFailed { return "Couldn’t turn off keyboard auto-brightness." }
        switch (report.failedDisplays.count, report.keyboardFailed) {
        case (0, false): return nil
        case (0, true): return "Couldn’t set the keyboard brightness."
        case (1, false): return "Couldn’t set the brightness of one display."
        case (let count, false): return "Couldn’t set the brightness of \(count) displays."
        case (_, true): return "Couldn’t set the brightness of the displays and keyboard."
        }
    }
}
