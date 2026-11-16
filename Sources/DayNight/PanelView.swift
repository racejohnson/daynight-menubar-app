import AppKit
import DayNightCore
import SwiftUI

/// The panel: the two levels, the three modes, open at login and a quiet
/// footer. Laid out as Audio Priority's panel is, so the two read as a pair.
struct PanelView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let problem = model.problem { Banner(text: problem) }

            VStack(spacing: 8) {
                LevelSlider(model: model, channel: .screens)
                LevelSlider(model: model, channel: .keyboard)
            }
            .padding(.bottom, 6)

            VStack(spacing: 1) {
                Heading(
                    title: "Mode",
                    hint: model.displayedState.mode.map { "the sliders set \($0.title)" } ?? "the sliders set no mode"
                )
                ForEach(Mode.allCases, id: \.self) { mode in
                    ModeRow(mode: mode, model: model)
                }
            }
            Rule()

            LaunchAtLoginRow(launchAtLogin: model.launchAtLogin)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)

            Rule()
            Footer(summary: model.hardwareSummary)
        }
        .padding(10)
        .frame(width: 312)
        // The panel takes key focus without activating the app; without this its
        // controls would draw in the inactive (grey) style.
        .environment(\.controlActiveState, .key)
    }
}

// MARK: Small pieces

private struct Rule: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}

private struct Banner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.primary.opacity(0.075)))
            .padding(.bottom, 8)
    }
}

private struct Heading: View {
    let title: String
    let hint: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(hint)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 3)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension EnvironmentValues {
    /// True in the off-screen pictures (`--readme`), where the system switch
    /// draws grey because its window is not the key window.
    @Entry var drawsSwitchesForPictures = false
}

/// A stand-in for the system's mini switch as it looks in the open panel.
private struct DrawnSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Capsule()
                .fill(configuration.isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary.opacity(0.16)))
                .frame(width: 36, height: 17)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(.white)
                        .frame(width: 22, height: 13)
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                        .padding(2)
                }
        }
    }
}

private struct LaunchAtLoginRow: View {
    let launchAtLogin: LaunchAtLogin
    @Environment(\.drawsSwitchesForPictures) private var drawsSwitch

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let toggle = Toggle(isOn: Binding(get: { launchAtLogin.isEnabled }, set: launchAtLogin.setEnabled)) {
                Text("Open at Login")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if drawsSwitch {
                toggle.toggleStyle(DrawnSwitchStyle())
            } else {
                toggle.toggleStyle(.switch).controlSize(.mini)
            }

            if let issue = launchAtLogin.issue {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(issue.message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if issue == .needsApproval {
                        Button("Open Login Items", action: launchAtLogin.openLoginItems)
                            .buttonStyle(.link)
                    }
                }
                .font(.system(size: 11))
            }
        }
    }
}

private struct Footer: View {
    let summary: String
    @State private var isHoveringQuit = false

    var body: some View {
        HStack {
            Text(summary)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(isHoveringQuit ? .primary : .secondary)
                .onHover { isHoveringQuit = $0 }
                .help("Quit DayNight (⌘Q)")
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
    }
}

// MARK: Level slider

/// A Control Center–style slider for the screens or the keyboard light. It
/// shows the mode that is on and sets it as it is dragged; with no mode on it
/// shows the brightness as it is and sets that, changing no mode.
private struct LevelSlider: View {
    enum Channel {
        case screens, keyboard
    }

    let model: AppModel
    let channel: Channel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var value: Double { channel == .screens ? model.levels.screen : model.levels.keyboard }
    private var canSet: Bool { channel == .screens ? model.canSetScreen : model.canSetKeyboard }
    /// The hardware this slider sets is missing. With a mode on, the level is
    /// still kept for when it is back.
    private var isMissing: Bool { channel == .screens ? model.displayCount == 0 : !model.hasKeyboard }
    private var title: String { channel == .screens ? "Screens" : "Keyboard" }

    /// What a change does, for VoiceOver: the heading says it, but comes after the sliders.
    private var spokenHint: String {
        let effect = model.displayedState.mode.map { "Sets \($0.title)’s level." } ?? "Sets the brightness. No mode changes."
        return note.isEmpty ? effect : "\(effect) \(note)"
    }

    private var note: String {
        guard isMissing else { return "" }
        let missing = channel == .screens ? "No display DayNight can set is connected." : "No keyboard backlight is connected."
        return canSet ? "\(missing) The level is saved for later." : missing
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * (canSet ? value : 0)
            ZStack(alignment: .leading) {
                // With nothing to set, a fainter, empty track.
                Capsule().fill(.primary.opacity(canSet ? 0.08 : 0.05))
                // The label is drawn twice, each copy clipped to its own side of
                // the edge, so the text stays readable across it and neither
                // copy shows through the other.
                label
                    .foregroundStyle(isMissing ? .secondary : .primary)
                    .mask(alignment: .trailing) { Rectangle().frame(width: max(geometry.size.width - width, 0)) }
                // White in both appearances, as in Control Center. A plain
                // colour, because `.primary` goes grey on glass. Grey when the
                // hardware is missing and the level is only being kept.
                Rectangle()
                    .fill(isMissing ? AnyShapeStyle(.primary.opacity(0.11)) : AnyShapeStyle(Color.white.opacity(0.92)))
                    .frame(width: width)
                label
                    .foregroundStyle(isMissing ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.black))
                    .mask(alignment: .leading) { Rectangle().frame(width: width) }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard canSet, geometry.size.width > 0 else { return }
                    set(min(max(drag.location.x / geometry.size.width, 0), 1))
                }
                .onEnded { _ in model.endLevelEdit() })
            // The fill glides when the mode changes, as the brightness fades,
            // and follows a drag exactly.
            .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: model.displayedState)
        }
        .frame(height: 30)
        // Focus comes from the keyboard only (Tab, with keyboard navigation
        // on), so a click leaves no focus ring behind.
        .focusable(canSet, interactions: .activate)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            guard canSet else { return .ignored }
            // A sixteenth, as the brightness keys step; Option steps by one percent.
            let step = press.modifiers.contains(.option) ? 0.01 : 1.0 / 16
            let isUp = press.key == .rightArrow || press.key == .upArrow
            set(min(max(value + (isUp ? step : -step), 0), 1))
            model.endLevelEdit()
            return .handled
        }
        .accessibilityRepresentation {
            // Each change is a whole edit, as an arrow key is: VoiceOver's
            // steps come without a start and an end.
            Slider(
                value: Binding(get: { value }, set: { level in
                    set(level)
                    model.endLevelEdit()
                }),
                in: 0...1, step: 1.0 / 16
            ) { Text(title) }
            .disabled(!canSet)
            .accessibilityValue("\(Int((value * 100).rounded())) percent")
            .accessibilityHint(canSet ? spokenHint : note)
        }
        .help(note)
    }

    private func set(_ level: Double) {
        channel == .screens ? model.setScreen(level) : model.setKeyboard(level)
    }

    private var label: some View {
        HStack(spacing: 8) {
            Image(systemName: channel == .screens ? "display" : "keyboard")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 12, weight: .medium))
                // As wide as a row's badge, so the glyphs and the names line up down the panel.
                .frame(width: 26)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            if canSet {
                Percent(level: value)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .opacity(0.6)
            }
        }
        // The right edge lines up with the heading's hint and Quit.
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A percentage that counts along with the fill beside it when a mode
/// change glides, where plain text would jump to the new number at once.
private struct Percent: View, Animatable {
    var level: Double

    nonisolated var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    var body: some View {
        Text(level, format: .percent.precision(.fractionLength(0)))
    }
}

// MARK: Mode rows

/// One mode: click it to fade to it. The one that is on is filled with its colour.
private struct ModeRow: View {
    let mode: Mode
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    private var isActive: Bool { model.displayedState.mode == mode }
    private var isFading: Bool { model.fadingTo == mode }

    private var detail: String {
        let preset = model.preset(for: mode)
        return "Screens \(Self.percent(preset.screen)) · Keyboard \(Self.percent(preset.keyboard))"
    }

    private static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: mode.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .symbolEffect(.pulse, options: .repeat(.continuous), isActive: isFading && !reduceMotion)
                .frame(width: 26, height: 26)
                .background(Circle().fill(isActive ? AnyShapeStyle(.white.opacity(0.24)) : AnyShapeStyle(.primary.opacity(0.075))))

            VStack(alignment: .leading, spacing: 0) {
                Text(mode.title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                Text(detail)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(isActive ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
            .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .lineLimit(1)

            Spacer(minLength: 2)
        }
        // The right edge lines up with the heading, the rules and the switch.
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: 38)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? AnyShapeStyle(mode.tint) : AnyShapeStyle(.primary.opacity(isHovering || isFocused ? 0.055 : 0)))
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isActive)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            // A click focuses the row; let go, so its fill does not outstay the pointer.
            isFocused = false
            model.apply(mode)
        }
        .focusable()
        .focused($isFocused)
        // No system focus ring: a click focuses the row, and the ring then
        // reads as a stray border. A focused row takes the hover fill instead.
        .focusEffectDisabled()
        .onKeyPress(keys: [.return, .space]) { _ in
            model.apply(mode)
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.title)
        .accessibilityValue(detail)
        .accessibilityHint("Fades to \(mode.title)")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.apply(mode) }
    }
}
