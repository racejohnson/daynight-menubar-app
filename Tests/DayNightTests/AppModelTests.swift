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

    /// Polls until `condition` holds, for at most three seconds, and says
    /// whether it did, so a wait that times out fails its test.
    func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    @Test func clickSwapsDayAndAway() async {
        let displays = MockDisplays([1: 1, 2: 1])
        let keyboard = MockKeyboard(1)
        let model = await model(displays, keyboard)

        model.toggle()
        #expect(await waitUntil { lastApplied == "away" && model.fadingTo == nil })
        #expect(model.state == .away)
        #expect(displays.values == [1: 0.5, 2: 0.5])

        model.toggle()
        #expect(await waitUntil { lastApplied == "day" && model.fadingTo == nil })
        #expect(model.state == .day)
        #expect(displays.values == [1: 1, 2: 1])
    }

    @Test func optionClickGoesToNightAndAClickFromNightGoesToDay() async {
        let displays = MockDisplays([1: 1])
        let model = await model(displays, MockKeyboard(1))

        model.toggle(alternate: true)
        #expect(await waitUntil { lastApplied == "night" && model.fadingTo == nil })
        #expect(model.state == .night)
        #expect(displays.values == [1: 0.2])

        model.toggle()
        #expect(await waitUntil { lastApplied == "day" && model.fadingTo == nil })
        #expect(model.state == .day)
    }

    @Test func twoQuickClicksEndOppositeTheFirstTarget() async {
        let displays = MockDisplays([1: 1, 2: 1])
        let model = await model(displays, MockKeyboard(1))
        #expect(model.state == .day)

        model.toggle()
        model.toggle()
        #expect(await waitUntil { lastApplied == "day" && model.fadingTo == nil })

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
        #expect(await waitUntil { !displays.writes.isEmpty })
        model.setScreen(0.3)
        #expect(await waitUntil { displays.values[1] == 0.3 })
        model.setScreen(0.25)
        model.endLevelEdit()
        #expect(model.displayedState == .night)

        #expect(await waitUntil { displays.values[1] == 0.25 })
        #expect(model.state == .night)
        #expect(model.fadingTo == nil)
        #expect(model.preset(for: .night).screen == 0.25)
        #expect(model.preset(for: .day) == .defaultDay)
    }

    @Test func aFailedWriteIsReported() async {
        let displays = MockDisplays([1: 1, 2: 1], failing: [1])
        let model = await model(displays, MockKeyboard(1))
        #expect(model.problem == nil)

        model.apply(.night)
        #expect(await waitUntil { model.fadingTo == nil })

        #expect(model.problem == "Couldn’t set the brightness of one display.")
    }

    // MARK: The panel's two sliders

    @Test func theSlidersShowTheModeThatIsOn() async {
        let model = await model(MockDisplays([1: 0.5]), MockKeyboard(0.5))
        #expect(model.state == .away)
        #expect(model.levels == BrightnessPreset(screen: 0.5, keyboard: 0.5))
    }

    @Test func draggingASliderSetsTheModeThatIsOn() async {
        let displays = MockDisplays([1: 1, 2: 1])
        let keyboard = MockKeyboard(1)
        let model = await model(displays, keyboard)

        model.setScreen(0.8)
        model.endLevelEdit()
        #expect(await waitUntil { displays.values == [1: 0.8, 2: 0.8] })

        #expect(model.state == .day)
        #expect(model.preset(for: .day) == BrightnessPreset(screen: 0.8, keyboard: 1))
        #expect(keyboard.level == 1)
    }

    /// Day and Away read the same here, and the tie goes to the mode being
    /// set because a live edit counts as applying it.
    @Test func aDragOntoAnotherModesLevelsStaysWithTheModeBeingSet() async {
        let displays = MockDisplays([1: 1])
        let keyboard = MockKeyboard(0.5)
        isolated.defaults.set(0.5, forKey: "preset.day.keyboard")
        let model = await model(displays, keyboard)
        #expect(model.state == .day)

        // Day now reads exactly as Away does.
        model.setScreen(0.5)
        #expect(await waitUntil { displays.values[1] == 0.5 })
        await model.refresh()
        #expect(model.state == .day)

        model.setScreen(0.3)
        model.endLevelEdit()
        #expect(await waitUntil { displays.values[1] == 0.3 })
        #expect(model.state == .day)
        #expect(model.preset(for: .day).screen == 0.3)
        #expect(model.preset(for: .away) == .defaultAway)
    }

    /// One display refuses its writes, so the hardware stops reading as Day
    /// partway through the drag. Only the drag's hold on its target keeps
    /// the rest of the drag setting Day.
    @Test func aDragKeepsItsModeWhenTheHardwareStopsMatchingIt() async {
        let displays = MockDisplays([1: 1, 2: 1], failing: [2])
        let model = await model(displays, MockKeyboard(1))
        #expect(model.state == .day)

        model.setScreen(0.6)
        #expect(await waitUntil { displays.values[1] == 0.6 })
        await model.refresh()
        #expect(model.state == .day, "the reading is no mode, but the drag is still going")

        model.setScreen(0.4)
        #expect(await waitUntil { displays.values[1] == 0.4 })
        #expect(model.preset(for: .day).screen == 0.4)
        #expect(model.preset(for: .away) == .defaultAway)

        model.endLevelEdit()
        #expect(await waitUntil { model.state == .custom })
    }

    @Test func aDragCutOffByThePanelClosingStillEnds() async {
        let displays = MockDisplays([1: 0.8])
        let keyboard = MockKeyboard(0.5)
        let model = await model(displays, keyboard)
        #expect(model.state == .custom)

        // The slider never reports the end of this drag.
        model.setScreen(0.7)
        model.panelDidClose()
        #expect(await waitUntil { displays.values[1] == 0.7 && model.customLevels == nil })

        // The brightness keys are followed again.
        displays.state.withLock { $0.values[1] = 0.5 }
        await model.refresh()
        #expect(model.state == .away)
        #expect(model.levels == .defaultAway)
    }

    @Test func aNewDragKeepsItsLevelsWhileTheLastOneIsStillEnding() async {
        let displays = MockDisplays([1: 0.8])
        let model = await model(displays, MockKeyboard(0.35))

        model.setScreen(0.7)
        model.endLevelEdit()
        model.setScreen(0.3)
        #expect(await waitUntil { displays.values[1] == 0.3 })
        // Let the first drag's ending run to its finish.
        try? await Task.sleep(for: .milliseconds(100))

        #expect(model.levels.screen == 0.3)
        #expect(model.state == .custom)
    }

    @Test func withNoModeOnTheSlidersShowTheBrightnessAsItIs() async {
        let model = await model(MockDisplays([1: 0.8, 2: 0.6]), MockKeyboard(0.35))
        #expect(model.state == .custom)
        #expect(abs(model.levels.screen - 0.7) < 1e-9)
        #expect(model.levels.keyboard == 0.35)
    }

    @Test func withNoModeOnADragSetsTheBrightnessAndNoMode() async {
        let displays = MockDisplays([1: 0.8, 2: 0.6])
        let keyboard = MockKeyboard(0.35)
        let model = await model(displays, keyboard)

        model.setScreen(0.7)
        #expect(await waitUntil { displays.values == [1: 0.7, 2: 0.7] })

        #expect(model.state == .custom)
        #expect(model.levels.screen == 0.7)
        #expect(model.presets == Presets())
        #expect(keyboard.level == 0.35)
        #expect(keyboard.autoBrightness, "a drag on Screens leaves the keyboard alone")
    }

    @Test func withNoModeOnADragThroughAModesLevelsStaysCustomUntilItEnds() async {
        let displays = MockDisplays([1: 0.8])
        let keyboard = MockKeyboard(0.5)
        let model = await model(displays, keyboard)
        #expect(model.state == .custom)

        model.setScreen(0.5)
        #expect(await waitUntil { displays.values[1] == 0.5 })
        await model.refresh()
        #expect(model.state == .custom, "Away's levels, but the drag is still going")

        model.endLevelEdit()
        #expect(await waitUntil { model.state == .away })
        #expect(model.state == .away)
        #expect(model.presets == Presets())
    }

    @Test func withNoModeOnTheKeyboardSliderSetsOnlyTheKeyboard() async {
        let displays = MockDisplays([1: 0.8])
        let keyboard = MockKeyboard(0.35)
        let model = await model(displays, keyboard)

        model.setKeyboard(0.6)
        model.endLevelEdit()
        #expect(await waitUntil { keyboard.level == 0.6 })

        #expect(displays.writes.isEmpty)
        #expect(model.state == .custom)
    }

    @Test func withNoModeOnAndNoKeyboardThereIsNothingToSet() async {
        let model = await model(MockDisplays([1: 0.8]), MockKeyboard(nil))
        #expect(model.state == .custom)
        #expect(model.canSetScreen)
        #expect(!model.canSetKeyboard)
    }

    // MARK: Nothing to set

    @Test func withNoDisplayOrKeyboardLightAClickDoesNothingAndThePanelSaysWhy() async {
        let model = await model(MockDisplays([:]), MockKeyboard(nil))
        #expect(model.problem == "DayNight can’t set the brightness of these screens. It works with built-in and Apple displays.")
        #expect(model.hardwareSummary == "no displays · no keyboard light")

        model.toggle()
        model.apply(.night)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(model.fadingTo == nil)
        #expect(model.state == .custom)
        #expect(lastApplied == nil)
    }

    @Test func theFooterCountsWhatCanBeSet() async {
        let model = await model(MockDisplays([1: 1]), MockKeyboard(1))
        #expect(model.hardwareSummary == "1 display · keyboard light")
        #expect(model.problem == nil)
    }
}
