@testable import DayNight
import DayNightCore
import Foundation
import ServiceManagement
import Testing

private struct FakeLoginItem: LoginItemService {
    var status: SMAppService.Status = .enabled
    func register() throws {}
    func unregister() throws {}
}

@MainActor
struct AppModelTests {
    let isolated = IsolatedDefaults()

    func model(_ displays: MockDisplays, _ keyboard: MockKeyboard) async -> AppModel {
        let model = AppModel(
            defaultsSuite: isolated.suite, displays: displays, keyboard: keyboard, loginService: FakeLoginItem()
        )
        await model.refresh()
        return model
    }

    var lastApplied: String? { isolated.defaults.string(forKey: "state.lastAppliedMode") }

    /// Polls until `condition` holds, for at most three seconds.
    func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func twoQuickClicksEndOppositeTheFirstTarget() async {
        let displays = MockDisplays([1: 1, 2: 1])
        let model = await model(displays, MockKeyboard(1))
        #expect(model.state == .day)

        model.toggle()
        model.toggle()
        await waitUntil { lastApplied == "day" && model.fadingTo == nil }

        #expect(model.state == .day)
        #expect(displays.values == [1: 1, 2: 1])
    }

    @Test func aReconnectedDisplayJoinsTheCurrentMode() async {
        let displays = MockDisplays([1: 1])
        let keyboard = MockKeyboard(1)
        let model = await model(displays, keyboard)

        displays.connect(7, at: 0.4)
        await model.refresh()

        #expect(displays.values == [1: 1, 7: 1])
        #expect(displays.writes.allSatisfy { $0.id == 7 }, "only the new display is touched")
        #expect(model.state == .day)
    }

    @Test func draggingTheIncomingPresetDuringAFadeKeepsPreviewing() async {
        let displays = MockDisplays([1: 1])
        let model = await model(displays, MockKeyboard(1))

        model.apply(.night)
        await waitUntil { !displays.writes.isEmpty }
        model.setScreen(0.3, for: .night)
        await waitUntil { displays.values[1] == 0.3 }
        model.setScreen(0.25, for: .night)
        #expect(model.displayedState == .night)

        await waitUntil { displays.values[1] == 0.25 }
        #expect(model.state == .night)
        #expect(model.fadingTo == nil)
    }

    @Test func aFailedWriteIsReported() async {
        let displays = MockDisplays([1: 1, 2: 1], failing: [1])
        let model = await model(displays, MockKeyboard(1))
        #expect(model.problem == nil)

        model.apply(.night)
        await waitUntil { model.fadingTo == nil }

        #expect(model.problem == "Couldn’t set the brightness of one display.")
    }
}
