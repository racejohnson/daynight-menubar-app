import DayNightCore
import Foundation
import ServiceManagement

final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var desired: Bool
    @Published private(set) var statusText = "Checking…"
    @Published private(set) var requiresApproval = false
    @Published private(set) var hasError = false

    private let store: PresetStore
    private let service = SMAppService.mainApp

    init(store: PresetStore) {
        self.store = store
        desired = store.launchAtLoginDesired
    }

    func syncOnLaunch() {
        if desired {
            enableIfNeeded()
        } else {
            refreshStatus()
        }
    }

    func setDesired(_ enabled: Bool) {
        desired = enabled
        store.launchAtLoginDesired = enabled
        if enabled {
            enableIfNeeded()
        } else {
            do {
                if service.status == .enabled ||
                    service.status == .requiresApproval {
                    try service.unregister()
                }
                hasError = false
            } catch {
                hasError = true
                statusText = "Could not disable: \(error.localizedDescription)"
            }
            refreshStatus(preserveError: hasError)
        }
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func enableIfNeeded() {
        let status = service.status
        if status != .enabled && status != .requiresApproval {
            do {
                try service.register()
                hasError = false
            } catch {
                hasError = true
                statusText = "Could not enable: \(error.localizedDescription)"
            }
        }
        refreshStatus(preserveError: hasError)
    }

    private func refreshStatus(preserveError: Bool = false) {
        requiresApproval = false
        if !preserveError {
            hasError = false
        }

        switch service.status {
        case .notRegistered:
            if !preserveError { statusText = "Off" }
        case .enabled:
            statusText = "On"
        case .requiresApproval:
            requiresApproval = true
            statusText = "Approval needed in Login Items"
        case .notFound:
            hasError = true
            statusText = "App must be installed in Applications"
        @unknown default:
            hasError = true
            statusText = "Unknown login-item status"
        }

        UserDefaults.standard.set(
            statusText, forKey: "login.lastObservedStatus"
        )
    }
}
