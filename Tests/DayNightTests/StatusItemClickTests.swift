import AppKit
@testable import DayNight
import Testing

/// Which keys count as held for a click on the menu-bar item.
@MainActor
struct StatusItemClickTests {
    private func click(_ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    @Test func optionOnTheEventCounts() {
        #expect(StatusItemController.modifiers(of: click(.option), held: []).contains(.option))
    }

    /// macOS 27 hands the item an Option-click with no modifiers on the event.
    @Test func optionHeldOnTheKeyboardCounts() {
        #expect(StatusItemController.modifiers(of: click(), held: .option).contains(.option))
    }

    @Test func aPlainClickHasNone() {
        #expect(StatusItemController.modifiers(of: click(), held: []).isEmpty)
    }

    /// VoiceOver and Voice Control presses come without a click: always plain.
    @Test func anAccessibilityPressIgnoresHeldKeys() {
        #expect(StatusItemController.modifiers(of: nil, held: [.option, .control]).isEmpty)
    }
}
