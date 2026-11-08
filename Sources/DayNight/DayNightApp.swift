import AppKit
import Combine
import DayNightCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = DayNightViewModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var stateObservation: AnyCancellable?
    private var didPrepareForTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        model.start()

        stateObservation = model.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateStatusIcon(for: state)
            }
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        prepareForTerminationIfNeeded()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        prepareForTerminationIfNeeded()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        updateStatusIcon(for: model.state)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 332, height: 370)
        popover.contentViewController = NSHostingController(
            rootView: SettingsView(model: model)
        )
    }

    @objc
    private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApplication.shared.currentEvent
        let isContextClick = event?.type == .rightMouseUp ||
            (event?.type == .leftMouseUp &&
             event?.modifierFlags.contains(.control) == true)

        if isContextClick {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(
                    relativeTo: sender.bounds,
                    of: sender,
                    preferredEdge: .minY
                )
                positionPopoverBelowStatusItem(sender)
            }
        } else {
            popover.performClose(nil)
            model.handlePrimaryClick()
        }
    }

    private func positionPopoverBelowStatusItem(_ sender: NSStatusBarButton) {
        // NSPopover can choose the display above a vertically stacked screen.
        // Pin its window to the screen containing the clicked status item.
        DispatchQueue.main.async { [weak self, weak sender] in
            guard let self,
                  let sender,
                  let statusWindow = sender.window,
                  let screen = statusWindow.screen,
                  let popoverWindow = self.popover.contentViewController?
                    .view.window
            else {
                return
            }

            let anchorInWindow = sender.convert(sender.bounds, to: nil)
            let anchor = statusWindow.convertToScreen(anchorInWindow)
            let frame = popoverWindow.frame
            let safeFrame = screen.visibleFrame.insetBy(dx: 6, dy: 6)

            let centeredX = anchor.midX - frame.width / 2
            let maximumX = max(safeFrame.minX, safeFrame.maxX - frame.width)
            let x = min(max(centeredX, safeFrame.minX), maximumX)

            let belowMenuBar = anchor.minY - frame.height - 4
            let maximumY = max(safeFrame.minY, safeFrame.maxY - frame.height)
            let y = min(max(belowMenuBar, safeFrame.minY), maximumY)
            popoverWindow.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func updateStatusIcon(for state: DayNightMode) {
        guard let button = statusItem?.button else { return }
        let symbol: String
        let label: String
        switch state {
        case .day:
            symbol = "sun.max.fill"
            label = "DayNight: Day"
        case .night:
            symbol = "moon.fill"
            label = "DayNight: Night"
        case .custom:
            symbol = "slider.horizontal.3"
            label = "DayNight: Custom"
        }

        let configuration = NSImage.SymbolConfiguration(
            pointSize: 14, weight: .medium
        )
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: label
        )?.withSymbolConfiguration(configuration)
        button.image?.isTemplate = true
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    private func prepareForTerminationIfNeeded() {
        guard !didPrepareForTermination else { return }
        didPrepareForTermination = true
        model.prepareToQuit()
    }
}

@main
enum DayNightMain {
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
