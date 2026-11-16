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
    /// The last hardware reading: the levels to show when no mode is on.
    private(set) var reading = HardwareSnapshot()
    /// The levels being dragged while no mode is on. The hardware trails them.
    private(set) var customLevels: BrightnessPreset?
    private(set) var controlProblem: String?
    /// The last attempt to restore auto-brightness left by an unclean quit.
    private(set) var leftoverRecovery: AutoBrightnessResult = .nothingToDo
    let launchAtLogin: LaunchAtLogin

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let hardware: BrightnessController
    @ObservationIgnored private var transitionID = 0
    @ObservationIgnored private var isRefreshing = false
    /// False until the hardware has been read once, so nothing is concluded from the counts before then.
    @ObservationIgnored private var hasRead = false
    @ObservationIgnored private var isPanelOpen = false
    @ObservationIgnored private var isShuttingDown = false
    @ObservationIgnored private var toggleTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPreview: Write?
    /// What the panel's sliders are setting, held for the length of one drag
    /// so that passing another mode's levels cannot change the target.
    @ObservationIgnored private var editTarget: BrightnessState?
    @ObservationIgnored private var editID = 0
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
        case 0: "no displays"
        case 1: "1 display"
        default: "\(displayCount) displays"
        }
        // The keyboard's backlight, not the keyboard: every Mac has one of those.
        return "\(displays) · \(hasKeyboard ? "keyboard light" : "no keyboard light")"
    }

    /// Nothing here can be set: no built-in or Apple display, and no keyboard backlight.
    private var hasNothingToSet: Bool { hasRead && displayCount == 0 && !hasKeyboard }

    var problem: String? {
        if hasNothingToSet {
            return "DayNight can’t set the brightness of these screens. It works with built-in and Apple displays."
        }
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

    /// What the panel's two sliders show: the levels of the mode that is on,
    /// or else the brightness as it is.
    var levels: BrightnessPreset {
        if let mode = displayedState.mode { return presets[mode] }
        return customLevels ?? BrightnessPreset(screen: reading.averageScreen ?? 0, keyboard: reading.keyboard ?? 0)
    }

    /// With a mode on, a slider sets that mode even when its hardware is
    /// missing. With none on, there has to be something to set.
    var canSetScreen: Bool { displayedState.mode != nil || displayCount > 0 }
    var canSetKeyboard: Bool { displayedState.mode != nil || hasKeyboard }

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
        startPolling()
    }

    /// A light poll keeps the item honest after brightness-key changes. While
    /// the panel is open it runs faster, so the sliders follow the keys.
    private func startPolling() {
        pollTask?.cancel()
        let isFast = isPanelOpen
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                if isFast {
                    try? await Task.sleep(for: .milliseconds(300), tolerance: .milliseconds(100))
                } else {
                    try? await Task.sleep(for: .seconds(2), tolerance: .seconds(1))
                }
                guard !Task.isCancelled else { return }
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
        isPanelOpen = true
        Task { await refresh() }
        if pollTask != nil { startPolling() }
    }

    /// The panel can close in the middle of a drag (Esc, another app, a
    /// display change), and the slider then never hears that the drag ended.
    func panelDidClose() {
        isPanelOpen = false
        endLevelEdit()
        if pollTask != nil { startPolling() }
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
            // With nothing to set, a click would light a mode for the length
            // of a fade that changes nothing.
            guard snapshot.channelCount > 0 else { return }
            if fadingTo == nil { state = infer(snapshot) }
            apply(StateEngine.clickTarget(
                from: displayedState, snapshot: snapshot, presets: presets,
                lastApplied: settings.lastApplied, alternate: alternate
            ))
        }
    }

    /// Fades every display and the keyboard to `mode`.
    func apply(_ mode: Mode) {
        guard !isShuttingDown, !hasNothingToSet else { return }
        transitionID += 1
        let id = transitionID
        pendingPreview = nil
        editTarget = nil
        customLevels = nil
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

    /// The panel's Screens slider: sets the mode that is on, or with none on
    /// sets the displays and changes no mode.
    func setScreen(_ value: Double) {
        guard canSetScreen else { return }
        setLevel(screens: true, keyboard: false) { $0.screen = value }
    }

    /// The panel's Keyboard slider, on the same terms.
    func setKeyboard(_ value: Double) {
        guard canSetKeyboard else { return }
        setLevel(screens: false, keyboard: true) { $0.keyboard = value }
    }

    /// The drag is over: let the last write land, then read the hardware again.
    /// Levels left matching a mode now count as that mode.
    func endLevelEdit() {
        guard editTarget != nil else { return }
        let id = editID
        Task {
            await previewTask?.value
            // A newer drag ends itself.
            guard id == editID else { return }
            editTarget = nil
            await refresh()
            // A drag that began during that read owns the levels now.
            guard id == editID else { return }
            customLevels = nil
        }
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
        hasRead = true
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
        self.reading = snapshot
        state = editTarget ?? infer(snapshot)
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
        // A live edit writes the whole preset, on purpose: a drag on Screens
        // also asserts the mode's keyboard level, so the hardware is in `mode`.
        // It also supersedes any fade still running.
        transitionID += 1
        fadingTo = nil
        state = BrightnessState(mode)
        settings.lastApplied = mode
        preview(Write(preset: preset))
    }

    private func setLevel(screens: Bool, keyboard: Bool, _ change: (inout BrightnessPreset) -> Void) {
        guard !isShuttingDown else { return }
        editID += 1
        let target = editTarget ?? displayedState
        editTarget = target
        if let mode = target.mode {
            var preset = presets[mode]
            change(&preset)
            update(preset, for: mode)
        } else {
            // No mode is on: write only the channel being dragged, so a drag on
            // Screens leaves the keyboard, and its auto-brightness, alone.
            var levels = levels
            change(&levels)
            customLevels = levels
            preview(Write(preset: levels, screens: screens, keyboard: keyboard))
        }
    }

    /// One instant write, to every display, the keyboard, or both.
    private struct Write {
        var preset: BrightnessPreset
        var screens = true
        var keyboard = true
    }

    /// Applies slider edits instantly. Edits that arrive while a write is in
    /// flight collapse into one, so a fast drag never queues a backlog.
    private func preview(_ write: Write) {
        var write = write
        if let waiting = pendingPreview {
            write.screens = write.screens || waiting.screens
            write.keyboard = write.keyboard || waiting.keyboard
        }
        pendingPreview = write
        guard previewTask == nil else { return }
        previewTask = Task {
            while let next = pendingPreview {
                pendingPreview = nil
                let report = await hardware.transition(
                    to: next.preset, duration: .zero,
                    displays: next.screens ? nil : [], includeKeyboard: next.keyboard
                )
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
