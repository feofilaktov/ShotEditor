import AppKit
import UniformTypeIdentifiers

/// Local-only export: save to a file the user picks, or copy to the clipboard.
/// No cloud, no account, no upload.
enum ImageExport {

    enum Format: Int {
        case png, jpeg
        var utType: UTType { self == .png ? .png : .jpeg }
        var ext: String { self == .png ? "png" : "jpg" }
        var title: String { self == .png ? "PNG" : "JPEG" }
    }

    static func data(from image: NSImage, format: Format) -> Data? {
        // Prefer an existing bitmap rep (exact pixels); fall back to a CGImage.
        // Avoids the backing-scale doubling of NSImage.cgImage(forProposedRect:).
        let rep: NSBitmapImageRep
        if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            rep = bitmap
        } else if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            rep = NSBitmapImageRep(cgImage: cg)
        } else {
            return nil
        }
        switch format {
        case .png:
            return rep.representation(using: .png, properties: [:])
        case .jpeg:
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        }
    }

    /// Prompt for a location + format (PNG or JPEG) and save.
    @discardableResult
    static func saveWithPanel(_ image: NSImage,
                              suggestedName: String,
                              defaultDirectory: URL?) -> URL? {
        let panel = NSSavePanel()
        let baseName = (suggestedName as NSString).deletingPathExtension

        let accessory = FormatAccessory(panel: panel, baseName: baseName)
        panel.accessoryView = accessory.view
        panel.allowedContentTypes = [Format.png.utType]
        panel.nameFieldStringValue = "\(baseName).png"
        if let defaultDirectory { panel.directoryURL = defaultDirectory }
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let format: Format = (url.pathExtension.lowercased().hasPrefix("jp")) ? .jpeg : .png
        guard let data = data(from: image, format: format) else { return nil }
        do {
            try data.write(to: url)
            return url
        } catch {
            NSLog("Save failed: \(error)")
            presentError(error)
            return nil
        }
    }

    static func copyToPasteboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = data(from: image, format: .png) {
            pb.setData(png, forType: .png)
        }
        pb.writeObjects([image])
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

/// Small controller for the "File Format: PNG / JPEG" popup inside the save panel.
private final class FormatAccessory: NSObject {
    let view: NSView
    private weak var panel: NSSavePanel?
    private let baseName: String
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)

    init(panel: NSSavePanel, baseName: String) {
        self.panel = panel
        self.baseName = baseName
        let label = NSTextField(labelWithString: "File Format:")
        popup.addItems(withTitles: [ImageExport.Format.png.title, ImageExport.Format.jpeg.title])
        popup.selectItem(at: 0)

        let stack = NSStackView(views: [label, popup])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])
        self.view = container
        super.init()
        popup.target = self
        popup.action = #selector(changed)
    }

    @objc private func changed() {
        let format = ImageExport.Format(rawValue: popup.indexOfSelectedItem) ?? .png
        panel?.allowedContentTypes = [format.utType]
        panel?.nameFieldStringValue = "\(baseName).\(format.ext)"
    }
}
