import DayNightCore
import Testing

struct SettingsStoreTests {
    @Test func defaultsWhenEmpty() {
        let isolated = IsolatedDefaults()
        let store = SettingsStore(defaults: isolated.defaults)
        #expect(store.preset(for: .day) == .defaultDay)
        #expect(store.preset(for: .away) == .defaultAway)
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
        #expect(store.preset(for: .away) == .defaultAway, "Away came later, so it starts at its default")
        #expect(store.lastApplied == .night)
        #expect(!store.launchAtLogin)
    }

    @Test func levelsSavedAsDimCarryOverToAway() {
        let isolated = IsolatedDefaults()
        let defaults = isolated.defaults
        defaults.set(0.4, forKey: "preset.dim.screen")
        defaults.set(0.25, forKey: "preset.dim.keyboard")
        defaults.set("dim", forKey: "state.lastAppliedMode")

        let store = SettingsStore(defaults: defaults)
        #expect(store.preset(for: .away) == BrightnessPreset(screen: 0.4, keyboard: 0.25))
        #expect(store.lastApplied == .away)

        store.setPreset(BrightnessPreset(screen: 0.6, keyboard: 0.25), for: .away)
        #expect(store.preset(for: .away) == BrightnessPreset(screen: 0.6, keyboard: 0.25), "new levels win")
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
        store.setPreset(BrightnessPreset(screen: 0.55, keyboard: 0.35), for: .away)
        store.lastApplied = .away
        #expect(isolated.defaults.string(forKey: "state.lastAppliedMode") == "away")
        store.lastApplied = .day
        store.launchAtLogin = false

        #expect(isolated.defaults.double(forKey: "preset.night.screen") == 0.33)
        #expect(isolated.defaults.double(forKey: "preset.night.keyboard") == 0.44)
        #expect(isolated.defaults.double(forKey: "preset.away.screen") == 0.55)
        #expect(isolated.defaults.double(forKey: "preset.away.keyboard") == 0.35)
        #expect(isolated.defaults.string(forKey: "state.lastAppliedMode") == "day")
        #expect(isolated.defaults.object(forKey: "login.desired") as? Bool == false)

        let reloaded = SettingsStore(defaults: isolated.defaults)
        #expect(reloaded.preset(for: .night) == BrightnessPreset(screen: 0.33, keyboard: 0.44))
        #expect(reloaded.preset(for: .away) == BrightnessPreset(screen: 0.55, keyboard: 0.35))
        reloaded.lastApplied = nil
        #expect(SettingsStore(defaults: isolated.defaults).lastApplied == nil)
    }
}
