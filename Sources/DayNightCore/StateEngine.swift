/// Pure rules that turn hardware readings into a state and a click into a target.
public enum StateEngine {
    public static let tolerance = 0.02

    /// The mode whose preset every available channel is within tolerance of.
    /// A reading that matches several resolves to the last applied mode, or
    /// else to the brightest of them.
    public static func infer(
        _ snapshot: HardwareSnapshot,
        presets: Presets,
        lastApplied: Mode? = nil,
        tolerance: Double = tolerance
    ) -> BrightnessState {
        let matching = Mode.allCases.filter { matches(snapshot, presets[$0], tolerance: tolerance) }
        if let lastApplied, matching.contains(lastApplied) { return BrightnessState(lastApplied) }
        return matching.first.map(BrightnessState.init) ?? .custom
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

    /// The mode a click should apply.
    ///
    /// A plain click swaps Day and Dim, and leaves Night for Day. From Custom
    /// it goes to whichever of Day and Dim is farther from the current reading;
    /// an exact tie goes to Dim unless Dim was the last applied mode.
    ///
    /// An `alternate` (Option) click goes to Night, or from Night to Day.
    public static func clickTarget(
        from state: BrightnessState,
        snapshot: HardwareSnapshot,
        presets: Presets,
        lastApplied: Mode?,
        alternate: Bool = false
    ) -> Mode {
        if alternate { return state == .night ? .day : .night }
        switch state {
        case .day:
            return .dim
        case .dim, .night:
            return .day
        case .custom:
            let toDay = distance(snapshot, presets.day)
            let toDim = distance(snapshot, presets.dim)
            if abs(toDay - toDim) <= 1e-7 {
                return lastApplied == .dim ? .day : .dim
            }
            return toDay < toDim ? .dim : .day
        }
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
