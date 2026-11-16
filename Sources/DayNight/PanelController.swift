import AppKit
import SwiftUI

/// A Control Center–style panel that hangs under the status item.
@MainActor
final class PanelController {
    var onVisibilityChange: ((Bool) -> Void)?

    private let model: AppModel
    private let panel = FloatingPanel()
    private let content: SizeReportingHostingView<PanelView>
    private var anchor: NSRect = .zero
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    /// When the panel last closed, in system uptime.
    private var closedAt: TimeInterval = 0

    private static let cornerRadius: CGFloat = 22
    private static let gapBelowMenuBar: CGFloat = 6
    private static let screenMargin: CGFloat = 8

    init(model: AppModel) {
        self.model = model
        content = SizeReportingHostingView(rootView: PanelView(model: model))
        content.sizingOptions = [.intrinsicContentSize]

        let glass = NSGlassEffectView()
        glass.cornerRadius = Self.cornerRadius
        glass.contentView = content
        panel.contentView = RoundedClipView(content: glass, cornerRadius: Self.cornerRadius)

        content.onSizeChange = { [weak self] in self?.fit() }
        panel.onCancel = { [weak self] in self?.close() }
    }

    var isVisible: Bool { panel.isVisible }

    /// A click on the status item while the panel is open closes it. On
    /// macOS 26 and later that click can also reach the outside-click monitor,
    /// which closes the panel a moment before this runs; without the check the
    /// same click would then open it again.
    func toggle(below button: NSStatusBarButton) {
        if isVisible {
            close()
        } else if ProcessInfo.processInfo.systemUptime - closedAt > 0.25 {
            show(below: button)
        }
    }

    /// For a plain click on the status item: closes the panel if it is open,
    /// and says whether this click was a dismissal. That includes a click the
    /// outside-click monitor has just closed the panel for (see `toggle`).
    func dismiss() -> Bool {
        if isVisible {
            close()
            return true
        }
        return ProcessInfo.processInfo.systemUptime - closedAt <= 0.25
    }

    func show(below button: NSStatusBarButton) {
        guard let window = button.window, let screen = window.screen else { return }
        anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        self.screen = screen
        model.panelDidOpen()
        fit()

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        // Nothing starts out focused: otherwise the first row, or the one
        // clicked last time, opens looking hovered. Tab still moves in.
        panel.makeFirstResponder(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        refreshShadow()
        startMonitoring()
        onVisibilityChange?(true)
    }

    func close() {
        guard panel.isVisible else { return }
        stopMonitoring()
        panel.orderOut(nil)
        closedAt = ProcessInfo.processInfo.systemUptime
        model.panelDidClose()
        onVisibilityChange?(false)
    }

    /// Sizes the panel to its content, centred under the status item and kept
    /// inside the visible frame of that item's screen.
    private func fit() {
        guard let screen else { return }
        let size = content.fittingSize
        let visible = screen.visibleFrame
        let x = min(
            max(anchor.midX - size.width / 2, visible.minX + Self.screenMargin),
            visible.maxX - Self.screenMargin - size.width
        )
        let top = min(anchor.minY, visible.maxY) - Self.gapBelowMenuBar
        let frame = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
        refreshShadow()
    }

    /// The window server traces the shadow and edge from what the window has
    /// drawn, so recompute it once the glass has rendered at its new size.
    private func refreshShadow() {
        DispatchQueue.main.async { [panel] in panel.invalidateShadow() }
    }

    private func startMonitoring() {
        // Closes the panel on a click anywhere outside this app. A click on our
        // own status item may or may not arrive here; `toggle` handles both.
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in MainActor.assumeIsolated { self?.close() } }
        ) {
            monitors.append(monitor)
        }
        observe(NSApplication.didResignActiveNotification, on: .default)
        observe(NSWorkspace.didActivateApplicationNotification, on: NSWorkspace.shared.notificationCenter)
        // A display change can leave the anchor on a screen that moved or is gone.
        observe(NSApplication.didChangeScreenParametersNotification, on: .default)
    }

    private func stopMonitoring() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let isSelf = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            MainActor.assumeIsolated {
                if !isSelf { self?.close() }
            }
        }
        observers.append((center, observer))
    }
}

/// A borderless panel that takes key focus (for Esc, ⌘Q and the sliders)
/// without activating the app.
private final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Caps Lock is a modifier flag too, and must not stop ⌘Q.
        if event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Clips the window to the panel's rounded shape, so its corners are truly
/// transparent and the window's shadow and edge follow the curve.
private final class RoundedClipView: NSView {
    init(content: NSView, cornerRadius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Reports SwiftUI content-size changes so the panel can refit while open.
private final class SizeReportingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (@MainActor () -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        // Refit after the current layout pass, not in the middle of it.
        Task { [weak self] in self?.onSizeChange?() }
    }
}
