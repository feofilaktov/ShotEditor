import AppKit

/// Renders the app icon programmatically so we don't ship binary art.
enum IconMaker {

    static func render(size: CGFloat = 1024) -> NSImage {
        let img = NSImage(size: CGSize(width: size, height: size))
        img.lockFocus()

        // Rounded-square gradient tile (macOS Big Sur style, slight inset).
        let inset = size * 0.06
        let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let radius = rect.width * 0.225
        let tile = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let grad = NSGradient(colors: [
            NSColor(srgbRed: 0.36, green: 0.66, blue: 0.99, alpha: 1),
            NSColor(srgbRed: 0.55, green: 0.35, blue: 0.96, alpha: 1),
        ])
        grad?.draw(in: tile, angle: -60)

        // A bold arrow (the signature annotation) + selection frame.
        let frame = rect.insetBy(dx: rect.width * 0.24, dy: rect.height * 0.24)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let sel = NSBezierPath(roundedRect: frame, xRadius: 14, yRadius: 14)
        sel.lineWidth = size * 0.018
        sel.setLineDash([size * 0.05, size * 0.035], count: 2, phase: 0)
        sel.stroke()

        let start = CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.36)
        let end   = CGPoint(x: rect.minX + rect.width * 0.66, y: rect.minY + rect.height * 0.64)
        let shaft = NSBezierPath()
        shaft.move(to: start); shaft.line(to: end)
        shaft.lineWidth = size * 0.05
        shaft.lineCapStyle = .round
        NSColor.white.setStroke(); shaft.stroke()

        // Arrow head
        let angle = atan2(end.y - start.y, end.x - start.x)
        let hl = size * 0.14
        let a = CGFloat.pi / 6
        let p1 = CGPoint(x: end.x - hl * cos(angle - a), y: end.y - hl * sin(angle - a))
        let p2 = CGPoint(x: end.x - hl * cos(angle + a), y: end.y - hl * sin(angle + a))
        let head = NSBezierPath()
        head.move(to: p1); head.line(to: end); head.line(to: p2); head.close()
        NSColor.white.setFill(); head.fill()

        img.unlockFocus()
        return img
    }

    @discardableResult
    static func writePNG(to path: String, size: CGFloat = 1024) -> Bool {
        let image = render(size: size)
        guard let data = ImageExport.data(from: image, format: .png) else { return false }
        do { try data.write(to: URL(fileURLWithPath: path)); return true }
        catch { NSLog("icon write failed: \(error)"); return false }
    }
}
