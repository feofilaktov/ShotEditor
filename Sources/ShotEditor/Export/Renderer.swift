import AppKit

/// Flattens a document (base image + annotations) into a single bitmap.
enum Renderer {

    /// Draw into an exact-pixel bitmap via a CGContext (no Core Image, so the
    /// output size is always exactly `pixelSize` — a cached CIContext can
    /// otherwise emit at the display's backing scale and double the pixels).
    private static func renderBitmap(_ pixelSize: CGSize, _ draw: (CGContext) -> Void) -> NSImage? {
        let w = Int(pixelSize.width.rounded()), h = Int(pixelSize.height.rounded())
        guard w > 0, h > 0 else { return nil }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = CGSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        let gctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = gctx
        let cg = gctx.cgContext
        cg.interpolationQuality = .high
        draw(cg)
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: rep.size)
        out.addRepresentation(rep)
        return out
    }

    static func rotated(_ doc: EditorDocument, clockwise: Bool) -> NSImage? {
        guard let src = flattenCGImage(doc) else { return nil }
        let s = doc.imageSize
        let newSize = CGSize(width: s.height, height: s.width)
        return renderBitmap(newSize) { cg in
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: clockwise ? -.pi / 2 : .pi / 2)
            cg.draw(src, in: CGRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height))
        }
    }

    static func flipped(_ doc: EditorDocument, horizontal: Bool) -> NSImage? {
        guard let src = flattenCGImage(doc) else { return nil }
        let s = doc.imageSize
        return renderBitmap(s) { cg in
            if horizontal { cg.translateBy(x: s.width, y: 0); cg.scaleBy(x: -1, y: 1) }
            else          { cg.translateBy(x: 0, y: s.height); cg.scaleBy(x: 1, y: -1) }
            cg.draw(src, in: CGRect(origin: .zero, size: s))
        }
    }

    static func scaled(_ doc: EditorDocument, to newWidth: CGFloat) -> NSImage? {
        guard let src = flattenCGImage(doc) else { return nil }
        let s = doc.imageSize
        guard s.width > 0 else { return nil }
        let newSize = CGSize(width: newWidth, height: (newWidth * s.height / s.width).rounded())
        return renderBitmap(newSize) { cg in
            cg.draw(src, in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Composite everything into a bitmap at exact 1:1 pixel size.
    static func flattenRep(_ doc: EditorDocument) -> NSBitmapImageRep {
        let size = doc.imageSize
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(size.width),
                                   pixelsHigh: Int(size.height),
                                   bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx

        doc.baseImage.draw(in: CGRect(origin: .zero, size: size),
                           from: .zero, operation: .copy, fraction: 1.0)
        let env = doc.renderEnv
        for a in doc.annotations {
            ctx.saveGraphicsState()
            a.draw(env: env)
            ctx.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func flatten(_ doc: EditorDocument) -> NSImage {
        let rep = flattenRep(doc)
        let out = NSImage(size: rep.size)
        out.addRepresentation(rep)
        return out
    }

    /// Exact-pixel CGImage (from the bitmap rep, so it is NOT affected by the
    /// screen's backing scale the way `NSImage.cgImage(forProposedRect:)` is).
    static func flattenCGImage(_ doc: EditorDocument) -> CGImage? {
        flattenRep(doc).cgImage
    }

    /// Flatten including the backdrop frame (used for export / copy).
    static func flattenForExport(_ doc: EditorDocument) -> NSImage {
        let inner = flatten(doc)
        let bd = doc.backdrop
        guard bd.enabled else { return inner }

        let total = bd.totalSize(for: doc.imageSize)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(total.width), pixelsHigh: Int(total.height),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = total

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!

        bd.drawBackground(in: CGRect(origin: .zero, size: total))

        let imgRect = CGRect(origin: bd.imageOrigin(), size: doc.imageSize)
        let radius = bd.cornerRadius
        let rounded = NSBezierPath(roundedRect: imgRect, xRadius: radius, yRadius: radius)

        if bd.shadow {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            shadow.shadowBlurRadius = 30
            shadow.shadowOffset = CGSize(width: 0, height: -10)
            shadow.set()
            NSColor.white.setFill()
            rounded.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.saveGraphicsState()
        rounded.addClip()
        inner.draw(in: imgRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.restoreGraphicsState()

        let out = NSImage(size: total)
        out.addRepresentation(rep)
        return out
    }

    /// Crop a composite to `rect` (image space, bottom-left origin).
    static func crop(_ image: NSImage, to rect: CGRect) -> NSImage {
        let size = rect.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(size.width),
                                   pixelsHigh: Int(size.height),
                                   bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
        image.draw(in: CGRect(origin: .zero, size: size),
                   from: rect, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }
}
