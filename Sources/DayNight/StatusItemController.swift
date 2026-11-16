import AppKit
import DayNightCore
import Observation

/// The menu-bar capsule. Click swaps Day and Away; Option-click goes to
/// Night, or from Night to Day; right-click or Control-click opens the panel.
/// While the panel is open, a click only closes it.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: AppModel
    private let panel: PanelController

    init(model: AppModel, panel: PanelController) {
        self.model = model
        self.panel = panel
        super.init()

        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked(_:))
        // On mouse down, like the system's own menu-bar items, so the toggle
        // and the panel's outside-click monitor see the same moment.
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        panel.onVisibilityChange = { [weak button] isVisible in
            button?.highlight(isVisible)
        }
        // A press from VoiceOver or Voice Control is a plain click, so the
        // panel and Night, which the mouse reaches with a right-click and
        // Option, are offered as actions.
        button.setAccessibilityHelp("Switches between Day and Away. The actions show the panel or switch to a mode.")
        button.setAccessibilityCustomActions(
            [NSAccessibilityCustomAction(name: "Show Panel") { [weak self] in
                guard let self, let button = self.item.button else { return false }
                self.panel.show(below: button)
                return true
            }] + Mode.allCases.map { mode in
                NSAccessibilityCustomAction(name: mode.title) { [weak self] in
                    self?.model.apply(mode)
                    return self != nil
                }
            }
        )
        Task { [weak self, model] in
            for await state in Observations({ model.displayedState }) {
                self?.show(state)
            }
        }
    }

    /// The capsule's button, for the self-test to click.
    var button: NSStatusBarButton? { item.button }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        // Only a mouse click carries a button and modifiers worth reading. An
        // accessibility press leaves whatever event came before it in place.
        let click = NSApp.currentEvent.flatMap { [.leftMouseDown, .rightMouseDown].contains($0.type) ? $0 : nil }
        if click?.type == .rightMouseDown || click?.modifierFlags.contains(.control) == true {
            panel.toggle(below: sender)
        } else if !panel.dismiss() {
            model.toggle(alternate: click?.modifierFlags.contains(.option) == true)
        }
    }

    private func show(_ state: BrightnessState) {
        guard let button = item.button else { return }
        button.image = Glyphs.trio(state)
        // The panel is behind a right-click, which nothing else on screen says.
        let clicks = switch state {
        case .day: "Click for Away · Option-click for Night"
        case .away: "Click for Day · Option-click for Night"
        case .night: "Click or Option-click for Day"
        case .custom: "Click for Day or Away · Option-click for Night"
        }
        button.toolTip = "DayNight: \(state.title)\n\(clicks) · Right-click for the panel"
        button.setAccessibilityLabel("DayNight. \(state.title)")
    }
}
