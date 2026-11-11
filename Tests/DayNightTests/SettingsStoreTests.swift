import DayNightCore
import Testing

struct SettingsStoreTests {
    @Test func defaultsWhenEmpty() {
        let isolated = IsolatedDefaults()
        let store = SettingsStore(defaults: isolated.defaults)
        #expect(store.preset(for: .day) == .defaultDay)
        #expect(store.preset(for: .dim) == .defaultDim)
        #expect(store.preset(for: .night) == .defaultNight)
        #expect(store.presets == Presets())
        #expect(store.lastApplied == nil)
        #expect(store.launchAtLogin)
    }

    @Test func readsDayNight1Keys() {
        let isolated = IsolatedDefaults()
        let defaults = isolated.defaults
        defaults.set(0.85, forKey: "preset.day.screen")
        defaults.set(0.6, forKey: "preset.day.keyboard")
        defaults.set(0.01, forKey: "preset.night.screen")
        defaults.set(0.01, forKey: "preset.night.keyboard")
        defaults.set("night", forKey: "state.lastAppliedMode")
        defaults.set(false, forKey: "login.desired")

        let store = SettingsStore(defaults: defaults)
        #expect(store.preset(for: .day) == BrightnessPreset(screen: 0.85, keyboard: 0.6))
        #expect(store.preset(for: .night) == BrightnessPreset(screen: 0.01, keyboard: 0.01))
        #expect(store.preset(for: .dim) == .defaultDim, "Dim is new, so it starts at its default")
        #expect(store.lastApplied == .night)
        #expect(!store.launchAtLogin)
    }

    @Test func legacyValuesAreClampedAndCustomIsIgnored() {
        let isolated = IsolatedDefaults()
        isolated.defaults.set(1.8, forKey: "preset.day.screen")
        isolated.defaults.set(-0.2, forKey: "preset.day.keyboard")
        isolated.defaults.set("custom", forKey: "state.lastAppliedMode")
        let store = SettingsStore(defaults: isolated.defaults)
        #expect(store.preset(for: .day) == BrightnessPreset(screen: 1, keyboard: 0))
        #expect(store.lastApplied == nil)
    }

    @Test func writesRoundTripUnderTheSameKeys() {
        let isolated = IsolatedDefaults()
        let store = SettingsStore(defaults: isolated.defaults)
        store.setPreset(BrightnessPreset(screen: 0.33, keyboard: 0.44), for: .night)
        store.setPreset(BrightnessPreset(screen: 0.55, keyboard: 0.35), for: .dim)
        store.lastApplied = .dim
        #expect(isolated.defaults.string(forKey: "state.lastAppliedMode") == "dim")
        store.lastApplied = .day
        store.launchAtLogin = false

        #expect(isolated.defaults.double(forKey: "preset.night.screen") == 0.33)
        #expect(isolated.defaults.double(forKey: "preset.night.keyboard") == 0.44)
        #expect(isolated.defaults.double(forKey: "preset.dim.screen") == 0.55)
        #expect(isolated.defaults.double(forKey: "preset.dim.keyboard") == 0.35)
        #expect(isolated.defaults.string(forKey: "state.lastAppliedMode") == "day")
        #expect(isolated.defaults.object(forKey: "login.desired") as? Bool == false)

        let reloaded = SettingsStore(defaults: isolated.defaults)
        #expect(reloaded.preset(for: .night) == BrightnessPreset(screen: 0.33, keyboard: 0.44))
        #expect(reloaded.preset(for: .dim) == BrightnessPreset(screen: 0.55, keyboard: 0.35))
        reloaded.lastApplied = nil
        #expect(SettingsStore(defaults: isolated.defaults).lastApplied == nil)
    }
}
