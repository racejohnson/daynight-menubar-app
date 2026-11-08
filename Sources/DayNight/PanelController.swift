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
        panel.contentView = glass

        content.onSizeChange = { [weak self] in self?.fit() }
        panel.onCancel = { [weak self] in self?.close() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(below button: NSStatusBarButton) {
        isVisible ? close() : show(below: button)
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
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        startMonitoring()
        onVisibilityChange?(true)
    }

    func close() {
        guard panel.isVisible else { return }
        stopMonitoring()
        panel.orderOut(nil)
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
        panel.invalidateShadow()
    }

    private func startMonitoring() {
        // Global monitors only see clicks in other apps, so clicks on our own
        // status item still reach `toggle` and `clicked`.
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
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "q" {
            NSApp.terminate(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
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
