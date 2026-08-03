import XCTest
import AppKit
@testable import ShotEditor

/// Shared helpers for building and sampling images headlessly (no screen).
enum TestSupport {

    /// Build an NSImage at exact 1:1 pixel size via an offscreen bitmap context.
    static func makeImage(_ w: Int, _ h: Int, fill: NSColor = .white, text: String? = nil) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = CGSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
        fill.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        if let text {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: CGFloat(h) * 0.5),
                .foregroundColor: NSColor.black,
            ]
            (text as NSString).draw(at: CGPoint(x: 6, y: CGFloat(h) * 0.2), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: CGSize(width: w, height: h))
        img.addRepresentation(rep)
        return img
    }

    static func bitmap(_ image: NSImage) -> NSBitmapImageRep {
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        return NSBitmapImageRep(cgImage: cg)
    }

    /// Sample a pixel (top-left origin) as sRGB.
    static func pixel(_ image: NSImage, _ x: Int, _ y: Int) -> NSColor {
        (bitmap(image).colorAt(x: x, y: y) ?? .clear).usingColorSpace(.sRGB) ?? .black
    }

    static func luminance(_ c: NSColor) -> CGFloat {
        let s = c.usingColorSpace(.sRGB) ?? c
        return 0.299 * s.redComponent + 0.587 * s.greenComponent + 0.114 * s.blueComponent
    }
}
