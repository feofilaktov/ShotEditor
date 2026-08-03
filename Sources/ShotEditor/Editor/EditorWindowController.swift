import AppKit
import Vision

final class EditorWindowController: NSWindowController, CanvasViewDelegate, NSWindowDelegate {

    private let doc: EditorDocument
    private var canvas: CanvasView!
    private var scrollView: NSScrollView!

    private var toolButtons: [ToolKind: IconButton] = [:]
    private var inspectorStack: NSStackView!
    private var undoButton: IconButton!
    private var redoButton: IconButton!
    private var zoomLabel: NSTextField!
    private var dimsLabel: NSTextField!
    private var fontSizeField: NSTextField?
    private var fontStepperControl: NSStepper?
    private var blurAmountSlider: NSSlider?

    var onClose: (() -> Void)?
    private let sharedUndo = UndoManager()
    private var settings: ToolSettings { doc.settings }

    init(image: NSImage) {
        self.doc = EditorDocument(image: image)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Screenshot"
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        sharedUndo.levelsOfUndo = 100
        buildUI()
        selectTool(.arrow, updateButton: true)
        centerAndSize()
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { sharedUndo }

    // Debug hooks (used by --demo / --captest verification).
    var debugImageSize: CGSize { doc.imageSize }
    func debugSetZoom(_ z: CGFloat) { setZoom(z) }
    func debugBeginCrop() { selectTool(.crop, updateButton: true) }

    // MARK: UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let topBar = Theme.makeBar(material: .headerView)
        let inspectorBar = Theme.makeBar(material: .titlebar)
        let statusBar = Theme.makeBar(material: .titlebar)

        // -- Top bar: tools + actions
        let toolsStack = NSStackView()
        toolsStack.orientation = .horizontal
        toolsStack.spacing = 2
        for tool in ToolKind.allCases {
            let b = IconButton(symbol: tool.symbolName,
                               accessibility: "\(tool.title)  (\(tool.shortcut.uppercased()))")
            b.target = self
            b.action = #selector(toolButtonTapped(_:))
            b.tag = tool.rawValue
            toolButtons[tool] = b
            toolsStack.addArrangedSubview(b)
        }

        undoButton = IconButton(symbol: "arrow.uturn.backward", accessibility: "Undo")
        undoButton.target = self; undoButton.action = #selector(undoAction(_:))
        redoButton = IconButton(symbol: "arrow.uturn.forward", accessibility: "Redo")
        redoButton.target = self; redoButton.action = #selector(redoAction(_:))

        let backdropButton = IconButton(symbol: "wand.and.stars", accessibility: "Backdrop / beautify")
        backdropButton.target = self; backdropButton.action = #selector(showBackdropPopover(_:))

        let copyButton = Buttons.secondary("Copy", target: self, action: #selector(copyImageToClipboard(_:)))
        let saveButton = Buttons.primary("Save", target: self, action: #selector(saveDocument(_:)), key: "s")

        let topStack = NSStackView(views: [toolsStack, spacer(),
                                           backdropButton, undoButton, redoButton, vDivider(),
                                           copyButton, saveButton])
        topStack.orientation = .horizontal
        topStack.spacing = Theme.gap
        topStack.alignment = .centerY
        topStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(topStack)
        NSLayoutConstraint.activate([
            topStack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: Theme.trafficLightInset),
            topStack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -Theme.hpad),
            topStack.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
        ])

        // -- Inspector bar (contextual)
        inspectorStack = NSStackView()
        inspectorStack.orientation = .horizontal
        inspectorStack.spacing = 10
        inspectorStack.alignment = .centerY
        inspectorStack.translatesAutoresizingMaskIntoConstraints = false
        inspectorBar.addSubview(inspectorStack)
        NSLayoutConstraint.activate([
            inspectorStack.leadingAnchor.constraint(equalTo: inspectorBar.leadingAnchor, constant: Theme.hpad + 4),
            inspectorStack.trailingAnchor.constraint(lessThanOrEqualTo: inspectorBar.trailingAnchor, constant: -Theme.hpad),
            inspectorStack.centerYAnchor.constraint(equalTo: inspectorBar.centerYAnchor),
        ])

        // -- Canvas
        canvas = CanvasView(document: doc)
        canvas.delegate = self
        scrollView = NSScrollView()
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.canvasBackdrop
        scrollView.contentView.postsBoundsChangedNotifications = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // -- Status bar
        dimsLabel = NSTextField(labelWithString: "")
        dimsLabel.font = Theme.caption
        dimsLabel.textColor = Theme.secondaryText

        let zoomOut = IconButton(symbol: "minus", accessibility: "Zoom out")
        zoomOut.target = self; zoomOut.action = #selector(zoomOutAction)
        let zoomIn = IconButton(symbol: "plus", accessibility: "Zoom in")
        zoomIn.target = self; zoomIn.action = #selector(zoomInAction)
        zoomLabel = NSTextField(labelWithString: "100%")
        zoomLabel.font = Theme.caption
        zoomLabel.alignment = .center
        zoomLabel.textColor = Theme.secondaryText
        zoomLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let fitButton = IconButton(symbol: "arrow.up.left.and.arrow.down.right", accessibility: "Fit to window")
        fitButton.target = self; fitButton.action = #selector(zoomFitAction)

        let dragWell = DragWell()
        dragWell.imageProvider = { [weak self] in
            guard let self else { return nil }
            self.canvas.commitTextEditingIfNeeded()
            return Renderer.flattenForExport(self.doc)
        }
        dragWell.filenameProvider = { "Screenshot \(Self.timestamp()).png" }

        let statusStack = NSStackView(views: [dimsLabel, dragWell, spacer(), fitButton, zoomOut, zoomLabel, zoomIn])
        statusStack.orientation = .horizontal
        statusStack.spacing = 4
        statusStack.alignment = .centerY
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(statusStack)
        NSLayoutConstraint.activate([
            statusStack.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: Theme.hpad),
            statusStack.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -Theme.hpad),
            statusStack.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
        ])

        // -- Assemble
        [topBar, inspectorBar, scrollView, statusBar].forEach { content.addSubview($0) }
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: content.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: Theme.toolbarHeight),

            inspectorBar.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            inspectorBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            inspectorBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            inspectorBar.heightAnchor.constraint(equalToConstant: Theme.inspectorHeight),

            scrollView.topAnchor.constraint(equalTo: inspectorBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: Theme.statusHeight),
        ])

        addHairline(below: topBar, in: content)
        addHairline(below: inspectorBar, in: content)
        addHairline(above: statusBar, in: content)

        updateDims()
        updateUndoButtons()
    }

    private func spacer() -> NSView {
        let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        return v
    }

    private func vDivider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = Theme.hair.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return v
    }

    private func addHairline(below bar: NSView, in content: NSView) {
        let line = hairline(); content.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            line.topAnchor.constraint(equalTo: bar.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
    }
    private func addHairline(above bar: NSView, in content: NSView) {
        let line = hairline(); content.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bar.topAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
    }
    private func hairline() -> NSView {
        let v = NSView(); v.wantsLayer = true
        v.layer?.backgroundColor = Theme.hair.withAlphaComponent(0.6).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    // MARK: Inspector

    private func rebuildInspector() {
        inspectorStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        fontSizeField = nil; fontStepperControl = nil; blurAmountSlider = nil

        if canvas.cropActive {
            inspectorStack.addArrangedSubview(caption("Drag to select the area to keep"))
            inspectorStack.addArrangedSubview(spacer())
            inspectorStack.addArrangedSubview(Buttons.secondary("Cancel", target: self, action: #selector(cancelCrop(_:))))
            let apply = Buttons.primary("Apply Crop", target: self, action: #selector(applyCrop(_:)))
            inspectorStack.addArrangedSubview(apply)
            return
        }

        switch settings.current {
        case .select:
            inspectorStack.addArrangedSubview(caption("Click to move · click again to pick layer below · right-click for layers · ⌫ delete"))
        case .arrow:
            addColor(); addWidth(); addArrowStyle(); addDashToggle()
        case .shape:
            addColor(); addWidth(); addShapeKind(); addDashToggle()
        case .pen:
            addColor(); addWidth()
        case .highlighter:
            addColor(); addWidth()
        case .number:
            addColor(); addWidth()
            inspectorStack.addArrangedSubview(vDivider())
            inspectorStack.addArrangedSubview(caption("Next: \(settings.nextNumber)"))
            inspectorStack.addArrangedSubview(Buttons.secondary("Reset", target: self, action: #selector(resetNumbers)))
        case .text:
            addColor(); addFontControls()
        case .callout:
            addColor(); addFontControls()
            inspectorStack.addArrangedSubview(vDivider())
            inspectorStack.addArrangedSubview(caption("Drag a bubble, then type"))
        case .blur:
            addBlurControls()
        case .crop:
            inspectorStack.addArrangedSubview(caption("Adjust the area, then Apply Crop"))
        }
    }

    @objc private func resetNumbers() { settings.nextNumber = 1; rebuildInspector() }

    // MARK: Backdrop popover

    private var backdropPopover: NSPopover?

    @objc private func showBackdropPopover(_ sender: NSButton) {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        content.translatesAutoresizingMaskIntoConstraints = false

        let enable = NSButton(checkboxWithTitle: "Beautify backdrop", target: self, action: #selector(bdEnable(_:)))
        enable.state = doc.backdrop.enabled ? .on : .off
        content.addArrangedSubview(enable)

        let style = NSSegmentedControl(labels: Backdrop.Style.allCases.map { $0.title },
                                       trackingMode: .selectOne, target: self, action: #selector(bdStyle(_:)))
        style.selectedSegment = doc.backdrop.style.rawValue
        content.addArrangedSubview(labeled("Background", style))

        content.addArrangedSubview(labeled("Padding",
            slider(0...220, Double(doc.backdrop.padding), #selector(bdPadding(_:)))))
        content.addArrangedSubview(labeled("Corners",
            slider(0...60, Double(doc.backdrop.cornerRadius), #selector(bdCorner(_:)))))

        let shadow = NSButton(checkboxWithTitle: "Drop shadow", target: self, action: #selector(bdShadow(_:)))
        shadow.state = doc.backdrop.shadow ? .on : .off
        content.addArrangedSubview(shadow)

        let container = NSView()
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        let vc = NSViewController()
        vc.view = container
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = vc
        pop.contentSize = CGSize(width: 300, height: 210)
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        backdropPopover = pop
    }

    private func labeled(_ title: String, _ control: NSView) -> NSView {
        let l = NSTextField(labelWithString: title)
        l.font = Theme.caption; l.textColor = Theme.secondaryText
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 78).isActive = true
        let row = NSStackView(views: [l, control])
        row.orientation = .horizontal; row.spacing = 8
        return row
    }

    private func slider(_ range: ClosedRange<Double>, _ value: Double, _ action: Selector) -> NSSlider {
        let s = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                         target: self, action: action)
        s.translatesAutoresizingMaskIntoConstraints = false
        s.widthAnchor.constraint(equalToConstant: 150).isActive = true
        return s
    }

    private func refreshBackdrop() { canvas.backdropDidChange(); fitZoom() }
    @objc private func bdEnable(_ s: NSButton) { doc.backdrop.enabled = (s.state == .on); refreshBackdrop() }
    @objc private func bdStyle(_ s: NSSegmentedControl) {
        doc.backdrop.style = Backdrop.Style(rawValue: s.selectedSegment) ?? .oceanGradient
        if !doc.backdrop.enabled { doc.backdrop.enabled = true }
        refreshBackdrop()
    }
    @objc private func bdPadding(_ s: NSSlider) { doc.backdrop.padding = CGFloat(s.doubleValue); refreshBackdrop() }
    @objc private func bdCorner(_ s: NSSlider) { doc.backdrop.cornerRadius = CGFloat(s.doubleValue); refreshBackdrop() }
    @objc private func bdShadow(_ s: NSButton) { doc.backdrop.shadow = (s.state == .on); refreshBackdrop() }

    private func addDashToggle() {
        let bar = IconSegmentedBar(items: [.symbol("minus"), .symbol("ellipsis")],
                                   selected: settings.dashed ? 1 : 0)
        bar.onSelect = { [weak self] i in self?.settings.dashed = (i == 1) }
        group("Line", bar)
    }

    private func caption(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = Theme.label; l.textColor = Theme.secondaryText
        return l
    }

    private func group(_ title: String, _ control: NSView) {
        let l = NSTextField(labelWithString: title)
        l.font = Theme.caption; l.textColor = Theme.secondaryText
        inspectorStack.addArrangedSubview(l)
        inspectorStack.addArrangedSubview(control)
    }

    private func addColor() {
        let bar = SwatchBar(selected: settings.color)
        bar.onPick = { [weak self] c in
            self?.settings.color = c
            self?.canvas.commitTextEditingIfNeeded()
        }
        inspectorStack.addArrangedSubview(bar)
        inspectorStack.addArrangedSubview(vDivider())
    }

    private func addWidth() {
        let items: [IconSegmentedBar.Item] = [.dot(5), .dot(8), .dot(12), .dot(16)]
        let idx = ToolSettings.lineWidths.firstIndex(of: settings.lineWidth) ?? 1
        let bar = IconSegmentedBar(items: items, selected: idx)
        bar.onSelect = { [weak self] i in self?.settings.lineWidth = ToolSettings.lineWidths[i] }
        group("Size", bar)
    }

    private func addArrowStyle() {
        let items = ArrowStyle.allCases.map { IconSegmentedBar.Item.symbol($0.iconName) }
        let bar = IconSegmentedBar(items: items, selected: settings.arrowStyle.rawValue)
        bar.onSelect = { [weak self] i in self?.settings.arrowStyle = ArrowStyle(rawValue: i) ?? .filled }
        group("Style", bar)
    }

    private func addShapeKind() {
        let items = ShapeKind.allCases.map { IconSegmentedBar.Item.symbol($0.iconName) }
        let bar = IconSegmentedBar(items: items, selected: settings.shapeKind.rawValue)
        bar.onSelect = { [weak self] i in self?.settings.shapeKind = ShapeKind(rawValue: i) ?? .rect }
        group("Shape", bar)

        let fill = IconSegmentedBar(items: [.symbol("square"), .symbol("square.fill")],
                                    selected: settings.shapeFilled ? 1 : 0)
        fill.onSelect = { [weak self] i in self?.settings.shapeFilled = (i == 1) }
        group("Fill", fill)
    }

    private func addFontControls() {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ToolSettings.availableFonts.map { $0.label })
        if let idx = ToolSettings.availableFonts.firstIndex(where: { $0.name == settings.fontName }) {
            popup.selectItem(at: idx)
        }
        popup.target = self; popup.action = #selector(fontChanged(_:))
        group("Font", popup)

        let field = NSTextField(); field.stringValue = String(Int(settings.fontSize))
        field.formatter = intFormatter(8, 240)
        field.target = self; field.action = #selector(fontSizeChanged(_:))
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 46).isActive = true
        let stepper = NSStepper()
        stepper.minValue = 8; stepper.maxValue = 240; stepper.increment = 2
        stepper.integerValue = Int(settings.fontSize)
        stepper.target = self; stepper.action = #selector(fontStepper(_:))
        fontSizeField = field; fontStepperControl = stepper
        group("Size", field)
        inspectorStack.addArrangedSubview(stepper)

        inspectorStack.addArrangedSubview(vDivider())
        let bg = SwatchBar(selected: settings.textBackground, includeTransparent: true)
        bg.onPick = { [weak self] c in self?.settings.textBackground = c }
        group("Background", bg)
    }

    private func addBlurControls() {
        let items = BlurStyle.allCases.map { IconSegmentedBar.Item.symbol($0.symbolName) }
        let bar = IconSegmentedBar(items: items, selected: settings.blurStyle.rawValue)
        bar.onSelect = { [weak self] i in
            self?.settings.blurStyle = BlurStyle(rawValue: i) ?? .pixelate
            self?.blurAmountSlider?.isEnabled = (self?.settings.blurStyle != .solid)
        }
        group("Effect", bar)

        let slider = NSSlider(value: Double(settings.blurAmount), minValue: 0.2, maxValue: 1.0,
                              target: self, action: #selector(blurAmountChanged(_:)))
        slider.isEnabled = settings.blurStyle != .solid
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 130).isActive = true
        blurAmountSlider = slider
        group("Strength", slider)

        inspectorStack.addArrangedSubview(vDivider())
        inspectorStack.addArrangedSubview(caption("Solid fully hides sensitive data"))
    }

    private func intFormatter(_ lo: Int, _ hi: Int) -> NumberFormatter {
        let f = NumberFormatter(); f.numberStyle = .none
        f.minimum = NSNumber(value: lo); f.maximum = NSNumber(value: hi)
        return f
    }

    // MARK: Tool selection

    private func selectTool(_ tool: ToolKind, updateButton: Bool) {
        settings.current = tool
        for (kind, button) in toolButtons { button.isSelectedTool = (kind == tool) }
        canvas.toolDidChange()
        if tool == .crop { canvas.beginCrop() }
        rebuildInspector()
    }

    @objc private func toolButtonTapped(_ sender: IconButton) {
        guard let tool = ToolKind(rawValue: sender.tag) else { return }
        selectTool(tool, updateButton: true)
    }

    // MARK: Actions — inspector

    @objc private func fontChanged(_ s: NSPopUpButton) {
        settings.fontName = ToolSettings.availableFonts[s.indexOfSelectedItem].name
        canvas.commitTextEditingIfNeeded()
    }
    @objc private func fontSizeChanged(_ s: NSTextField) {
        settings.fontSize = CGFloat(s.integerValue); fontStepperControl?.integerValue = s.integerValue
    }
    @objc private func fontStepper(_ s: NSStepper) {
        settings.fontSize = CGFloat(s.integerValue); fontSizeField?.integerValue = s.integerValue
    }
    @objc private func blurAmountChanged(_ s: NSSlider) { settings.blurAmount = CGFloat(s.doubleValue) }

    @objc private func applyCrop(_ s: Any?) { canvas.applyCrop() }
    @objc private func cancelCrop(_ s: Any?) {
        canvas.cancelCrop(); selectTool(.select, updateButton: true)
    }

    // MARK: Actions — zoom

    private func setZoom(_ z: CGFloat) {
        canvas.zoom = max(0.1, min(z, 8))
        zoomLabel.stringValue = "\(Int((canvas.zoom * 100).rounded()))%"
    }
    @objc private func zoomInAction() { setZoom(canvas.zoom * 1.25) }
    @objc private func zoomOutAction() { setZoom(canvas.zoom / 1.25) }
    @objc private func zoomFitAction() { fitZoom() }

    // MARK: Actions — export / undo

    @objc func saveDocument(_ sender: Any?) {
        canvas.commitTextEditingIfNeeded()
        let flat = Renderer.flattenForExport(doc)
        if let url = ImageExport.saveWithPanel(flat, suggestedName: "Screenshot \(Self.timestamp()).png",
                                               defaultDirectory: Self.defaultSaveDirectory()) {
            RecentScreenshots.add(url)
        }
    }
    @objc func copyImageToClipboard(_ sender: Any?) {
        canvas.commitTextEditingIfNeeded()
        ImageExport.copyToPasteboard(Renderer.flattenForExport(doc))
        flashTitle("Copied to clipboard")
    }
    // Image transforms (bake down with undo).
    @objc func rotateLeft(_ s: Any?)  { if let i = Renderer.rotated(doc, clockwise: false) { canvas.bakeReplace(with: i); fitZoom() } }
    @objc func rotateRight(_ s: Any?) { if let i = Renderer.rotated(doc, clockwise: true)  { canvas.bakeReplace(with: i); fitZoom() } }
    @objc func flipHorizontal(_ s: Any?) { if let i = Renderer.flipped(doc, horizontal: true)  { canvas.bakeReplace(with: i) } }
    @objc func flipVertical(_ s: Any?)   { if let i = Renderer.flipped(doc, horizontal: false) { canvas.bakeReplace(with: i) } }

    @objc func resizeImage(_ s: Any?) {
        canvas.commitTextEditingIfNeeded()
        let alert = NSAlert()
        alert.messageText = "Resize Image"
        alert.informativeText = "New width in pixels (height scales proportionally):"
        let tf = NSTextField(frame: CGRect(x: 0, y: 0, width: 200, height: 24))
        tf.stringValue = String(Int(doc.imageSize.width))
        alert.accessoryView = tf
        alert.addButton(withTitle: "Resize")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let w = CGFloat(Int(tf.stringValue) ?? Int(doc.imageSize.width))
            if w > 10, let img = Renderer.scaled(doc, to: w) {
                canvas.bakeReplace(with: img)
                updateDims(); fitZoom()
            }
        }
    }

    @objc func copyTextOCR(_ sender: Any?) {
        guard let cg = Renderer.flattenCGImage(doc) else { return }
        flashTitle("Recognizing text…")
        let request = VNRecognizeTextRequest { [weak self] req, _ in
            let lines = (req.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            let text = lines.joined(separator: "\n")
            DispatchQueue.main.async {
                guard let self else { return }
                if text.isEmpty {
                    self.flashTitle("No text found")
                } else {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    self.flashTitle("Copied \(lines.count) line(s) of text")
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        }
    }

    @objc func undo(_ sender: Any?) { sharedUndo.undo(); afterUndo() }
    @objc func redo(_ sender: Any?) { sharedUndo.redo(); afterUndo() }
    @objc private func undoAction(_ s: Any?) { sharedUndo.undo(); afterUndo() }
    @objc private func redoAction(_ s: Any?) { sharedUndo.redo(); afterUndo() }
    private func afterUndo() { canvas.needsDisplay = true; updateUndoButtons(); updateDims() }

    private func updateUndoButtons() {
        undoButton.isEnabled = sharedUndo.canUndo
        redoButton.isEnabled = sharedUndo.canRedo
        undoButton.alphaValue = sharedUndo.canUndo ? 1 : 0.35
        redoButton.alphaValue = sharedUndo.canRedo ? 1 : 0.35
    }

    private static func defaultSaveDirectory() -> URL? {
        AppDelegate.saveDirectory()
    }
    private static func timestamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: Date())
    }

    // MARK: Sizing

    private func fitZoom() {
        let avail = scrollView?.contentSize ?? CGSize(width: 960, height: 560)
        let img = doc.imageSize
        guard img.width > 0, img.height > 0 else { return }
        let scale = min(avail.width / img.width, avail.height / img.height, 1.0)
        setZoom(scale > 0 ? scale : 1)
    }

    private func centerAndSize() {
        guard let window, let screen = NSScreen.main else { return }
        let img = doc.imageSize
        let chrome = Theme.toolbarHeight + Theme.inspectorHeight + Theme.statusHeight + 40
        let maxW = screen.visibleFrame.width * 0.9
        let maxH = screen.visibleFrame.height * 0.9
        let w = min(max(img.width + 40, 720), maxW)
        let h = min(max(img.height + chrome, 480), maxH)
        window.setContentSize(CGSize(width: w, height: h))
        window.center()
        DispatchQueue.main.async { [weak self] in self?.fitZoom() }
    }

    private func updateDims() {
        let s = doc.imageSize
        dimsLabel.stringValue = "\(Int(s.width)) × \(Int(s.height)) px"
    }

    private func flashTitle(_ text: String) {
        window?.title = text
        window?.titleVisibility = .visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.window?.titleVisibility = .hidden
        }
    }

    // MARK: Delegates

    func canvasDidChange(_ canvas: CanvasView) {
        updateDims(); updateUndoButtons()
    }
    func canvas(_ canvas: CanvasView, requestCropConfirm active: Bool) {
        rebuildInspector()
    }
    func canvas(_ canvas: CanvasView, requestSelectTool tool: ToolKind) {
        selectTool(tool, updateButton: true)
    }
    func windowDidBecomeKey(_ notification: Notification) {
        if canvas.window?.firstResponder !== canvas {
            window?.makeFirstResponder(canvas)
        }
    }
    func windowWillClose(_ notification: Notification) { onClose?() }
}
