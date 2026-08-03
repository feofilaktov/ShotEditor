import AppKit

enum ToolKind: Int, CaseIterable {
    case select
    case arrow
    case shape
    case pen
    case highlighter
    case text
    case callout
    case number
    case blur
    case crop

    var title: String {
        switch self {
        case .select:      return "Select"
        case .arrow:       return "Arrow"
        case .shape:       return "Shape"
        case .pen:         return "Pen"
        case .highlighter: return "Highlighter"
        case .text:        return "Text"
        case .callout:     return "Callout"
        case .number:      return "Step number"
        case .blur:        return "Redaction"
        case .crop:        return "Crop"
        }
    }

    var symbolName: String {
        switch self {
        case .select:      return "cursorarrow"
        case .arrow:       return "arrow.up.right"
        case .shape:       return "square.on.circle"
        case .pen:         return "pencil.tip"
        case .highlighter: return "highlighter"
        case .text:        return "textformat"
        case .callout:     return "bubble.left"
        case .number:      return "1.circle.fill"
        case .blur:        return "drop.halffull"
        case .crop:        return "crop"
        }
    }

    /// Single-key shortcut.
    var shortcut: String {
        switch self {
        case .select:      return "v"
        case .arrow:       return "a"
        case .shape:       return "s"
        case .pen:         return "p"
        case .highlighter: return "h"
        case .text:        return "t"
        case .callout:     return "u"
        case .number:      return "n"
        case .blur:        return "b"
        case .crop:        return "c"
        }
    }
}

/// Shared, mutable settings edited by the accessory panels.
final class ToolSettings {
    var current: ToolKind = .arrow

    var color: NSColor = Palette.defaultColor
    var lineWidth: CGFloat = 4

    var arrowStyle: ArrowStyle = .filled
    var shapeKind: ShapeKind = .rect
    var shapeFilled: Bool = false
    var dashed: Bool = false

    var blurStyle: BlurStyle = .pixelate
    var blurAmount: CGFloat = 0.75

    // Step numbers (auto-incrementing)
    var nextNumber: Int = 1

    // Text
    var fontName: String = "Helvetica"
    var fontSize: CGFloat = 28
    var textBackground: NSColor = .clear

    var font: NSFont {
        NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
    }

    /// The fonts offered in the text accessory (originals used Arial / Comic
    /// Sans / Georgia; we offer widely-available equivalents).
    static let availableFonts: [(label: String, name: String)] = [
        ("Helvetica", "Helvetica"),
        ("Arial", "Arial"),
        ("Georgia", "Georgia"),
        ("Courier", "Courier"),
        ("Comic Sans MS", "Comic Sans MS"),
    ]

    static let lineWidths: [CGFloat] = [2, 4, 8, 14]
}
