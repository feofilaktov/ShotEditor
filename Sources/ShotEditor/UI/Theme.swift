import AppKit

/// Central design tokens so the whole app stays visually consistent.
enum Theme {

    // Metrics
    static let toolbarHeight: CGFloat = 52
    static let inspectorHeight: CGFloat = 46
    static let statusHeight: CGFloat = 28
    static let trafficLightInset: CGFloat = 80      // space for window controls

    static let controlHeight: CGFloat = 30
    static let toolButtonSize: CGFloat = 32
    static let corner: CGFloat = 8
    static let smallCorner: CGFloat = 6
    static let hpad: CGFloat = 14
    static let gap: CGFloat = 8

    static let swatchSize: CGFloat = 18

    // Colors (resolve against the current appearance)
    static var accent: NSColor { .controlAccentColor }
    static var hair: NSColor { NSColor.separatorColor }
    static var secondaryText: NSColor { .secondaryLabelColor }

    /// Neutral canvas backdrop behind the image.
    static var canvasBackdrop: NSColor {
        NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(white: 0.11, alpha: 1) : NSColor(white: 0.92, alpha: 1)
        }
    }

    /// Subtle fill for hovered/selected controls.
    static var controlHoverFill: NSColor { NSColor.labelColor.withAlphaComponent(0.08) }
    static var segmentTrack: NSColor { NSColor.labelColor.withAlphaComponent(0.06) }

    // Fonts
    static var caption: NSFont { .systemFont(ofSize: 11, weight: .medium) }
    static var label: NSFont { .systemFont(ofSize: 12) }

    static func makeBar(material: NSVisualEffectView.Material) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .withinWindow
        v.state = .active
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
