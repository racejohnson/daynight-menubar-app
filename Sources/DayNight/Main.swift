import AppKit

@main
@MainActor
enum DayNightMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let arguments = Array(CommandLine.arguments.dropFirst())

        // Developer tools, both on a made-up Mac: see the Makefile. A flag
        // that is mistyped must not start a second real DayNight instead.
        let delegate: AppDelegate
        switch arguments.first {
        case "--selftest" where arguments.count == 1:
            delegate = AppDelegate(demo: Demo())
        case "--readme" where arguments.count == 2:
            ReadmePictures.write(to: URL(fileURLWithPath: arguments[1]))
            app.run()
            return
        case let first? where first.hasPrefix("--"):
            FileHandle.standardError.write(Data("usage: DayNight [--selftest | --readme <folder>]\n".utf8))
            exit(2)
        default:
            // No arguments, or ones macOS adds on its own.
            delegate = AppDelegate()
        }
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
