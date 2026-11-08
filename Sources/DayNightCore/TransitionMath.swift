import Foundation

public enum TransitionMath {
    public static func easedProgress(_ progress: Double) -> Double {
        let value = min(1, max(0, progress))
        return value * value * (3 - 2 * value)
    }

    public static func interpolate(
        from start: Double,
        to target: Double,
        progress: Double
    ) -> Double {
        let eased = easedProgress(progress)
        return BrightnessPreset.clamp(start + (target - start) * eased)
    }

    public static func stepCount(
        duration: TimeInterval,
        framesPerSecond: Double = 30
    ) -> Int {
        max(1, Int(ceil(max(0, duration) * max(1, framesPerSecond))))
    }
}
