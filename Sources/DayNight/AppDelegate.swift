import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var panel: PanelController?
    private var statusItem: StatusItemController?
    private var terminationSignal: (any DispatchSourceSignal)?
    private var hasRepliedToTerminate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = PanelController(model: model)
        statusItem = StatusItemController(model: model, panel: panel)
        self.panel = panel
        terminateOnSIGTERM()
        model.start()
    }

    /// Restores keyboard auto-brightness before quitting, but never holds up
    /// logout for more than two seconds: if the private framework hangs, the
    /// recovery marker stays behind and the next launch finishes the job.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        panel?.close()
        Task {
            await model.shutdown()
            replyToTerminate(sender)
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            replyToTerminate(sender)
        }
        return .terminateLater
    }

    private func replyToTerminate(_ sender: NSApplication) {
        guard !hasRepliedToTerminate else { return }
        hasRepliedToTerminate = true
        sender.reply(toApplicationShouldTerminate: true)
    }

    /// `kill`, `make install` and some logout paths send SIGTERM; route it
    /// through the normal quit so keyboard auto-brightness is restored.
    private func terminateOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        source.resume()
        terminationSignal = source
    }
}
