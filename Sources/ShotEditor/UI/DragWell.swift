import AppKit

/// A small control you can drag out of the window to export the flattened
/// screenshot as a file into Finder or any app that accepts image drops.
final class DragWell: NSView, NSDraggingSource {

    var imageProvider: (() -> NSImage?)?
    var filenameProvider: (() -> String)?

    private var mouseDownPoint: NSPoint?
    private let label = NSTextField(labelWithString: "Drag out")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Theme.smallCorner
        layer?.backgroundColor = Theme.segmentTrack.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Drag out")
        icon.contentTintColor = Theme.secondaryText
        label.font = Theme.caption
        label.textColor = Theme.secondaryText

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            heightAnchor.constraint(equalToConstant: 22),
        ])
        toolTip = "Drag this to Finder or another app to export the image"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { mouseDownPoint = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let now = event.locationInWindow
        if hypot(now.x - start.x, now.y - start.y) < 6 { return }
        mouseDownPoint = nil
        beginDrag(event)
    }

    private func beginDrag(_ event: NSEvent) {
        guard let image = imageProvider?(),
              let data = ImageExport.data(from: image, format: .png) else { return }
        let name = filenameProvider?() ?? "Screenshot.png"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        do { try data.write(to: url) } catch { return }

        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let thumb = thumbnail(image)
        let dragFrame = CGRect(x: 0, y: 0, width: thumb.size.width, height: thumb.size.height)
        item.setDraggingFrame(dragFrame, contents: thumb)

        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func thumbnail(_ image: NSImage) -> NSImage {
        let maxDim: CGFloat = 160
        let s = image.size
        let scale = min(maxDim / max(s.width, 1), maxDim / max(s.height, 1), 1)
        let size = CGSize(width: s.width * scale, height: s.height * scale)
        let out = NSImage(size: size)
        out.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: size),
                   from: .zero, operation: .copy, fraction: 0.9)
        out.unlockFocus()
        return out
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
