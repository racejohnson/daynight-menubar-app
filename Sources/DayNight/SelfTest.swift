import AppKit
import DayNightCore

/// `--selftest`: puts the real item in the menu bar and opens the real panel,
/// on a made-up Mac, and drives them with synthetic mouse events the way a
/// hand would. It checks the parts unit tests cannot reach: that clicks on
/// the item swap modes and open the panel, that a click on a row fades to it,
/// and that the sliders follow the pointer. The real brightness is never touched.
@MainActor
enum SelfTest {
    static func run(demo: Demo, panel: PanelController, button: NSStatusBarButton) {
        let model = demo.model
        Task {
            // Let the item take its place in the menu bar, and the model read the hardware.
            try? await Task.sleep(for: .milliseconds(1200))
            guard let bar = button.window else {
                print("selftest: FAIL · the item has no window")
                exit(1)
            }
            var failures = 0
            @MainActor func check(_ name: String, _ passed: Bool, _ detail: String) {
                print("selftest: \(passed ? "pass" : "FAIL") · \(name) · \(detail)")
                if !passed { failures += 1 }
            }
            @MainActor func settle() async {
                try? await Task.sleep(for: .milliseconds(150))
                for _ in 0..<40 where model.fadingTo != nil {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            let item = button.convert(button.bounds, to: nil)
            let at = NSPoint(x: item.midX, y: item.midY)

            // 1. The item: a click swaps Day and Away, Option-click goes to Night.
            check("starts in Day", model.state == .day, model.state.title)
            await click(bar, at)
            await settle()
            check("click from Day", model.state == .away && demo.displays.levels == [1: 0.5, 2: 0.5], "\(model.state.title), displays at \(demo.displays.levels.values.sorted())")
            await click(bar, at)
            await settle()
            check("click from Away", model.state == .day, model.state.title)
            await click(bar, at, modifiers: .option)
            await settle()
            check("Option-click", model.state == .night && demo.keyboard.level == 0.1, "\(model.state.title), keyboard at \(demo.keyboard.level)")
            await click(bar, at)
            await settle()
            check("click from Night", model.state == .day, model.state.title)

            // 2. Right-click opens the panel, and a second one closes it.
            await click(bar, at, right: true)
            try? await Task.sleep(for: .milliseconds(500))
            check("right-click opens the panel", panel.isVisible, panel.isVisible ? "open" : "closed")
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0 !== bar && $0 is NSPanel }) else {
                print("selftest: FAIL · the panel did not stay open (a click in another app closes it). Run it again and keep your hands off.")
                exit(1)
            }
            check("panel size", window.frame.width == 312, "\(Int(window.frame.width)) × \(Int(window.frame.height)) pt")

            // From the top of the panel: 10 pt padding, two 30 pt sliders 8 pt
            // apart, 6 pt, the heading, then 38 pt rows 1 pt apart.
            @MainActor func fromTop(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: window.frame.height - y) }
            let sliderLeft: CGFloat = 10, sliderWidth: CGFloat = 292
            let screens: CGFloat = 25, keyboard: CGFloat = 63
            @MainActor func row(_ index: Int) -> NSPoint { fromTop(150, 101 + CGFloat(index) * 39 + 19) }

            // 3. A click on a row fades to that mode.
            await click(window, row(2))
            await settle()
            check("click the Night row", model.state == .night && demo.displays.levels == [1: 0.2, 2: 0.2], "\(model.state.title), displays at \(demo.displays.levels.values.sorted())")

            // 4. With a mode on, a slider sets that mode and the brightness.
            await click(window, fromTop(sliderLeft + sliderWidth * 0.25, screens))
            await settle()
            check(
                "drag Screens in Night", abs(model.preset(for: .night).screen - 0.25) < 0.01 && model.state == .night,
                "Night’s screens are \(Int((model.preset(for: .night).screen * 100).rounded()))%, \(model.state.title) is on"
            )

            // 5. With no mode on, a slider sets the brightness and no mode.
            await demo.show(BrightnessPreset(screen: 0.72, keyboard: 0.35))
            check("brightness keys", model.state == .custom, model.state.title)
            let before = model.presets
            await click(window, fromTop(sliderLeft + sliderWidth * 0.6, keyboard))
            await settle()
            check(
                "drag Keyboard with no mode on", abs(demo.keyboard.level - 0.6) < 0.01 && model.state == .custom && model.presets == before,
                "keyboard at \(demo.keyboard.level), \(model.state.title), modes unchanged: \(model.presets == before)"
            )

            // 6. From Custom, a click closes the panel and goes to whichever of Day
            // and Away is the bigger change: Day, from screens at 72% and keys at 60%.
            await click(bar, at)
            await settle()
            check("click from Custom", model.state == .day && !panel.isVisible, "\(model.state.title), panel \(panel.isVisible ? "open" : "closed")")

            print("selftest: \(failures == 0 ? "all checks passed" : "\(failures) check(s) FAILED")")
            Demo.cleanUp()
            exit(failures == 0 ? 0 : 1)
        }
    }

    // MARK: Synthetic input

    private static func post(_ type: NSEvent.EventType, _ window: NSWindow, _ point: NSPoint, _ modifiers: NSEvent.ModifierFlags) async {
        let isUp = type == .leftMouseUp || type == .rightMouseUp
        if let event = NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: isUp ? 0 : 1
        ) { NSApp.postEvent(event, atStart: false) }
        try? await Task.sleep(for: .milliseconds(30))
    }

    /// `point` is in the window's own coordinates.
    private static func click(_ window: NSWindow, _ point: NSPoint, right: Bool = false, modifiers: NSEvent.ModifierFlags = []) async {
        await post(right ? .rightMouseDown : .leftMouseDown, window, point, modifiers)
        await post(right ? .rightMouseUp : .leftMouseUp, window, point, modifiers)
    }
}
