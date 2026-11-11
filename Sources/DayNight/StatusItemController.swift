import AppKit
import DayNightCore
import Observation

/// The menu-bar icon. Click swaps Day and Away; Option-click goes to Night;
/// right-click or Control-click opens the panel.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private let panel: PanelController

    init(model: AppModel, panel: PanelController) {
        self.model = model
        self.panel = panel
        super.init()

        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel.onVisibilityChange = { [weak button] isVisible in
            button?.highlight(isVisible)
        }
        Task { [weak self, model] in
            for await state in Observations({ model.displayedState }) {
                self?.show(state)
            }
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            panel.toggle(below: sender)
        } else {
            panel.close()
            model.toggle(alternate: event?.modifierFlags.contains(.option) == true)
        }
    }

    private func show(_ state: BrightnessState) {
        guard let button = item.button else { return }
        let label = "DayNight: \(state.title)"
        button.image = NSImage(systemSymbolName: state.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }
}
