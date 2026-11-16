import AppKit

@main
@MainActor
enum DayNightMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let arguments = CommandLine.arguments

        // Developer tools, both on a made-up Mac: see the Makefile.
        if let index = arguments.firstIndex(of: "--readme"), arguments.count > index + 1 {
            ReadmePictures.write(to: URL(fileURLWithPath: arguments[index + 1]))
            app.run()
            return
        }
        let delegate = AppDelegate(demo: arguments.contains("--selftest") ? Demo() : nil)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
