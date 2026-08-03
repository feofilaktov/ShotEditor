import AppKit

/// An icon-only button with a rounded highlight for hover and selected states.
final class IconButton: NSButton {

    var isSelectedTool = false { didSet { updateAppearance() } }
    private var hovering = false { didSet { updateAppearance() } }
    private var accentTint = false

    init(symbol: String, accessibility: String, accentTint: Bool = false) {
        super.init(frame: .zero)
        self.accentTint = accentTint
        wantsLayer = true
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility)?
            .withSymbolConfiguration(cfg)
        contentTintColor = .labelColor
        toolTip = accessibility
        layer?.cornerRadius = Theme.smallCorner
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Theme.toolButtonSize).isActive = true
        heightAnchor.constraint(equalToConstant: Theme.toolButtonSize).isActive = true
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

    private func updateAppearance() {
        if isSelectedTool {
            layer?.backgroundColor = Theme.accent.cgColor
            contentTintColor = .white
        } else if hovering {
            layer?.backgroundColor = Theme.controlHoverFill.cgColor
            contentTintColor = accentTint ? Theme.accent : .labelColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            contentTintColor = accentTint ? Theme.accent : .labelColor
        }
    }
}

/// A single-selection row of small segments (icons, text, or size dots)
/// inside a rounded track.
final class IconSegmentedBar: NSView {

    enum Item {
        case symbol(String)
        case text(String)
        case dot(CGFloat)   // filled circle of given diameter
    }

    var onSelect: ((Int) -> Void)?
    private var buttons: [NSButton] = []
    private(set) var selectedIndex: Int

    init(items: [Item], selected: Int) {
        self.selectedIndex = selected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.smallCorner
        layer?.backgroundColor = Theme.segmentTrack.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        for (i, item) in items.enumerated() {
            let b = NSButton()
            b.wantsLayer = true
            b.isBordered = false
            b.bezelStyle = .regularSquare
            b.title = ""
            b.imagePosition = .imageOnly
            b.tag = i
            b.target = self
            b.action = #selector(tap(_:))
            b.layer?.cornerRadius = 4
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: Theme.controlHeight - 6).isActive = true
            b.widthAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true

            switch item {
            case .symbol(let name):
                let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                b.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(cfg)
                b.contentTintColor = .labelColor
            case .text(let t):
                b.title = t
                b.font = Theme.caption
                b.contentTintColor = .labelColor
            case .dot(let d):
                b.image = IconSegmentedBar.dotImage(diameter: d)
            }
            buttons.append(b)
            stack.addArrangedSubview(b)
        }
        highlight(selected)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tap(_ sender: NSButton) {
        selectedIndex = sender.tag
        highlight(sender.tag)
        onSelect?(sender.tag)
    }

    private func highlight(_ index: Int) {
        for (i, b) in buttons.enumerated() {
            let on = (i == index)
            b.layer?.backgroundColor = on ? NSColor.controlColor.cgColor : NSColor.clear.cgColor
            if on { b.layer?.shadowOpacity = 0.12; b.layer?.shadowRadius = 2
                    b.layer?.shadowOffset = CGSize(width: 0, height: -1) }
            else  { b.layer?.shadowOpacity = 0 }
            b.contentTintColor = on ? Theme.accent : .labelColor
        }
    }

    private static func dotImage(diameter: CGFloat) -> NSImage {
        let side: CGFloat = 22
        let img = NSImage(size: CGSize(width: side, height: side))
        img.lockFocus()
        NSColor.labelColor.setFill()
        let r = CGRect(x: (side - diameter)/2, y: (side - diameter)/2,
                       width: diameter, height: diameter)
        NSBezierPath(ovalIn: r).fill()
        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}

/// Text-button factory helpers.
enum Buttons {
    static func primary(_ title: String, target: Any?, action: Selector, key: String = "") -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .large
        b.bezelColor = Theme.accent
        b.contentTintColor = .white
        b.keyEquivalent = key
        if !key.isEmpty { b.keyEquivalentModifierMask = .command }
        b.font = .systemFont(ofSize: 13, weight: .semibold)
        return b
    }

    static func secondary(_ title: String, target: Any?, action: Selector, key: String = "") -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .large
        b.keyEquivalent = key
        if !key.isEmpty { b.keyEquivalentModifierMask = .command }
        return b
    }
}
