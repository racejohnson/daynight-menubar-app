import Foundation

public enum StateEngine {
    public static let defaultTolerance = 0.02

    public static func infer(
        snapshot: HardwareSnapshot,
        day: BrightnessPreset,
        night: BrightnessPreset,
        tolerance: Double = defaultTolerance,
        lastAppliedMode: DayNightMode? = nil
    ) -> DayNightMode {
        guard snapshot.availableChannelCount > 0 else { return .custom }

        let dayMatches = matches(
            snapshot: snapshot, preset: day, tolerance: tolerance
        )
        let nightMatches = matches(
            snapshot: snapshot, preset: night, tolerance: tolerance
        )

        switch (dayMatches, nightMatches) {
        case (true, false):
            return .day
        case (false, true):
            return .night
        case (true, true):
            if lastAppliedMode == .night { return .night }
            return .day
        case (false, false):
            return .custom
        }
    }

    public static func matches(
        snapshot: HardwareSnapshot,
        preset: BrightnessPreset,
        tolerance: Double = defaultTolerance
    ) -> Bool {
        guard snapshot.availableChannelCount > 0 else { return false }
        let permittedDifference = max(0, tolerance)

        let displaysMatch = snapshot.displayValues.values.allSatisfy {
            abs($0 - preset.screen) <= permittedDifference
        }
        let keyboardMatches = snapshot.keyboardValue.map {
            abs($0 - preset.keyboard) <= permittedDifference
        } ?? true
        return displaysMatch && keyboardMatches
    }

    public static func modeForClick(
        inferredState: DayNightMode,
        snapshot: HardwareSnapshot,
        day: BrightnessPreset,
        night: BrightnessPreset,
        lastAppliedMode: DayNightMode?
    ) -> DayNightMode {
        switch inferredState {
        case .day:
            return .night
        case .night:
            return .day
        case .custom:
            let dayDistance = distance(from: snapshot, to: day)
            let nightDistance = distance(from: snapshot, to: night)
            if abs(dayDistance - nightDistance) <= 0.000_000_1 {
                if let lastAppliedMode,
                   lastAppliedMode == .day || lastAppliedMode == .night {
                    return lastAppliedMode.opposite
                }
                return .night
            }
            return dayDistance < nightDistance ? .night : .day
        }
    }

    public static func distance(
        from snapshot: HardwareSnapshot,
        to preset: BrightnessPreset
    ) -> Double {
        let screenDistance = snapshot.displayValues.values.reduce(0) {
            $0 + abs($1 - preset.screen)
        }
        let keyboardDistance = snapshot.keyboardValue.map {
            abs($0 - preset.keyboard)
        } ?? 0
        return screenDistance + keyboardDistance
    }
}

public enum LivePreviewPolicy {
    public static func shouldPreview(
        editedMode: DayNightMode,
        inferredState: DayNightMode,
        applyingMode: DayNightMode?
    ) -> Bool {
        guard editedMode == .day || editedMode == .night else { return false }
        return inferredState == editedMode || applyingMode == editedMode
    }
}
