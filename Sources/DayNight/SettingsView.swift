import AppKit
import DayNightCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: DayNightViewModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: stateSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(stateTitle)
                            .font(.headline)
                        Text(model.hardwareSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                presetEditor(
                    title: "Day",
                    symbol: "sun.max.fill",
                    mode: .day,
                    preset: model.day
                )

                presetEditor(
                    title: "Night",
                    symbol: "moon.fill",
                    mode: .night,
                    preset: model.night
                )

                Divider()

                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { model.launchAtLogin.desired },
                        set: { model.launchAtLogin.setDesired($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)

                HStack(alignment: .firstTextBaseline) {
                    Text(model.launchAtLogin.statusText)
                        .font(.caption)
                        .foregroundStyle(
                            model.launchAtLogin.hasError ? .red : .secondary
                        )
                    Spacer()
                    if model.launchAtLogin.requiresApproval ||
                        model.launchAtLogin.hasError {
                        Button("Open Login Items") {
                            model.launchAtLogin.openLoginItems()
                        }
                        .controlSize(.small)
                    }
                }

                if !model.detailMessage.isEmpty {
                    Text(model.detailMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Button("Apply Day") { model.apply(.day) }
                    Button("Apply Night") { model.apply(.night) }
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                }
                .controlSize(.small)
            }
            .padding(12)
        }
        .frame(width: 332, height: 370)
    }

    @ViewBuilder
    private func presetEditor(
        title: String,
        symbol: String,
        mode: DayNightMode,
        preset: BrightnessPreset
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))

            brightnessRow(
                label: "Screens",
                value: preset.screen,
                set: { model.setScreenValue($0, for: mode) }
            )
            brightnessRow(
                label: "Keyboard",
                value: preset.keyboard,
                set: { model.setKeyboardValue($0, for: mode) }
            )
        }
        .padding(8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private func brightnessRow(
        label: String,
        value: Double,
        set: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 58, alignment: .leading)
            Slider(
                value: Binding(get: { value * 100 }, set: { set($0 / 100) }),
                in: 0...100
            )
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var stateTitle: String {
        switch model.state {
        case .day: return "Day"
        case .night: return "Night"
        case .custom: return "Custom"
        }
    }

    private var stateSymbol: String {
        switch model.state {
        case .day: return "sun.max.fill"
        case .night: return "moon.fill"
        case .custom: return "slider.horizontal.3"
        }
    }
}
