import AppKit

/// Annotations that hold editable text (Text and Callout) implement this so the
/// canvas can reuse one text-editing overlay for both.
protocol TextEditable: AnyObject {
    var string: String { get set }
    var editFont: NSFont { get set }
    var editColor: NSColor { get set }
    /// Rect (image space, bottom-left origin) the editor overlay should occupy.
    var textEditRect: CGRect { get }
}

/// Rendering environment handed to each annotation so tools that need the
/// underlying pixels (blur) can sample them.
struct RenderEnv {
    /// The flattened base image (screenshot + already-applied crops), used by
    /// blur to sample the region it obscures.
    let baseCGImage: CGImage?
    let imageSize: CGSize
}

/// Abstract annotation object living in *image* coordinate space
/// (origin bottom-left, points = base-image points).
class Annotation {
    var color: NSColor = Palette.defaultColor
    var lineWidth: CGFloat = 4
    var dashed: Bool = false

    /// Draw self into the current NSGraphicsContext (already transformed to
    /// image space by the canvas).
    func draw(env: RenderEnv) {}

    /// Tight bounding box in image space (used for selection & hit-testing).
    var bounds: CGRect { .zero }

    /// Hit test in image space, with a tolerance in image points.
    func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
    }

    /// Move the whole object.
    func translate(by d: CGVector) {}

    /// Resize handles in image space (empty = not resizable). The canvas draws
    /// these when the object is selected and lets the user drag them.
    func resizeHandles() -> [CGPoint] { [] }

    /// Move handle `index` (from `resizeHandles()`) to point `p`.
    func moveHandle(_ index: Int, to p: CGPoint) {}

    /// Deep copy for undo snapshots.
    func clone() -> Annotation { Annotation() }

    /// Standard 8 handle points for a rect (bl, br, tl, tr, left, right, bottom, top).
    static func rectHandles(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
         CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY),
         CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.midX, y: r.maxY)]
    }

    /// Apply an 8-handle drag to a rect, returning the new (unnormalized ok) rect.
    static func resizedRect(_ r: CGRect, handle i: Int, to p: CGPoint, minSize: CGFloat = 8) -> CGRect {
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch i {
        case 0: minX = p.x; minY = p.y
        case 1: maxX = p.x; minY = p.y
        case 2: minX = p.x; maxY = p.y
        case 3: maxX = p.x; maxY = p.y
        case 4: minX = p.x
        case 5: maxX = p.x
        case 6: minY = p.y
        case 7: maxY = p.y
        default: break
        }
        var out = CGRect(x: min(minX, maxX), y: min(minY, maxY),
                         width: abs(maxX - minX), height: abs(maxY - minY))
        if out.width < minSize { out.size.width = minSize }
        if out.height < minSize { out.size.height = minSize }
        return out
    }

    // MARK: helpers

    func stroke(_ path: NSBezierPath) {
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if dashed {
            path.setLineDash([lineWidth * 2.4, lineWidth * 1.8], count: 2, phase: 0)
        }
        color.setStroke()
        path.stroke()
    }

    static func distance(point p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 == 0 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = max(0, min(1, t))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
}
