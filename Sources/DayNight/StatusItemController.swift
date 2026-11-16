import AppKit
import DayNightCore
import Observation

/// The menu-bar capsule. Click swaps Day and Away; Option-click goes to
/// Night; right-click or Control-click opens the panel.
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
        Task { [weak self, model] in
            for await state in Observations({ model.displayedState }) {
                self?.show(state)
            }
        }
    }

    /// The capsule's button, for the self-test to click.
    var button: NSStatusBarButton? { item.button }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            panel.toggle(below: sender)
        } else {
            panel.close()
            model.toggle(alternate: event?.modifierFlags.contains(.option) == true)
        }
    }

    private func show(_ state: BrightnessState) {
        guard let button = item.button else { return }
        let label = "DayNight: \(state.title)"
        button.image = Glyphs.trio(state)
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }
}
