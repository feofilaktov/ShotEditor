import AppKit

/// The editable state of one screenshot: the base bitmap plus the stack of
/// vector annotations drawn over it.
final class EditorDocument {

    private(set) var baseImage: NSImage
    private(set) var baseCGImage: CGImage?
    var annotations: [Annotation] = []
    var backdrop = Backdrop()

    let settings = ToolSettings()

    /// Pixel size of the base image (points, treated 1:1 for annotation coords).
    var imageSize: CGSize { baseImage.pixelSizeOrDefault }

    init(image: NSImage) {
        self.baseImage = EditorDocument.normalized(image)
        self.baseCGImage = self.baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Redraw into an explicit 1:1 bitmap so the canvas works in true pixels.
    /// (Uses an offscreen bitmap context rather than `lockFocus`, which would
    /// re-apply the screen's backing-scale factor and double-size the image.)
    private static func normalized(_ image: NSImage) -> NSImage {
        let size = image.pixelSizeOrDefault
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
                   from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }

    var renderEnv: RenderEnv {
        RenderEnv(baseCGImage: baseCGImage, imageSize: imageSize)
    }

    // MARK: Mutations

    func add(_ annotation: Annotation) {
        annotations.append(annotation)
    }

    func remove(_ annotation: Annotation) {
        annotations.removeAll { $0 === annotation }
    }

    /// Replace the base image (used by crop, which bakes everything down).
    func replaceBase(with image: NSImage, annotations newAnnotations: [Annotation]) {
        self.baseImage = image
        self.baseCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        self.annotations = newAnnotations
    }

    /// Topmost annotation at a point (image space).
    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Annotation? {
        for a in annotations.reversed() where a.hitTest(point, tolerance: tolerance) {
            return a
        }
        return nil
    }
}

extension NSImage {
    /// Pixel size from the largest bitmap rep, falling back to `size`.
    var pixelSizeOrDefault: CGSize {
        var best = CGSize.zero
        for rep in representations {
            let s = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            if s.width * s.height > best.width * best.height { best = s }
        }
        if best.width < 1 || best.height < 1 { return size }
        return best
    }
}
