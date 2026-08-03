import AppKit

// MARK: - Arrow

enum ArrowStyle: Int, CaseIterable {
    case filled     // solid triangular head
    case thin       // open V head
    case line       // plain line, no head

    var iconName: String {
        switch self {
        case .filled: return "arrow.right"
        case .thin:   return "arrow.up.right"
        case .line:   return "line.diagonal"
        }
    }
}

final class ArrowAnnotation: Annotation {
    var start: CGPoint
    var end: CGPoint
    var style: ArrowStyle
    var shadow: Bool = true

    init(start: CGPoint, end: CGPoint, style: ArrowStyle) {
        self.start = start
        self.end = end
        self.style = style
    }

    override var bounds: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    override func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        Annotation.distance(point: p, toSegment: start, end) <= max(tolerance, lineWidth)
    }

    override func translate(by d: CGVector) {
        start.x += d.dx; start.y += d.dy
        end.x += d.dx; end.y += d.dy
    }

    override func resizeHandles() -> [CGPoint] { [start, end] }
    override func moveHandle(_ index: Int, to p: CGPoint) {
        if index == 0 { start = p } else { end = p }
    }

    override func clone() -> Annotation {
        let a = ArrowAnnotation(start: start, end: end, style: style)
        a.color = color; a.lineWidth = lineWidth; a.shadow = shadow; a.dashed = dashed
        return a
    }

    override func draw(env: RenderEnv) {
        let ctx = NSGraphicsContext.current?.cgContext
        if shadow {
            ctx?.saveGState()
            ctx?.setShadow(offset: CGSize(width: 0, height: -1), blur: 3,
                           color: NSColor.black.withAlphaComponent(0.35).cgColor)
        }
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLen = max(12, lineWidth * 3.2)
        let headAngle = CGFloat.pi / 6

        if style == .line {
            let path = NSBezierPath()
            path.move(to: start); path.line(to: end)
            stroke(path)
        } else {
            // shaft stops a little short so the head looks clean
            let shaftEnd = CGPoint(x: end.x - cos(angle) * headLen * 0.7,
                                   y: end.y - sin(angle) * headLen * 0.7)
            let shaft = NSBezierPath()
            shaft.move(to: start); shaft.line(to: shaftEnd)
            stroke(shaft)

            let p1 = CGPoint(x: end.x - headLen * cos(angle - headAngle),
                             y: end.y - headLen * sin(angle - headAngle))
            let p2 = CGPoint(x: end.x - headLen * cos(angle + headAngle),
                             y: end.y - headLen * sin(angle + headAngle))
            let head = NSBezierPath()
            head.move(to: p1); head.line(to: end); head.line(to: p2)
            if style == .filled {
                head.line(to: p1); head.close()
                color.setFill(); head.fill()
            } else {
                head.lineWidth = lineWidth
                head.lineCapStyle = .round
                head.lineJoinStyle = .round
                color.setStroke(); head.stroke()
            }
        }
        if shadow { ctx?.restoreGState() }
    }
}

// MARK: - Shapes

enum ShapeKind: Int, CaseIterable {
    case rect, roundedRect, ellipse, line, star

    var iconName: String {
        switch self {
        case .rect:        return "square"
        case .roundedRect: return "app"
        case .ellipse:     return "circle"
        case .line:        return "line.diagonal"
        case .star:        return "star"
        }
    }
}

final class ShapeAnnotation: Annotation {
    var kind: ShapeKind
    var p0: CGPoint     // drag start
    var p1: CGPoint     // drag current
    var filled: Bool = false

    init(kind: ShapeKind, p0: CGPoint, p1: CGPoint) {
        self.kind = kind; self.p0 = p0; self.p1 = p1
    }

    var rect: CGRect {
        CGRect(x: min(p0.x, p1.x), y: min(p0.y, p1.y),
               width: abs(p1.x - p0.x), height: abs(p1.y - p0.y))
    }

    override var bounds: CGRect { rect.insetBy(dx: -lineWidth, dy: -lineWidth) }

    override func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        let tol = max(tolerance, lineWidth)
        switch kind {
        case .line:
            return Annotation.distance(point: p, toSegment: p0, p1) <= tol
        default:
            if filled { return rect.insetBy(dx: -tol, dy: -tol).contains(p) }
            // stroke-only: hit near the edge
            let outer = rect.insetBy(dx: -tol, dy: -tol)
            let inner = rect.insetBy(dx: tol, dy: tol)
            return outer.contains(p) && !inner.contains(p)
        }
    }

    override func translate(by d: CGVector) {
        p0.x += d.dx; p0.y += d.dy; p1.x += d.dx; p1.y += d.dy
    }

    override func resizeHandles() -> [CGPoint] {
        kind == .line ? [p0, p1] : Annotation.rectHandles(rect)
    }
    override func moveHandle(_ index: Int, to p: CGPoint) {
        if kind == .line {
            if index == 0 { p0 = p } else { p1 = p }
            return
        }
        let nr = Annotation.resizedRect(rect, handle: index, to: p)
        p0 = CGPoint(x: nr.minX, y: nr.minY)
        p1 = CGPoint(x: nr.maxX, y: nr.maxY)
    }

    override func clone() -> Annotation {
        let s = ShapeAnnotation(kind: kind, p0: p0, p1: p1)
        s.color = color; s.lineWidth = lineWidth; s.filled = filled; s.dashed = dashed
        return s
    }

    override func draw(env: RenderEnv) {
        let path: NSBezierPath
        switch kind {
        case .rect:
            path = NSBezierPath(rect: rect)
        case .roundedRect:
            let r = min(rect.width, rect.height) * 0.18
            path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        case .ellipse:
            path = NSBezierPath(ovalIn: rect)
        case .line:
            path = NSBezierPath(); path.move(to: p0); path.line(to: p1)
        case .star:
            path = ShapeAnnotation.starPath(in: rect)
        }
        if filled && kind != .line {
            color.setFill(); path.fill()
        } else {
            stroke(path)
        }
    }

    static func starPath(in rect: CGRect, points: Int = 5) -> NSBezierPath {
        let path = NSBezierPath()
        let cx = rect.midX, cy = rect.midY
        let rOuter = min(rect.width, rect.height) / 2
        let rInner = rOuter * 0.42
        let steps = points * 2
        for i in 0..<steps {
            let r = (i % 2 == 0) ? rOuter : rInner
            let a = CGFloat(i) / CGFloat(steps) * 2 * .pi + .pi / 2
            let pt = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
        }
        path.close()
        return path
    }
}

// MARK: - Pen (freehand marker)

final class PenAnnotation: Annotation {
    var points: [CGPoint]
    var isHighlighter = false

    init(points: [CGPoint]) { self.points = points }

    override var bounds: CGRect {
        guard let first = points.first else { return .zero }
        var r = CGRect(origin: first, size: .zero)
        for p in points { r = r.union(CGRect(origin: p, size: .zero)) }
        return r.insetBy(dx: -lineWidth, dy: -lineWidth)
    }

    override func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        guard points.count > 1 else {
            if let f = points.first { return hypot(p.x - f.x, p.y - f.y) <= max(tolerance, lineWidth) }
            return false
        }
        let tol = max(tolerance, lineWidth)
        for i in 1..<points.count {
            if Annotation.distance(point: p, toSegment: points[i-1], points[i]) <= tol { return true }
        }
        return false
    }

    override func translate(by d: CGVector) {
        points = points.map { CGPoint(x: $0.x + d.dx, y: $0.y + d.dy) }
    }

    override func clone() -> Annotation {
        let p = PenAnnotation(points: points)
        p.color = color; p.lineWidth = lineWidth; p.isHighlighter = isHighlighter
        return p
    }

    override func draw(env: RenderEnv) {
        guard let first = points.first else { return }

        let ctx = NSGraphicsContext.current?.cgContext
        if isHighlighter {
            ctx?.saveGState()
            ctx?.setBlendMode(.multiply)
        }
        let strokeColor = isHighlighter ? color.withAlphaComponent(0.4) : color

        let path = NSBezierPath()
        path.move(to: first)
        if points.count == 1 {
            let r = lineWidth / 2
            strokeColor.setFill()
            NSBezierPath(ovalIn: CGRect(x: first.x - r, y: first.y - r,
                                        width: lineWidth, height: lineWidth)).fill()
            if isHighlighter { ctx?.restoreGState() }
            return
        }
        // Smooth with midpoint quadratic curves.
        for i in 1..<points.count {
            let mid = CGPoint(x: (points[i-1].x + points[i].x)/2,
                              y: (points[i-1].y + points[i].y)/2)
            path.curve(to: mid, controlPoint1: points[i-1], controlPoint2: points[i-1])
        }
        path.line(to: points.last!)
        path.lineWidth = lineWidth
        path.lineCapStyle = isHighlighter ? .square : .round
        path.lineJoinStyle = .round
        strokeColor.setStroke()
        path.stroke()

        if isHighlighter { ctx?.restoreGState() }
    }
}

// MARK: - Numbered step marker

final class NumberAnnotation: Annotation {
    var center: CGPoint
    var number: Int
    var diameter: CGFloat

    init(center: CGPoint, number: Int, diameter: CGFloat) {
        self.center = center; self.number = number; self.diameter = diameter
    }

    override var bounds: CGRect {
        CGRect(x: center.x - diameter/2, y: center.y - diameter/2, width: diameter, height: diameter)
    }

    override func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        hypot(p.x - center.x, p.y - center.y) <= diameter/2 + tolerance
    }

    override func translate(by d: CGVector) { center.x += d.dx; center.y += d.dy }

    override func resizeHandles() -> [CGPoint] {
        let r = diameter / 2
        return [CGPoint(x: center.x - r, y: center.y - r), CGPoint(x: center.x + r, y: center.y - r),
                CGPoint(x: center.x - r, y: center.y + r), CGPoint(x: center.x + r, y: center.y + r)]
    }
    override func moveHandle(_ index: Int, to p: CGPoint) {
        diameter = max(16, 2 * max(abs(p.x - center.x), abs(p.y - center.y)))
    }

    override func clone() -> Annotation {
        let n = NumberAnnotation(center: center, number: number, diameter: diameter)
        n.color = color; n.lineWidth = lineWidth
        return n
    }

    override func draw(env: RenderEnv) {
        let rect = bounds
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        ctx?.setShadow(offset: CGSize(width: 0, height: -1), blur: 3,
                       color: NSColor.black.withAlphaComponent(0.35).cgColor)
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
        ring.lineWidth = max(1.5, diameter * 0.06)
        ring.stroke()
        ctx?.restoreGState()

        let fontSize = diameter * 0.52
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let str = "\(number)" as NSString
        let sz = str.size(withAttributes: attrs)
        str.draw(at: CGPoint(x: center.x - sz.width/2, y: center.y - sz.height/2), withAttributes: attrs)
    }
}

// MARK: - Callout (speech bubble)

final class CalloutAnnotation: Annotation, TextEditable {
    var rect: CGRect
    var tailTip: CGPoint
    var string: String = ""
    var font: NSFont
    var textColor: NSColor = .white

    init(rect: CGRect, tailTip: CGPoint, font: NSFont) {
        self.rect = rect; self.tailTip = tailTip; self.font = font
    }

    override var bounds: CGRect {
        rect.union(CGRect(x: tailTip.x, y: tailTip.y, width: 1, height: 1))
    }

    override func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        rect.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
    }

    override func translate(by d: CGVector) {
        rect.origin.x += d.dx; rect.origin.y += d.dy
        tailTip.x += d.dx; tailTip.y += d.dy
    }

    override func resizeHandles() -> [CGPoint] { Annotation.rectHandles(rect) + [tailTip] }
    override func moveHandle(_ index: Int, to p: CGPoint) {
        if index == 8 { tailTip = p; return }
        rect = Annotation.resizedRect(rect, handle: index, to: p, minSize: 24)
    }

    override func clone() -> Annotation {
        let c = CalloutAnnotation(rect: rect, tailTip: tailTip, font: font)
        c.string = string; c.color = color; c.textColor = textColor; c.lineWidth = lineWidth
        return c
    }

    override func draw(env: RenderEnv) {
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        ctx?.setShadow(offset: CGSize(width: 0, height: -2), blur: 6,
                       color: NSColor.black.withAlphaComponent(0.3).cgColor)

        let radius = min(14, min(rect.width, rect.height) * 0.25)
        let bubble = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        // Tail: a triangle from the nearest edge midpoint toward tailTip.
        let baseHalf: CGFloat = max(8, min(rect.width, rect.height) * 0.12)
        let anchor = CGPoint(x: min(max(tailTip.x, rect.minX + baseHalf), rect.maxX - baseHalf),
                             y: (tailTip.y < rect.minY) ? rect.minY : rect.maxY)
        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: anchor.x - baseHalf, y: anchor.y))
        tail.line(to: tailTip)
        tail.line(to: CGPoint(x: anchor.x + baseHalf, y: anchor.y))
        tail.close()

        color.setFill()
        bubble.fill()
        tail.fill()

        // Subtle inner border for definition.
        NSColor.white.withAlphaComponent(0.25).setStroke()
        bubble.lineWidth = 1.5
        bubble.stroke()
        ctx?.restoreGState()

        // Text — auto-contrast color, wrapped and vertically centred.
        let inset = rect.insetBy(dx: 14, dy: 10)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: autoTextColor,
            .paragraphStyle: para,
        ]
        let text = string.isEmpty ? "" : string
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: inset.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        let ty = inset.midY - bounding.height / 2
        let textRect = CGRect(x: inset.minX, y: ty, width: inset.width, height: bounding.height)
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    /// Black or white depending on the bubble fill's luminance.
    var autoTextColor: NSColor {
        guard let c = color.usingColorSpace(.sRGB) else { return .white }
        let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return lum > 0.62 ? NSColor(white: 0.12, alpha: 1) : .white
    }

    // TextEditable
    var editFont: NSFont { get { font } set { font = newValue } }
    var editColor: NSColor { get { autoTextColor } set { } }
    var textEditRect: CGRect { rect.insetBy(dx: 10, dy: 8) }
}

// MARK: - Text

final class TextAnnotation: Annotation, TextEditable {
    var origin: CGPoint         // top-left in image space (see draw)
    var string: String
    var font: NSFont
    var backgroundColor: NSColor = .clear

    init(origin: CGPoint, string: String, font: NSFont) {
        self.origin = origin; self.string = string; self.font = font
    }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color]
    }

    var attributedString: NSAttributedString {
        NSAttributedString(string: string.isEmpty ? " " : string, attributes: attributes)
    }

    var textSize: CGSize {
        let s = attributedString.size()
        return CGSize(width: ceil(s.width) + 8, height: ceil(s.height) + 4)
    }

    override var bounds: CGRect {
        let s = textSize
        return CGRect(x: origin.x, y: origin.y - s.height, width: s.width, height: s.height)
    }

    override func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
    }

    override func translate(by d: CGVector) {
        origin.x += d.dx; origin.y += d.dy
    }

    override func clone() -> Annotation {
        let t = TextAnnotation(origin: origin, string: string, font: font)
        t.color = color; t.lineWidth = lineWidth; t.backgroundColor = backgroundColor
        return t
    }

    // TextEditable
    var editFont: NSFont { get { font } set { font = newValue } }
    var editColor: NSColor { get { color } set { color = newValue } }
    var textEditRect: CGRect { bounds }

    override func draw(env: RenderEnv) {
        let b = bounds
        if backgroundColor.alphaComponent > 0.01 {
            let bg = NSBezierPath(roundedRect: b.insetBy(dx: -2, dy: -1),
                                  xRadius: 3, yRadius: 3)
            backgroundColor.setFill(); bg.fill()
        }
        let drawPoint = CGPoint(x: b.minX + 4, y: b.minY + 2)
        attributedString.draw(at: drawPoint)
    }
}

// MARK: - Blur

enum BlurStyle: Int, CaseIterable {
    case blur       // strong gaussian
    case pixelate   // large mosaic blocks
    case solid      // opaque bar — unrecoverable redaction

    var title: String {
        switch self {
        case .blur:     return "Blur"
        case .pixelate: return "Pixelate"
        case .solid:    return "Solid"
        }
    }
    var symbolName: String {
        switch self {
        case .blur:     return "drop"
        case .pixelate: return "square.grid.3x3.fill"
        case .solid:    return "rectangle.fill"
        }
    }
}

/// A redaction region. Defaults are tuned so text becomes genuinely
/// unreadable (weak blur/pixelation can be reversed, so we err strong).
final class BlurAnnotation: Annotation {
    var rect: CGRect
    var style: BlurStyle
    /// 0.2 … 1.0 — strength, scaled against the region size.
    var amount: CGFloat = 0.75

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(rect: CGRect, style: BlurStyle) {
        self.rect = rect; self.style = style
    }

    override var bounds: CGRect { rect }

    override func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        rect.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
    }

    override func translate(by d: CGVector) {
        rect.origin.x += d.dx; rect.origin.y += d.dy
    }

    override func resizeHandles() -> [CGPoint] { Annotation.rectHandles(rect) }
    override func moveHandle(_ index: Int, to p: CGPoint) {
        rect = Annotation.resizedRect(rect, handle: index, to: p)
    }

    override func clone() -> Annotation {
        let b = BlurAnnotation(rect: rect, style: style)
        b.amount = amount
        return b
    }

    override func draw(env: RenderEnv) {
        let r = rect.integral
        guard r.width > 2, r.height > 2 else { return }

        if style == .solid {
            fillSolid(r)
            return
        }
        guard let base = env.baseCGImage else { fillSolid(r); return }

        let minSide = min(r.width, r.height)
        let region = CIImage(cgImage: base).cropped(to: r).clampedToExtent()

        let filter: CIFilter?
        switch style {
        case .pixelate:
            // Blocks scale with the region's short side so text becomes
            // genuinely unreadable (a whole character collapses into ~1 block).
            let scale = max(24, minSide * (0.55 + amount * 0.45))
            filter = CIFilter(name: "CIPixellate", parameters: [
                kCIInputImageKey: region,
                kCIInputScaleKey: scale,
                kCIInputCenterKey: CIVector(x: r.midX, y: r.midY),
            ])
        case .blur:
            // Very heavy gaussian — radius near the region height smears glyphs.
            let radius = max(14, minSide * (0.5 + amount * 0.6))
            filter = CIFilter(name: "CIGaussianBlur", parameters: [
                kCIInputImageKey: region,
                kCIInputRadiusKey: radius,
            ])
        case .solid:
            filter = nil
        }

        guard let out = filter?.outputImage?.cropped(to: r),
              let cg = BlurAnnotation.ciContext.createCGImage(out, from: r) else {
            fillSolid(r); return
        }

        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(rect: r)
        clip.addClip()
        NSImage(cgImage: cg, size: r.size).draw(in: r, from: .zero,
                                                operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func fillSolid(_ r: CGRect) {
        let fill = NSColor(calibratedWhite: 0.12, alpha: 1.0)
        fill.setFill()
        NSBezierPath(rect: r).fill()
    }
}
