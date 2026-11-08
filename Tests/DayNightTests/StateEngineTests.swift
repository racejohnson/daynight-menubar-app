import DayNightCore
import Testing

struct StateEngineTests {
    let day = BrightnessPreset.defaultDay
    let night = BrightnessPreset.defaultNight

    @Test func everyChannelMustBeWithinTolerance() {
        let nearDay = HardwareSnapshot(displays: [1: 0.981, 2: 1], keyboard: 0.99)
        #expect(StateEngine.infer(nearDay, day: day, night: night) == .day)

        let outside = HardwareSnapshot(displays: [1: 0.979, 2: 1], keyboard: 1)
        #expect(StateEngine.infer(outside, day: day, night: night) == .custom)

        let nearNight = HardwareSnapshot(displays: [1: 0.2, 2: 0.219], keyboard: 0.081)
        #expect(StateEngine.infer(nearNight, day: day, night: night) == .night)

        let keyboardOff = HardwareSnapshot(displays: [1: 0.2, 2: 0.2], keyboard: 0.5)
        #expect(StateEngine.infer(keyboardOff, day: day, night: night) == .custom)
    }

    @Test func missingChannelsAreIgnoredButNoChannelsIsCustom() {
        let displaysOnly = HardwareSnapshot(displays: [1: 1])
        #expect(StateEngine.infer(displaysOnly, day: day, night: night) == .day)
        #expect(StateEngine.infer(HardwareSnapshot(), day: day, night: night) == .custom)
    }

    @Test func matchingBothPresetsResolvesToLastApplied() {
        let same = BrightnessPreset(screen: 0.5, keyboard: 0.5)
        let reading = HardwareSnapshot(displays: [1: 0.5], keyboard: 0.5)
        #expect(StateEngine.infer(reading, day: same, night: same) == .day)
        #expect(StateEngine.infer(reading, day: same, night: same, lastApplied: .night) == .night)
        #expect(StateEngine.infer(reading, day: same, night: same, lastApplied: .day) == .day)
    }

    @Test func clickFromDayOrNightFlips() {
        let reading = HardwareSnapshot(displays: [1: 1], keyboard: 1)
        #expect(StateEngine.clickTarget(from: .day, snapshot: reading, day: day, night: night, lastApplied: nil) == .night)
        #expect(StateEngine.clickTarget(from: .night, snapshot: reading, day: day, night: night, lastApplied: .day) == .day)
    }

    @Test func clickFromCustomGoesToTheFartherPreset() {
        let nearNight = HardwareSnapshot(displays: [1: 0.25, 2: 0.2], keyboard: 0.12)
        #expect(StateEngine.clickTarget(from: .custom, snapshot: nearNight, day: day, night: night, lastApplied: .night) == .day)

        let nearDay = HardwareSnapshot(displays: [1: 0.9, 2: 1], keyboard: 0.95)
        #expect(StateEngine.clickTarget(from: .custom, snapshot: nearDay, day: day, night: night, lastApplied: .day) == .night)
    }

    @Test func clickFromAnExactTieFlipsLastAppliedOrGoesToNight() {
        let tie = HardwareSnapshot(displays: [1: 0.6], keyboard: 0.55)
        #expect(StateEngine.clickTarget(from: .custom, snapshot: tie, day: day, night: night, lastApplied: nil) == .night)
        #expect(StateEngine.clickTarget(from: .custom, snapshot: tie, day: day, night: night, lastApplied: .night) == .day)
        #expect(StateEngine.clickTarget(from: .custom, snapshot: tie, day: day, night: night, lastApplied: .day) == .night)
    }

    @Test func livePreviewOnlyForTheActiveOrIncomingMode() {
        #expect(StateEngine.shouldPreview(edited: .day, state: .day, fadingTo: nil))
        #expect(StateEngine.shouldPreview(edited: .night, state: .custom, fadingTo: .night))
        #expect(!StateEngine.shouldPreview(edited: .night, state: .custom, fadingTo: nil))
        #expect(!StateEngine.shouldPreview(edited: .day, state: .night, fadingTo: nil))
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
