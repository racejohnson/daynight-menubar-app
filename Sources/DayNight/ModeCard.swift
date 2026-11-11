import DayNightCore
import SwiftUI

/// One preset: a header that applies it, and its screen and keyboard levels.
/// The active preset is tinted; a fade toward it tints it as the fade runs.
struct ModeCard: View {
    let mode: Mode
    let model: AppModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool { model.displayedState.mode == mode }
    private var isFading: Bool { model.fadingTo == mode }
    private var preset: BrightnessPreset { model.preset(for: mode) }

    var body: some View {
        VStack(spacing: 4) {
            Button { model.apply(mode) } label: { header }
                .buttonStyle(HeaderButtonStyle())
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(isActive ? .isSelected : [])
                .accessibilityHint("Fades to the \(mode.title) preset")

            VStack(spacing: 8) {
                LevelSlider(
                    symbol: "display",
                    label: "\(mode.title) screen brightness",
                    value: preset.screen,
                    tint: sliderTint
                ) { model.setScreen($0, for: mode) }

                LevelSlider(
                    symbol: "keyboard",
                    label: "\(mode.title) keyboard brightness",
                    value: preset.keyboard,
                    tint: sliderTint,
                    unavailable: model.hasKeyboard
                        ? nil : "No keyboard backlight connected. The level is saved for later."
                ) { model.setKeyboard($0, for: mode) }
            }
            .padding(.horizontal, 8)
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
        .padding(.horizontal, 4)
        .background(fill, in: .rect(cornerRadius: 12, style: .continuous))
        .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: isActive)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: mode.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .symbolEffect(.pulse, options: .repeat(.continuous), isActive: isFading && !reduceMotion)
                .frame(width: Self.badgeSize, height: Self.badgeSize)
                .background(isActive ? AnyShapeStyle(mode.tint) : AnyShapeStyle(.fill.secondary), in: .circle)
            Text(mode.title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .contentShape(.rect)
    }

    static let badgeSize: CGFloat = 26

    /// Inactive sliders stay neutral so only the active preset carries colour.
    private var sliderTint: Color {
        isActive ? mode.tint : LevelSlider.neutral
    }

    private var fill: AnyShapeStyle {
        if isActive {
            AnyShapeStyle(mode.tint.opacity(mode.fillOpacity(colorScheme)))
        } else {
            AnyShapeStyle(.fill.quaternary)
        }
    }
}

private struct HeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(isPressed: configuration.isPressed) { configuration.label }
    }
}

private struct HoverHighlight<Label: View>: View {
    let isPressed: Bool
    @ViewBuilder let label: Label
    @State private var isHovering = false

    var body: some View {
        label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                .fill.opacity(isPressed ? 1 : isHovering ? 0.6 : 0),
                in: .rect(cornerRadius: 8, style: .continuous)
            )
            .onHover { isHovering = $0 }
    }
}

/// A 0–100 % slider with a leading symbol and a trailing value. When its
/// channel is `unavailable` the row reads as secondary but stays editable.
private struct LevelSlider: View {
    /// A quiet fill a step above the track. Opaque, because the slider
    /// flattens a translucent tint into a heavy grey.
    static let neutral = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(white: isDark ? 0.52 : 0.72, alpha: 1)
    })

    let symbol: String
    let label: String
    let value: Double
    let tint: Color
    var unavailable: String?
    let onChange: @MainActor (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(detailStyle)
                .frame(width: ModeCard.badgeSize)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { value }, set: onChange), in: 0...1)
                .controlSize(.small)
                .tint(unavailable == nil ? tint : Self.neutral)
                .accessibilityLabel(label)
                .accessibilityValue("\(Int((value * 100).rounded())) percent")
                .accessibilityHint(unavailable ?? "")
            Text(value, format: .percent.precision(.fractionLength(0)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(detailStyle)
                .frame(width: 34, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .help(unavailable ?? "")
    }

    private var detailStyle: HierarchicalShapeStyle {
        unavailable == nil ? .secondary : .tertiary
    }
}
