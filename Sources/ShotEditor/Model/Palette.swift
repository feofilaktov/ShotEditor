import AppKit

/// The fixed color palette, mirroring the original editor
/// (black, blue, gray, green, magenta, red, white, yellow) plus a
/// transparent slot used for text backgrounds.
enum Palette {

    struct Swatch {
        let name: String
        let color: NSColor
    }

    static let swatches: [Swatch] = [
        Swatch(name: "red",     color: NSColor(srgbRed: 0.90, green: 0.16, blue: 0.16, alpha: 1)),
        Swatch(name: "yellow",  color: NSColor(srgbRed: 1.00, green: 0.80, blue: 0.00, alpha: 1)),
        Swatch(name: "green",   color: NSColor(srgbRed: 0.20, green: 0.72, blue: 0.30, alpha: 1)),
        Swatch(name: "blue",    color: NSColor(srgbRed: 0.13, green: 0.47, blue: 0.95, alpha: 1)),
        Swatch(name: "magenta", color: NSColor(srgbRed: 0.85, green: 0.16, blue: 0.72, alpha: 1)),
        Swatch(name: "black",   color: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1)),
        Swatch(name: "gray",    color: NSColor(srgbRed: 0.55, green: 0.56, blue: 0.58, alpha: 1)),
        Swatch(name: "white",   color: NSColor.white),
    ]

    /// Transparent swatch, only offered as a text-background option.
    static let transparent = Swatch(name: "transparent", color: .clear)

    static var defaultColor: NSColor { swatches[0].color }   // red

    static let colors: [NSColor] = swatches.map { $0.color }
}
