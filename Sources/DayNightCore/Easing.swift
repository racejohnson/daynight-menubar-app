public enum Easing {
    /// Smoothstep: gentle start and finish, linear-feeling middle.
    public static func smoothstep(_ progress: Double) -> Double {
        let t = min(1, max(0, progress))
        return t * t * (3 - 2 * t)
    }

    public static func interpolate(from start: Double, to end: Double, progress: Double) -> Double {
        let t = smoothstep(progress)
        return BrightnessPreset.clamp(start * (1 - t) + end * t)
    }
}
