import AppKit
import DayNightCore
import SwiftUI

/// The panel's content: the three presets, open at login, and a quiet footer.
struct PanelView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { mode in
                ModeCard(mode: mode, model: model)
            }

            VStack(spacing: 10) {
                LaunchAtLoginRow(launchAtLogin: model.launchAtLogin)
                if let problem = model.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .symbolRenderingMode(.hierarchical)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Footer(summary: model.hardwareSummary)
            }
            // Shares its edges with the cards' content (4 + 8).
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
        .padding(10)
        .frame(width: 300)
        // The panel takes key focus without activating the app; without this its
        // controls would draw in the inactive (grey) style.
        .environment(\.controlActiveState, .key)
    }
}

private struct LaunchAtLoginRow: View {
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { launchAtLogin.isEnabled }, set: launchAtLogin.setEnabled)) {
                Text("Open at Login")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

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
                .font(.subheadline)
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
        .font(.subheadline)
    }
}
