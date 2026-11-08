import Foundation

public enum DayNightMode: String, Codable, CaseIterable, Equatable {
    case day
    case night
    case custom

    public var opposite: DayNightMode {
        switch self {
        case .day: return .night
        case .night: return .day
        case .custom: return .custom
        }
    }
}

public struct BrightnessPreset: Equatable {
    public var screen: Double
    public var keyboard: Double

    public init(screen: Double, keyboard: Double) {
        self.screen = BrightnessPreset.clamp(screen)
        self.keyboard = BrightnessPreset.clamp(keyboard)
    }

    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    public static let defaultDay = BrightnessPreset(screen: 1, keyboard: 1)
    public static let defaultNight = BrightnessPreset(screen: 0.2, keyboard: 0.1)
}

public struct HardwareSnapshot: Equatable {
    public var displayValues: [UInt32: Double]
    public var keyboardValue: Double?

    public init(
        displayValues: [UInt32: Double] = [:],
        keyboardValue: Double? = nil
    ) {
        self.displayValues = displayValues.mapValues(BrightnessPreset.clamp)
        self.keyboardValue = keyboardValue.map(BrightnessPreset.clamp)
    }

    public var allChannelValues: [Double] {
        displayValues.keys.sorted().compactMap { displayValues[$0] }
            + (keyboardValue.map { [$0] } ?? [])
    }

    public var availableChannelCount: Int {
        displayValues.count + (keyboardValue == nil ? 0 : 1)
    }
}

public struct HardwarePollResult {
    public let snapshot: HardwareSnapshot
    public let newlyAvailableDisplayIDs: Set<UInt32>

    public init(
        snapshot: HardwareSnapshot,
        newlyAvailableDisplayIDs: Set<UInt32>
    ) {
        self.snapshot = snapshot
        self.newlyAvailableDisplayIDs = newlyAvailableDisplayIDs
    }
}

public struct TransitionReport {
    public let elapsed: TimeInterval
    public let displayIDsAttempted: Set<UInt32>
    public let failedDisplayIDs: Set<UInt32>
    public let keyboardAttempted: Bool
    public let keyboardFailed: Bool
    public let cancelled: Bool

    public init(
        elapsed: TimeInterval,
        displayIDsAttempted: Set<UInt32>,
        failedDisplayIDs: Set<UInt32>,
        keyboardAttempted: Bool,
        keyboardFailed: Bool,
        cancelled: Bool
    ) {
        self.elapsed = elapsed
        self.displayIDsAttempted = displayIDsAttempted
        self.failedDisplayIDs = failedDisplayIDs
        self.keyboardAttempted = keyboardAttempted
        self.keyboardFailed = keyboardFailed
        self.cancelled = cancelled
    }
}
