import AppKit
import DayNightCore

/// The menu-bar item's drawing: Audio Priority's capsule, holding all three modes.
@MainActor
enum Glyphs {
    static let size = CGSize(width: 76, height: 22)
    private static let slot: CGFloat = 24
    private static let padding: CGFloat = 2

    /// The capsule, 76 × 22 pt: sun, walking figure and moon on a soft 16%
    /// fill. The mode that is on is at full strength and the others are faint.
    /// When the brightness matches no mode, all three are faint.
    static func trio(_ state: BrightnessState) -> NSImage {
        let capsule = Bitmap.draw(width: size.width, height: size.height) { context in
            context.setFillColor(CGColor(gray: 0, alpha: 0.16))
            context.addPath(CGPath(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerWidth: size.height / 2, cornerHeight: size.height / 2, transform: nil
            ))
            context.fillPath()
            for (index, mode) in Mode.allCases.enumerated() {
                let glyph = symbol(mode.symbolName)
                let box = CGRect(x: padding + CGFloat(index) * slot, y: 0, width: slot, height: size.height)
                let rect = CGRect(
                    x: box.midX - glyph.size.width / 2, y: box.midY - glyph.size.height / 2,
                    width: glyph.size.width, height: glyph.size.height
                )
                glyph.draw(in: rect, from: .zero, operation: .sourceOver, fraction: mode == state.mode ? 1 : 0.3)
            }
        }
        capsule.isTemplate = true
        return capsule
    }

    /// One flat ink: some symbols otherwise shade parts of themselves.
    private static func symbol(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold).applying(.preferringMonochrome())
        return image.withSymbolConfiguration(configuration) ?? image
    }
}

/// Draws into bitmaps at 1×, 2× and 3×, so a display of any density gets a
/// copy made for it and nothing is resampled.
@MainActor
enum Bitmap {
    static func draw(width: CGFloat, height: CGFloat, scales: [CGFloat] = [1, 2, 3], _ body: (CGContext) -> Void) -> NSImage {
        let size = CGSize(width: width, height: height)
        let image = NSImage(size: size)
        for scale in scales {
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int((width * scale).rounded(.up)), pixelsHigh: Int((height * scale).rounded(.up)),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) else { continue }
            // Set before the context is made, so drawing is in points, not pixels.
            rep.size = size
            guard let context = NSGraphicsContext(bitmapImageRep: rep) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            body(context.cgContext)
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        return image
    }
}
