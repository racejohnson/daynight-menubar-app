import DayNightCore
import Testing

struct StateEngineTests {
    let presets = Presets()

    @Test func everyChannelMustBeWithinTolerance() {
        let nearDay = HardwareSnapshot(displays: [1: 0.981, 2: 1], keyboard: 0.99)
        #expect(StateEngine.infer(nearDay, presets: presets) == .day)

        let outside = HardwareSnapshot(displays: [1: 0.979, 2: 1], keyboard: 1)
        #expect(StateEngine.infer(outside, presets: presets) == .custom)

        let nearDim = HardwareSnapshot(displays: [1: 0.5, 2: 0.519], keyboard: 0.481)
        #expect(StateEngine.infer(nearDim, presets: presets) == .dim)

        let nearNight = HardwareSnapshot(displays: [1: 0.2, 2: 0.219], keyboard: 0.081)
        #expect(StateEngine.infer(nearNight, presets: presets) == .night)

        let keyboardOff = HardwareSnapshot(displays: [1: 0.2, 2: 0.2], keyboard: 0.5)
        #expect(StateEngine.infer(keyboardOff, presets: presets) == .custom)
    }

    @Test func missingChannelsAreIgnoredButNoChannelsIsCustom() {
        let displaysOnly = HardwareSnapshot(displays: [1: 1])
        #expect(StateEngine.infer(displaysOnly, presets: presets) == .day)
        #expect(StateEngine.infer(HardwareSnapshot(), presets: presets) == .custom)
    }

    @Test func matchingSeveralPresetsResolvesToLastAppliedOrTheBrightest() {
        let same = BrightnessPreset(screen: 0.5, keyboard: 0.5)
        let all = Presets(day: same, dim: same, night: same)
        let reading = HardwareSnapshot(displays: [1: 0.5], keyboard: 0.5)
        #expect(StateEngine.infer(reading, presets: all) == .day)
        #expect(StateEngine.infer(reading, presets: all, lastApplied: .night) == .night)
        #expect(StateEngine.infer(reading, presets: all, lastApplied: .dim) == .dim)

        let dimAndNight = Presets(dim: same, night: same)
        #expect(StateEngine.infer(reading, presets: dimAndNight) == .dim)
        #expect(StateEngine.infer(reading, presets: dimAndNight, lastApplied: .day) == .dim)
        #expect(StateEngine.infer(reading, presets: dimAndNight, lastApplied: .night) == .night)
    }

    func click(_ state: BrightnessState, _ reading: HardwareSnapshot, last: Mode? = nil, alternate: Bool = false) -> Mode {
        StateEngine.clickTarget(
            from: state, snapshot: reading, presets: presets, lastApplied: last, alternate: alternate
        )
    }

    @Test func clickSwapsDayAndDimAndLeavesNightForDay() {
        let reading = HardwareSnapshot(displays: [1: 1], keyboard: 1)
        #expect(click(.day, reading) == .dim)
        #expect(click(.dim, reading) == .day)
        #expect(click(.night, reading, last: .night) == .day)
    }

    @Test func optionClickGoesToNightOrFromNightToDay() {
        let reading = HardwareSnapshot(displays: [1: 1], keyboard: 1)
        #expect(click(.day, reading, alternate: true) == .night)
        #expect(click(.dim, reading, alternate: true) == .night)
        #expect(click(.custom, reading, alternate: true) == .night)
        #expect(click(.night, reading, alternate: true) == .day)
    }

    @Test func clickFromCustomGoesToTheFartherOfDayAndDim() {
        let nearNight = HardwareSnapshot(displays: [1: 0.25, 2: 0.2], keyboard: 0.12)
        #expect(click(.custom, nearNight, last: .night) == .day)

        let nearDim = HardwareSnapshot(displays: [1: 0.45, 2: 0.6], keyboard: 0.5)
        #expect(click(.custom, nearDim, last: .dim) == .day)

        let nearDay = HardwareSnapshot(displays: [1: 0.9, 2: 1], keyboard: 0.95)
        #expect(click(.custom, nearDay, last: .day) == .dim)
    }

    @Test func clickFromAnExactTieGoesToDimUnlessDimWasLast() {
        let tie = HardwareSnapshot(displays: [1: 0.75], keyboard: 0.75)
        #expect(click(.custom, tie) == .dim)
        #expect(click(.custom, tie, last: .day) == .dim)
        #expect(click(.custom, tie, last: .night) == .dim)
        #expect(click(.custom, tie, last: .dim) == .day)
    }

    @Test func livePreviewOnlyForTheActiveOrIncomingMode() {
        #expect(StateEngine.shouldPreview(edited: .day, state: .day, fadingTo: nil))
        #expect(StateEngine.shouldPreview(edited: .night, state: .custom, fadingTo: .night))
        #expect(!StateEngine.shouldPreview(edited: .night, state: .custom, fadingTo: nil))
        #expect(!StateEngine.shouldPreview(edited: .day, state: .night, fadingTo: nil))
        #expect(StateEngine.shouldPreview(edited: .dim, state: .dim, fadingTo: nil))
        #expect(!StateEngine.shouldPreview(edited: .dim, state: .day, fadingTo: .night))
    }

    @Test func smoothstepEasing() {
        #expect(Easing.smoothstep(-1) == 0)
        #expect(abs(Easing.smoothstep(0.5) - 0.5) < 1e-9)
        #expect(Easing.smoothstep(2) == 1)
        #expect(Easing.smoothstep(0.25) < 0.25)
        #expect(abs(Easing.interpolate(from: 0.2, to: 1, progress: 0.5) - 0.6) < 1e-9)
    }

    @Test func presetsClamp() {
        var preset = BrightnessPreset(screen: 1.8, keyboard: -0.2)
        #expect(preset == BrightnessPreset(screen: 1, keyboard: 0))
        preset.screen = .nan
        #expect(preset.screen == 0)
        #expect(BrightnessPreset.clamp(.infinity) == 0)
    }
}
