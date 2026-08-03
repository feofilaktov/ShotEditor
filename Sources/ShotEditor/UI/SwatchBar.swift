import AppKit

/// A horizontal row of circular color swatches with a selection ring.
final class SwatchBar: NSView {

    var onPick: ((NSColor) -> Void)?
    private var dots: [SwatchDot] = []
    private let includeTransparent: Bool

    init(selected: NSColor, includeTransparent: Bool = false) {
        self.includeTransparent = includeTransparent
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build(selected: selected)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var swatches: [Palette.Swatch] {
        includeTransparent ? [Palette.transparent] + Palette.swatches : Palette.swatches
    }

    private func build(selected: NSColor) {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        for (idx, sw) in swatches.enumerated() {
            let dot = SwatchDot(color: sw.color,
                                transparent: sw.name == "transparent")
            dot.onClick = { [weak self] in self?.select(idx) }
            dots.append(dot)
            stack.addArrangedSubview(dot)
        }
        highlight(matching: selected)
    }

    private func select(_ index: Int) {
        for (i, d) in dots.enumerated() { d.isSelected = (i == index) }
        onPick?(swatches[index].color)
    }

    private func highlight(matching color: NSColor) {
        if let idx = swatches.firstIndex(where: { approx($0.color, color) }) {
            for (i, d) in dots.enumerated() { d.isSelected = (i == idx) }
        }
    }

    private func approx(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return a == b }
        return abs(x.redComponent - y.redComponent) < 0.02 &&
               abs(x.greenComponent - y.greenComponent) < 0.02 &&
               abs(x.blueComponent - y.blueComponent) < 0.02 &&
               abs(x.alphaComponent - y.alphaComponent) < 0.02
    }
}

final class SwatchDot: NSView {
    var onClick: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true } }
    private let color: NSColor
    private let transparent: Bool
    private var hovering = false { didSet { needsDisplay = true } }

    init(color: NSColor, transparent: Bool) {
        self.color = color
        self.transparent = transparent
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let s = Theme.swatchSize + 8
        widthAnchor.constraint(equalToConstant: s).isActive = true
        heightAnchor.constraint(equalToConstant: s).isActive = true
        toolTip = transparent ? "Transparent" : nil
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInActiveApp],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let d = Theme.swatchSize
        let rect = CGRect(x: (bounds.width - d)/2, y: (bounds.height - d)/2, width: d, height: d)

        // selection / hover ring
        if isSelected || hovering {
            let ringRect = rect.insetBy(dx: -4, dy: -4)
            let ring = NSBezierPath(ovalIn: ringRect)
            (isSelected ? Theme.accent : Theme.accent.withAlphaComponent(0.35)).setStroke()
            ring.lineWidth = isSelected ? 2 : 1.5
            ring.stroke()
        }

        let circle = NSBezierPath(ovalIn: rect)
        if transparent {
            NSColor.white.setFill(); circle.fill()
            NSColor.systemRed.setStroke()
            let slash = NSBezierPath()
            slash.move(to: CGPoint(x: rect.minX + 3, y: rect.minY + 3))
            slash.line(to: CGPoint(x: rect.maxX - 3, y: rect.maxY - 3))
            slash.lineWidth = 2; slash.stroke()
        } else {
            color.setFill(); circle.fill()
        }
        // hairline border so white/light swatches stay visible
        NSColor.black.withAlphaComponent(0.15).setStroke()
        let border = NSBezierPath(ovalIn: rect); border.lineWidth = 1; border.stroke()
    }
}
