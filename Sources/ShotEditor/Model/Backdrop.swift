import AppKit

/// Export "beautify" frame drawn around the screenshot: padding, a background
/// (solid or gradient), a drop shadow and rounded corners.
struct Backdrop {
    var enabled = false
    var padding: CGFloat = 64
    var cornerRadius: CGFloat = 16
    var shadow = true
    var style: Style = .oceanGradient

    enum Style: Int, CaseIterable {
        case solid, oceanGradient, sunsetGradient, mono

        var title: String {
            switch self {
            case .solid:          return "Solid"
            case .oceanGradient:  return "Ocean"
            case .sunsetGradient: return "Sunset"
            case .mono:           return "Mono"
            }
        }

        var colors: [NSColor] {
            switch self {
            case .solid:          return [NSColor(srgbRed: 0.20, green: 0.55, blue: 0.95, alpha: 1)]
            case .oceanGradient:  return [NSColor(srgbRed: 0.30, green: 0.62, blue: 0.98, alpha: 1),
                                          NSColor(srgbRed: 0.56, green: 0.35, blue: 0.95, alpha: 1)]
            case .sunsetGradient: return [NSColor(srgbRed: 0.98, green: 0.58, blue: 0.35, alpha: 1),
                                          NSColor(srgbRed: 0.95, green: 0.32, blue: 0.55, alpha: 1)]
            case .mono:           return [NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1)]
            }
        }
    }

    /// Total size once the padding is added around `imageSize`.
    func totalSize(for imageSize: CGSize) -> CGSize {
        guard enabled else { return imageSize }
        return CGSize(width: imageSize.width + padding * 2,
                      height: imageSize.height + padding * 2)
    }

    /// Origin of the screenshot inside the padded frame.
    func imageOrigin() -> CGPoint {
        enabled ? CGPoint(x: padding, y: padding) : .zero
    }

    /// Fill the background across `rect` (view or bitmap space).
    func drawBackground(in rect: CGRect) {
        let colors = style.colors
        if colors.count == 1 {
            colors[0].setFill()
            rect.fill()
        } else if let grad = NSGradient(colors: colors) {
            grad.draw(in: rect, angle: 45)
        }
    }
}
