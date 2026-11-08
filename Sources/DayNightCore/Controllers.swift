import CoreGraphics
import DayNightPrivateAPI

public protocol DisplayControlling: Sendable {
    func onlineDisplayIDs() -> [UInt32]
    func canControlBrightness(of display: UInt32) -> Bool
    func brightness(of display: UInt32) -> Double?
    func setBrightness(_ value: Double, of display: UInt32) -> Bool
}

public protocol KeyboardControlling: Sendable {
    var isAvailable: Bool { get }
    func brightness() -> Double?
    func setBrightness(_ value: Double) -> Bool
    func isAutoBrightnessEnabled() -> Bool?
    func setAutoBrightnessEnabled(_ enabled: Bool) -> Bool
}

/// Apple displays through the private DisplayServices framework.
public struct SystemDisplays: DisplayControlling {
    public init() {}

    public func onlineDisplayIDs() -> [UInt32] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    public func canControlBrightness(of display: UInt32) -> Bool {
        DNDisplayCanChangeBrightness(display)
    }

    public func brightness(of display: UInt32) -> Double? {
        var value: Float = 0
        return DNDisplayGetBrightness(display, &value) ? Double(value) : nil
    }

    public func setBrightness(_ value: Double, of display: UInt32) -> Bool {
        DNDisplaySetBrightness(display, Float(BrightnessPreset.clamp(value)))
    }
}

/// The built-in keyboard backlight through the private CoreBrightness framework.
public struct SystemKeyboard: KeyboardControlling {
    public init() {}

    public var isAvailable: Bool { DNKeyboardAvailable() }

    public func brightness() -> Double? {
        var value: Float = 0
        return DNKeyboardGetBrightness(&value) ? Double(value) : nil
    }

    public func setBrightness(_ value: Double) -> Bool {
        DNKeyboardSetBrightness(Float(BrightnessPreset.clamp(value)))
    }

    public func isAutoBrightnessEnabled() -> Bool? {
        var enabled = false
        return DNKeyboardGetAutoBrightness(&enabled) ? enabled : nil
    }

    public func setAutoBrightnessEnabled(_ enabled: Bool) -> Bool {
        DNKeyboardSetAutoBrightness(enabled)
    }
}
