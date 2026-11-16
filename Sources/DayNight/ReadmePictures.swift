import AppKit
import DayNightCore
import SwiftUI

/// `--readme <folder>`: the README's pictures, drawn from a made-up Mac so
/// they come out the same on any machine and change nothing on this one.
@MainActor
enum ReadmePictures {
    private struct Shot {
        var panel: CGImage
        var size: CGSize
        var item: NSImage
        var isDark: Bool
    }

    static func write(to folder: URL) {
        Task {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let demo = Demo()
            let presets = demo.model.presets
            var shots: [Shot] = []
            var written = true
            for (mode, dark) in [(Mode.day, false), (.away, false), (.night, true)] {
                await demo.show(presets[mode])
                guard let rep = render(demo.model, dark: dark), let image = rep.cgImage else { continue }
                shots.append(Shot(panel: image, size: rep.size, item: Glyphs.trio(demo.model.displayedState), isDark: dark))
                written = save(chip(Glyphs.trio(demo.model.displayedState)), to: folder.appendingPathComponent("icon-\(mode.rawValue).png")) && written
            }
            // The brightness keys have been used: no mode matches.
            await demo.show(BrightnessPreset(screen: 0.72, keyboard: 0.35))
            written = save(chip(Glyphs.trio(demo.model.displayedState)), to: folder.appendingPathComponent("icon-custom.png")) && written

            written = save(hero(shots), to: folder.appendingPathComponent("panel.png")) && written
            Demo.cleanUp()
            guard written, shots.count == 3 else {
                FileHandle.standardError.write(Data("readme: could not draw or write every picture in \(folder.path)\n".utf8))
                exit(1)
            }
            print("Wrote the README's pictures to \(folder.path)")
            exit(0)
        }
    }

    /// The panel's content on a flat stand-in for the glass, at the display's scale.
    static func render(_ model: AppModel, dark: Bool) -> NSBitmapImageRep? {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let view = PanelView(model: model)
            .background(Color(nsColor: backdrop(dark: dark)))
            .environment(\.colorScheme, dark ? .dark : .light)
            // System switches draw grey in a window that is not on screen.
            .environment(\.drawsSwitchesForPictures, true)
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    /// The colour `render` puts behind the panel.
    private static func backdrop(dark: Bool) -> NSColor {
        dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.95, alpha: 1)
    }

    /// The panels side by side, each under a strip of menu bar with its item.
    private static func hero(_ shots: [Shot]) -> NSImage {
        let panelWidth: CGFloat = 312, gap: CGFloat = 44, margin: CGFloat = 40
        let barHeight: CGFloat = 30, barGap: CGFloat = 7, radius: CGFloat = 22
        let tallest = shots.map(\.size.height).max() ?? 0
        let width = margin * 2 + CGFloat(shots.count) * panelWidth + CGFloat(shots.count - 1) * gap
        let height = margin * 0.6 + barHeight + barGap + tallest + margin * 1.4
        return Bitmap.draw(width: width, height: height, scales: [2]) { context in
            for (index, shot) in shots.enumerated() {
                let left = margin + CGFloat(index) * (panelWidth + gap)
                let top = height - margin * 0.6

                // The menu bar: black, fading out to either side, with the item pressed.
                let bar = CGRect(x: left - 6, y: top - barHeight, width: panelWidth + 12, height: barHeight)
                context.saveGState()
                context.clip(to: bar)
                let fade = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [0, 1, 1, 0].map { CGColor(gray: 0, alpha: $0) } as CFArray, locations: [0, 0.3, 0.7, 1]
                )
                if let fade {
                    context.drawLinearGradient(fade, start: CGPoint(x: bar.minX, y: 0), end: CGPoint(x: bar.maxX, y: 0), options: [])
                }
                context.restoreGState()
                let item = shot.item.size
                let pressed = CGRect(x: bar.midX - item.width / 2 - 6, y: bar.midY - 12, width: item.width + 12, height: 24)
                context.setFillColor(CGColor(gray: 1, alpha: 0.18))
                context.addPath(CGPath(roundedRect: pressed, cornerWidth: 7, cornerHeight: 7, transform: nil))
                context.fillPath()
                drawWhite(shot.item, at: CGPoint(x: bar.midX - item.width / 2, y: bar.midY - item.height / 2), in: context)

                // The panel: rounded, with its shadow and a hairline edge.
                let frame = CGRect(x: left, y: bar.minY - barGap - shot.size.height, width: panelWidth, height: shot.size.height)
                let shape = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: CGColor(gray: 0, alpha: 0.22))
                context.setFillColor(backdrop(dark: shot.isDark).cgColor)
                context.addPath(shape)
                context.fillPath()
                context.restoreGState()
                context.saveGState()
                context.addPath(shape)
                context.clip()
                context.draw(shot.panel, in: frame)
                context.restoreGState()
                context.setStrokeColor(CGColor(gray: shot.isDark ? 1 : 0, alpha: shot.isDark ? 0.16 : 0.12))
                context.setLineWidth(0.5)
                context.addPath(CGPath(roundedRect: frame.insetBy(dx: 0.25, dy: 0.25), cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.strokePath()
            }
        }
    }

    /// The item on a piece of menu bar, to sit in a line of text.
    private static func chip(_ item: NSImage) -> NSImage {
        let size = CGSize(width: item.size.width + 16, height: 30)
        return Bitmap.draw(width: size.width, height: size.height, scales: [2]) { context in
            context.setFillColor(.black)
            context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 7, cornerHeight: 7, transform: nil))
            context.fillPath()
            drawWhite(item, at: CGPoint(x: 8, y: (size.height - item.size.height) / 2), in: context)
        }
    }

    /// A template image is one ink: draw it, then tint what was drawn.
    private static func drawWhite(_ image: NSImage, at origin: CGPoint, in context: CGContext) {
        let rect = CGRect(origin: origin, size: image.size)
        context.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        image.draw(in: rect)
        context.setBlendMode(.sourceIn)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.endTransparencyLayer()
        context.setBlendMode(.normal)
    }

    /// Whether the picture was written.
    private static func save(_ image: NSImage, to url: URL) -> Bool {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}
