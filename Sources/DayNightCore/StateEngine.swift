/// Pure rules that turn hardware readings into a state and a click into a target.
public enum StateEngine {
    public static let tolerance = 0.02

    /// Day or Night when every available channel is within tolerance of that
    /// preset; a reading that matches both resolves to the last applied mode.
    public static func infer(
        _ snapshot: HardwareSnapshot,
        day: BrightnessPreset,
        night: BrightnessPreset,
        lastApplied: Mode? = nil,
        tolerance: Double = tolerance
    ) -> BrightnessState {
        switch (
            matches(snapshot, day, tolerance: tolerance),
            matches(snapshot, night, tolerance: tolerance)
        ) {
        case (true, false): .day
        case (false, true): .night
        case (true, true): lastApplied == .night ? .night : .day
        case (false, false): .custom
        }
    }

    public static func matches(
        _ snapshot: HardwareSnapshot,
        _ preset: BrightnessPreset,
        tolerance: Double = tolerance
    ) -> Bool {
        guard snapshot.channelCount > 0 else { return false }
        let limit = max(0, tolerance)
        return snapshot.displays.values.allSatisfy { abs($0 - preset.screen) <= limit }
            && snapshot.keyboard.map { abs($0 - preset.keyboard) <= limit } ?? true
    }

    /// The mode a primary click should apply. From Custom it goes to the preset
    /// farther from the current reading (the opposite of the nearest one); an
    /// exact tie flips the last applied mode, or goes to Night.
    public static func clickTarget(
        from state: BrightnessState,
        snapshot: HardwareSnapshot,
        day: BrightnessPreset,
        night: BrightnessPreset,
        lastApplied: Mode?
    ) -> Mode {
        if let mode = state.mode { return mode.opposite }
        let toDay = distance(snapshot, day)
        let toNight = distance(snapshot, night)
        if abs(toDay - toNight) <= 1e-7 {
            return lastApplied?.opposite ?? .night
        }
        return toDay < toNight ? .night : .day
    }

    /// Sum of absolute differences across every available channel.
    public static func distance(_ snapshot: HardwareSnapshot, _ preset: BrightnessPreset) -> Double {
        snapshot.displays.values.reduce(0) { $0 + abs($1 - preset.screen) }
            + (snapshot.keyboard.map { abs($0 - preset.keyboard) } ?? 0)
    }

    /// Editing a preset previews it live only while it is (or is becoming) the active one.
    public static func shouldPreview(edited: Mode, state: BrightnessState, fadingTo: Mode?) -> Bool {
        state.mode == edited || fadingTo == edited
    }
}
