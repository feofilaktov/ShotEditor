import AppKit
import Vision
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var editors: [EditorWindowController] = []
    private let hotkeys = HotkeyManager()

    private var appearanceMenu: NSMenu?
    private var recentMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applySavedAppearance()
        setupMainMenu()
        setupStatusItem()
        registerHotkeys()

        if CommandLine.arguments.contains("--selftest") {
            AppDelegate.runSelfTest()
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }

        if CommandLine.arguments.contains("--showcase") {
            AppDelegate.runShowcase()
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }

        if CommandLine.arguments.contains("--captest") {
            captureFullScreen()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                if let ed = self?.editors.last {
                    NSLog("captest: editor opened, image \(ed.debugImageSize)")
                }
                self?.snapshotFrontWindow(to: "/tmp/shotedit_verify/captest.png")
            }
        }

        if CommandLine.arguments.contains("--demo") {
            openEditor(with: AppDelegate.demoImage())
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                if CommandLine.arguments.contains("--zoom2") {
                    self?.editors.last?.debugSetZoom(2.0)
                }
                if CommandLine.arguments.contains("--crop") {
                    self?.editors.last?.debugBeginCrop()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.snapshotFrontWindow(to: "/tmp/shotedit_verify/window.png")
                }
            }
        }
    }

    /// A clean, realistic scene to judge real-world quality of each tool.
    static func runShowcase() {
        let W = 1000, H = 620
        let base = NSImage(size: CGSize(width: W, height: H))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = CGSize(width: W, height: H)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
        NSColor(calibratedWhite: 0.99, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: W, height: H).fill()
        // A faux "document" with lines of text (y is bottom-up).
        let lines = ["Invoice #2026-0042", "Account: 4916 2534 8871 0090",
                     "Name: Jane Appleseed", "Total due: $1,240.00", "Status: PAID"]
        for (i, line) in lines.enumerated() {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 30, weight: i == 0 ? .bold : .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1)]
            (line as NSString).draw(at: CGPoint(x: 60, y: H - 90 - i * 60), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        base.addRepresentation(rep)

        let doc = EditorDocument(image: base)
        let s = doc.imageSize
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        func topY(_ py: CGFloat) -> CGFloat { s.height - py }   // convert screen-top y to image y

        // Redact the account number (pixelate) and cover the total with solid.
        let acct = BlurAnnotation(rect: CGRect(x: 205, y: topY(175), width: 360, height: 40), style: .pixelate)
        acct.amount = 0.85; doc.add(acct)

        // Highlight the "PAID" status line.
        let hl = PenAnnotation(points: (0...20).map { P(60 + CGFloat($0) * 6, topY(365)) })
        hl.isHighlighter = true; hl.color = Palette.swatches[1].color; hl.lineWidth = 34
        doc.add(hl)

        // Arrow pointing at the total.
        let arrow = ArrowAnnotation(start: P(720, topY(360)), end: P(360, topY(305)), style: .filled)
        arrow.color = Palette.swatches[0].color; arrow.lineWidth = 6
        doc.add(arrow)

        // Numbered steps down the right side.
        for (i, py) in [90, 150, 210].enumerated() {
            let n = NumberAnnotation(center: P(900, topY(CGFloat(py))), number: i + 1, diameter: 44)
            n.color = Palette.swatches[3].color; doc.add(n)
        }

        // A rounded-rect emphasis around the name.
        let box = ShapeAnnotation(kind: .roundedRect, p0: P(50, topY(300)), p1: P(430, topY(245)))
        box.color = Palette.swatches[2].color; box.lineWidth = 4; doc.add(box)

        // Callout.
        let callout = CalloutAnnotation(rect: CGRect(x: 560, y: topY(560), width: 320, height: 90),
                                        tailTip: P(470, topY(500)), font: .systemFont(ofSize: 26, weight: .semibold))
        callout.color = Palette.swatches[4].color; callout.string = "Please verify this total"
        doc.add(callout)

        doc.backdrop.enabled = true
        doc.backdrop.style = .oceanGradient
        doc.backdrop.padding = 70
        doc.backdrop.cornerRadius = 18

        if let data = ImageExport.data(from: Renderer.flattenForExport(doc), format: .png) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/shotedit_verify/showcase.png"))
            NSLog("showcase written")
        }
    }

    /// Headless check of the annotation rendering pipeline.
    static func runSelfTest() {
        let doc = EditorDocument(image: demoImage())
        let s = doc.imageSize
        func P(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: fx * s.width, y: fy * s.height)
        }

        let arrow = ArrowAnnotation(start: P(0.10, 0.30), end: P(0.34, 0.55), style: .filled)
        arrow.color = Palette.swatches[0].color; arrow.lineWidth = 10
        doc.add(arrow)

        let rect = ShapeAnnotation(kind: .roundedRect, p0: P(0.45, 0.30), p1: P(0.72, 0.55))
        rect.color = Palette.swatches[2].color; rect.lineWidth = 8
        doc.add(rect)

        let ellipse = ShapeAnnotation(kind: .ellipse, p0: P(0.76, 0.32), p1: P(0.93, 0.55))
        ellipse.color = Palette.swatches[3].color; ellipse.lineWidth = 8
        doc.add(ellipse)

        let star = ShapeAnnotation(kind: .star, p0: P(0.10, 0.62), p1: P(0.22, 0.82))
        star.color = Palette.swatches[1].color; star.filled = true
        doc.add(star)

        let pen = PenAnnotation(points: (0..<60).map {
            P(0.30 + CGFloat($0) * 0.008, 0.60 + sin(CGFloat($0) / 4) * 0.05)
        })
        pen.color = Palette.swatches[4].color; pen.lineWidth = 7
        doc.add(pen)

        let text = TextAnnotation(origin: P(0.10, 0.95),
                                  string: "Annotated!", font: NSFont.boldSystemFont(ofSize: 44))
        text.color = .white
        text.backgroundColor = Palette.swatches[0].color
        doc.add(text)

        // Numbered step markers
        for (i, fx) in [0.50, 0.60, 0.70].enumerated() {
            let n = NumberAnnotation(center: P(CGFloat(fx), 0.30), number: i + 1, diameter: 56)
            n.color = Palette.swatches[3].color
            doc.add(n)
        }

        // Highlighter over the title
        let hl = PenAnnotation(points: (0..<30).map { P(0.10 + CGFloat($0) * 0.012, 0.86) })
        hl.isHighlighter = true; hl.color = Palette.swatches[1].color; hl.lineWidth = 46
        doc.add(hl)

        // Dashed rectangle
        let dash = ShapeAnnotation(kind: .rect, p0: P(0.78, 0.62), p1: P(0.95, 0.82))
        dash.color = Palette.swatches[0].color; dash.lineWidth = 5; dash.dashed = true
        doc.add(dash)

        // Callout bubble
        let callout = CalloutAnnotation(
            rect: CGRect(x: s.width * 0.30, y: s.height * 0.04, width: s.width * 0.30, height: s.height * 0.12),
            tailTip: P(0.40, -0.02 + 0.02), font: NSFont.boldSystemFont(ofSize: 26))
        callout.rect = CGRect(x: s.width * 0.30, y: s.height * 0.05, width: s.width * 0.30, height: s.height * 0.12)
        callout.tailTip = CGPoint(x: s.width * 0.36, y: s.height * 0.01)
        callout.color = Palette.swatches[3].color
        callout.string = "Look here!"
        doc.add(callout)

        // Blur over the title text (top of the image).
        let blur = BlurAnnotation(rect: CGRect(x: s.width * 0.10, y: s.height * 0.68,
                                               width: s.width * 0.42, height: s.height * 0.16),
                                  style: .pixelate)
        blur.amount = 0.8
        doc.add(blur)

        let flat = Renderer.flatten(doc)
        if let data = ImageExport.data(from: flat, format: .png) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/shotedit_verify/selftest.png"))
            NSLog("selftest image written")
        }

        // Redaction strength check: cover the title with each style and crop.
        let titleRect = CGRect(x: s.width * 0.08, y: s.height * 0.68,
                               width: s.width * 0.60, height: s.height * 0.16)
        for style in BlurStyle.allCases {
            let d = EditorDocument(image: demoImage())
            let b = BlurAnnotation(rect: titleRect, style: style); b.amount = 0.75
            d.add(b)
            let f = Renderer.flatten(d)
            let c = Renderer.crop(f, to: titleRect.insetBy(dx: -20, dy: -20))
            if let data = ImageExport.data(from: c, format: .png) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/shotedit_verify/redact-\(style.title).png"))
            }
        }

        // Backdrop export
        doc.backdrop.enabled = true
        doc.backdrop.style = .oceanGradient
        doc.backdrop.padding = 80
        doc.backdrop.cornerRadius = 20
        if let data = ImageExport.data(from: Renderer.flattenForExport(doc), format: .png) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/shotedit_verify/backdrop.png"))
        }
        doc.backdrop.enabled = false

        // OCR check
        if let cg = AppDelegate.demoImage().cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
            let lines = (req.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            NSLog("OCR result: \(lines)")
        }

        // Image transforms
        if let rot = Renderer.rotated(doc, clockwise: true),
           let data = ImageExport.data(from: rot, format: .png) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/shotedit_verify/rotated.png"))
        }
        if let sc = Renderer.scaled(doc, to: 300),
           let data = ImageExport.data(from: sc, format: .png) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/shotedit_verify/scaled.png"))
        }

        // Also exercise crop: crop the center and save.
        let cropped = Renderer.crop(flat, to: CGRect(x: 100, y: 100, width: 700, height: 380))
        if let data = ImageExport.data(from: cropped, format: .png) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/shotedit_verify/selftest-crop.png"))
            NSLog("selftest crop written")
        }
    }

    /// Debug helper: render the front editor window to a PNG.
    private func snapshotFrontWindow(to path: String) {
        guard let window = editors.last?.window,
              let view = window.contentView else { return }
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            NSLog("snapshot written to \(path)")
        }
    }

    /// A synthetic image so the editor UI can be exercised without capturing.
    static func demoImage() -> NSImage {
        let size = CGSize(width: 900, height: 560)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        let grad = NSGradient(colors: [NSColor.systemTeal, NSColor.systemPurple])
        grad?.draw(in: CGRect(x: 60, y: 60, width: 780, height: 300), angle: 30)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 40),
            .foregroundColor: NSColor.white,
        ]
        "ShotEditor demo canvas".draw(at: CGPoint(x: 90, y: 420), withAttributes: attrs)
        img.unlockFocus()
        return img
    }

    // A minimal main menu so standard editing shortcuts (⌘Z/⌘C/⌘V/⌘A) and
    // undo/redo work inside the editor windows.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ShotEditor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Save…", action: #selector(EditorWindowController.saveDocument(_:)), keyEquivalent: "s")
        fileMenu.addItem(.separator())
        let close = fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        close.keyEquivalentModifierMask = .command
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let copyImage = editMenu.addItem(withTitle: "Copy Image to Clipboard",
                                         action: #selector(EditorWindowController.copyImageToClipboard(_:)),
                                         keyEquivalent: "c")
        copyImage.keyEquivalentModifierMask = [.command, .shift]
        let ocr = editMenu.addItem(withTitle: "Copy Text (OCR)",
                                   action: #selector(EditorWindowController.copyTextOCR(_:)), keyEquivalent: "t")
        ocr.keyEquivalentModifierMask = [.command, .shift]
        editItem.submenu = editMenu

        let imageItem = NSMenuItem()
        mainMenu.addItem(imageItem)
        let imageMenu = NSMenu(title: "Image")
        let rr = imageMenu.addItem(withTitle: "Rotate Right", action: #selector(EditorWindowController.rotateRight(_:)), keyEquivalent: "r")
        rr.keyEquivalentModifierMask = [.command]
        let rl = imageMenu.addItem(withTitle: "Rotate Left", action: #selector(EditorWindowController.rotateLeft(_:)), keyEquivalent: "r")
        rl.keyEquivalentModifierMask = [.command, .shift]
        imageMenu.addItem(withTitle: "Flip Horizontal", action: #selector(EditorWindowController.flipHorizontal(_:)), keyEquivalent: "")
        imageMenu.addItem(withTitle: "Flip Vertical", action: #selector(EditorWindowController.flipVertical(_:)), keyEquivalent: "")
        imageMenu.addItem(.separator())
        imageMenu.addItem(withTitle: "Resize…", action: #selector(EditorWindowController.resizeImage(_:)), keyEquivalent: "")
        imageItem.submenu = imageMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder",
                                   accessibilityDescription: "ShotEditor")
        }

        let menu = NSMenu()
        // Note: ⇧⌘3/4/5 belong to macOS Screenshot, so we use ⌥⌘ to avoid conflicts.
        menu.addItem(makeItem("Capture Area…", #selector(captureArea), "4", [.command, .option]))
        menu.addItem(makeItem("Capture Window…", #selector(captureWindow), "5", [.command, .option]))
        menu.addItem(makeItem("Capture Full Screen", #selector(captureFullScreen), "3", [.command, .option]))
        menu.addItem(makeItem("Repeat Last Capture", #selector(repeatLastCapture), "4", [.command, .option, .shift]))

        let delayItem = NSMenuItem(title: "Capture Area with Delay", action: nil, keyEquivalent: "")
        let delayMenu = NSMenu()
        delayMenu.addItem(makeItem("After 3 seconds", #selector(captureAreaDelayed3), "", []))
        delayMenu.addItem(makeItem("After 5 seconds", #selector(captureAreaDelayed5), "", []))
        delayMenu.addItem(makeItem("After 10 seconds", #selector(captureAreaDelayed10), "", []))
        delayItem.submenu = delayMenu
        menu.addItem(delayItem)

        menu.addItem(.separator())
        menu.addItem(makeItem("Pick Color (Eyedropper)…", #selector(pickColor), "", []))
        menu.addItem(makeItem("Open Image…", #selector(openImage), "o", [.command]))

        let recentItem = NSMenuItem(title: "Recent Screenshots", action: nil, keyEquivalent: "")
        let rm = NSMenu(title: "Recent")
        rm.delegate = self
        recentMenu = rm
        recentItem.submenu = rm
        menu.addItem(recentItem)

        let autosave = makeItem("Auto-save Captures to Folder", #selector(toggleAutosave(_:)), "", [])
        autosave.state = autosaveEnabled ? .on : .off
        menu.addItem(autosave)

        menu.addItem(makeItem("Set Save Folder…", #selector(chooseSaveFolder), "", []))

        let launch = makeItem("Launch at Login", #selector(toggleLaunchAtLogin(_:)), "", [])
        launch.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launch)

        menu.addItem(.separator())

        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.addItem(appearanceMenuItem("System", "system"))
        sub.addItem(appearanceMenuItem("Light", "light"))
        sub.addItem(appearanceMenuItem("Dark", "dark"))
        appearanceItem.submenu = sub
        appearanceMenu = sub
        menu.addItem(appearanceItem)
        updateAppearanceMenuState()

        menu.addItem(.separator())
        menu.addItem(makeItem("Quit ShotEditor", #selector(quit), "q", [.command]))
        statusItem.menu = menu
    }

    private func appearanceMenuItem(_ title: String, _ mode: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(appearanceChanged(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = mode
        return item
    }

    @objc private func appearanceChanged(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        setAppearance(mode, persist: true)
    }

    private func applySavedAppearance() {
        let mode = UserDefaults.standard.string(forKey: "appearance") ?? "system"
        setAppearance(mode, persist: false)
    }

    private func setAppearance(_ mode: String, persist: Bool) {
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil   // follow the system
        }
        if persist { UserDefaults.standard.set(mode, forKey: "appearance") }
        updateAppearanceMenuState()
    }

    private func updateAppearanceMenuState() {
        let current = UserDefaults.standard.string(forKey: "appearance") ?? "system"
        appearanceMenu?.items.forEach { item in
            item.state = (item.representedObject as? String == current) ? .on : .off
        }
    }

    private func makeItem(_ title: String, _ action: Selector,
                          _ key: String, _ mods: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = self
        return item
    }

    // MARK: Global hotkeys

    private func registerHotkeys() {
        // Global shortcuts. ⇧⌘3/4/5 are owned by the macOS Screenshot service,
        // so we use ⌥⌘ (Option+Command) to stay conflict-free.
        hotkeys.register(keyCode: 21, modifiers: [.command, .option]) { [weak self] in self?.captureArea() }       // ⌥⌘4
        hotkeys.register(keyCode: 20, modifiers: [.command, .option]) { [weak self] in self?.captureFullScreen() } // ⌥⌘3
        hotkeys.register(keyCode: 23, modifiers: [.command, .option]) { [weak self] in self?.captureWindow() }     // ⌥⌘5
    }

    // MARK: Capture actions

    private var lastCaptureMode: ScreenCapture.Mode = .area

    private func run(_ mode: ScreenCapture.Mode, delay: TimeInterval = 0) {
        guard ensureCapturePermission() else { return }
        lastCaptureMode = mode
        let work = { ScreenCapture.capture(mode: mode) { [weak self] image in self?.openEditor(with: image) } }
        if delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
        else { work() }
    }

    /// Screen Recording permission is required or `screencapture` returns only
    /// the desktop wallpaper (which looks like "the wrong part of the screen").
    private func ensureCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
        ShotEditor needs Screen Recording access, otherwise captures only show the \
        desktop wallpaper instead of your windows.

        1. Enable ShotEditor in System Settings → Privacy & Security → Screen Recording
        2. Quit and reopen ShotEditor (the permission is read at launch)

        Tip: rebuilding with an ad-hoc signature resets this every time. Run \
        scripts/create-signing-cert.sh once so it persists.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit ShotEditor")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            NSApp.terminate(nil)
        default:
            break
        }
        return false
    }

    @objc func captureArea()       { run(.area) }
    @objc func captureWindow()     { run(.window) }
    @objc func captureFullScreen() { run(.fullScreen) }

    @objc func captureAreaDelayed3()  { run(.area, delay: 3) }
    @objc func captureAreaDelayed5()  { run(.area, delay: 5) }
    @objc func captureAreaDelayed10() { run(.area, delay: 10) }
    @objc func repeatLastCapture()    { run(lastCaptureMode) }

    @objc func pickColor() {
        let sampler = NSColorSampler()
        sampler.show { color in
            guard let color = color, let srgb = color.usingColorSpace(.sRGB) else { return }
            let r = Int((srgb.redComponent * 255).rounded())
            let g = Int((srgb.greenComponent * 255).rounded())
            let b = Int((srgb.blueComponent * 255).rounded())
            let hex = String(format: "#%02X%02X%02X", r, g, b)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(hex, forType: .string)
            // Brief confirmation via the menu-bar title.
            self.statusItem.button?.title = " \(hex)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.statusItem.button?.title = ""
            }
        }
    }

    @objc func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url,
                  let image = NSImage(contentsOf: url) else { return }
            self?.openEditor(with: image)
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Editor lifecycle

    private func openEditor(with image: NSImage?) {
        guard let image else { return }
        autosaveIfNeeded(image)
        let controller = EditorWindowController(image: image)
        controller.onClose = { [weak self, weak controller] in
            self?.editors.removeAll { $0 === controller }
        }
        editors.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Autosave & recents

    private var autosaveEnabled: Bool { UserDefaults.standard.bool(forKey: "autosave") }

    private func autosaveIfNeeded(_ image: NSImage) {
        guard autosaveEnabled,
              let data = ImageExport.data(from: image, format: .png) else { return }
        let dir = AppDelegate.saveDirectory()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = dir.appendingPathComponent("Screenshot \(f.string(from: Date())).png")
        do { try data.write(to: url); RecentScreenshots.add(url) } catch { NSLog("autosave failed: \(error)") }
    }

    @objc private func toggleAutosave(_ sender: NSMenuItem) {
        let v = !autosaveEnabled
        UserDefaults.standard.set(v, forKey: "autosave")
        sender.state = v ? .on : .off
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, let img = NSImage(contentsOf: url) else { return }
        openEditor(with: img)
    }

    @objc private func revealRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func clearRecents() { RecentScreenshots.clear() }

    // MARK: Save folder + launch at login

    static func saveDirectory() -> URL {
        if let path = UserDefaults.standard.string(forKey: "saveFolder") {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    @objc private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppDelegate.saveDirectory()
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "saveFolder")
        }
    }

    private var launchAtLoginEnabled: Bool {
        if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        guard #available(macOS 13, *) else { return }
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister(); sender.state = .off }
            else { try svc.register(); sender.state = .on }
        } catch {
            NSLog("Launch-at-login toggle failed: \(error)")
            let alert = NSAlert(error: error); alert.runModal()
        }
    }

    // NSMenuDelegate: populate the Recent submenu on open.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()
        let urls = RecentScreenshots.urls()
        if urls.isEmpty {
            let empty = NSMenuItem(title: "No recent screenshots", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.image = thumbnailIcon(for: url)
            let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(revealRecent(_:)), keyEquivalent: "")
            reveal.target = self; reveal.representedObject = url
            let sub = NSMenu(); sub.addItem(reveal)
            item.submenu = sub
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Recents", action: #selector(clearRecents), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    private func thumbnailIcon(for url: URL) -> NSImage? {
        guard let img = NSImage(contentsOf: url) else { return nil }
        let side: CGFloat = 16
        let s = img.size
        let scale = min(side / max(s.width, 1), side / max(s.height, 1))
        let size = CGSize(width: s.width * scale, height: s.height * scale)
        let out = NSImage(size: size)
        out.lockFocus()
        img.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }
}
