import AppKit

protocol CanvasViewDelegate: AnyObject {
    func canvasDidChange(_ canvas: CanvasView)
    func canvas(_ canvas: CanvasView, requestCropConfirm active: Bool)
    func canvas(_ canvas: CanvasView, requestSelectTool tool: ToolKind)
}

/// The drawing surface. Holds the document, renders it at `zoom`, and turns
/// mouse gestures into annotations based on the current tool.
final class CanvasView: NSView, NSTextViewDelegate {

    let document: EditorDocument
    weak var delegate: CanvasViewDelegate?

    var zoom: CGFloat = 1 { didSet { resizeToImage(); needsDisplay = true } }

    private var settings: ToolSettings { document.settings }

    // Interaction state
    private var dragStart: CGPoint?
    private var liveAnnotation: Annotation?
    private var selected: Annotation?
    private var movingFrom: CGPoint?
    private var draggingExisting = false
    private var resizingHandle: Int?
    private var stateBeforeGesture: [Annotation]?

    private var hitTolerance: CGFloat { 8 / zoom }

    // Crop state
    private(set) var cropActive = false
    private var cropRect: CGRect?

    private enum CropHandle { case tl, tr, bl, br, top, bottom, left, right }
    private enum CropDrag { case none, drawNew, move, resize(CropHandle) }
    private var cropDrag: CropDrag = .none
    private var cropMoveLast: CGPoint?

    // Text editing (Text + Callout share the overlay)
    private var editor: NSTextView?
    private var editingAnnotation: (Annotation & TextEditable)?

    init(document: EditorDocument) {
        self.document = document
        super.init(frame: CGRect(origin: .zero, size: document.imageSize))
        wantsLayer = true
        resizeToImage()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    private var backdrop: Backdrop { document.backdrop }
    private var imageOriginPts: CGPoint { backdrop.imageOrigin() }

    private func resizeToImage() {
        let s = backdrop.totalSize(for: document.imageSize)
        setFrameSize(CGSize(width: s.width * zoom, height: s.height * zoom))
    }

    /// Call after backdrop settings change.
    func backdropDidChange() {
        resizeToImage()
        needsDisplay = true
    }

    // MARK: Coordinate mapping

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / zoom - imageOriginPts.x, y: p.y / zoom - imageOriginPts.y)
    }

    private func viewRect(_ imageRect: CGRect) -> CGRect {
        let ox = imageOriginPts.x, oy = imageOriginPts.y
        return CGRect(x: (imageRect.minX + ox) * zoom, y: (imageRect.minY + oy) * zoom,
                      width: imageRect.width * zoom, height: imageRect.height * zoom)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        Theme.canvasBackdrop.setFill()
        dirtyRect.fill()

        // Backdrop card (padding + gradient/solid background) fills the frame.
        if backdrop.enabled {
            backdrop.drawBackground(in: bounds)
        }

        let originView = CGPoint(x: imageOriginPts.x * zoom, y: imageOriginPts.y * zoom)
        let imageRectInView = CGRect(origin: originView,
                                     size: CGSize(width: document.imageSize.width * zoom,
                                                  height: document.imageSize.height * zoom))
        let radius = backdrop.enabled ? backdrop.cornerRadius * zoom : 0

        // Soft drop shadow behind the image.
        NSGraphicsContext.saveGraphicsState()
        if backdrop.shadow || !backdrop.enabled {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(backdrop.enabled ? 0.4 : 0.35)
            shadow.shadowBlurRadius = backdrop.enabled ? 26 : 18
            shadow.shadowOffset = CGSize(width: 0, height: -8)
            shadow.set()
        }
        NSColor.white.setFill()
        NSBezierPath(roundedRect: imageRectInView, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Clip the screenshot to rounded corners.
        NSGraphicsContext.saveGraphicsState()
        if radius > 0 {
            NSBezierPath(roundedRect: imageRectInView, xRadius: radius, yRadius: radius).addClip()
        }

        let t = NSAffineTransform()
        t.translateX(by: originView.x, yBy: originView.y)
        t.scale(by: zoom)
        t.concat()

        let env = document.renderEnv
        document.baseImage.draw(in: CGRect(origin: .zero, size: document.imageSize),
                                from: .zero, operation: .sourceOver, fraction: 1.0)

        for a in document.annotations where a !== editingAnnotation {
            NSGraphicsContext.saveGraphicsState()
            a.draw(env: env)
            NSGraphicsContext.restoreGraphicsState()
        }
        if let live = liveAnnotation {
            NSGraphicsContext.saveGraphicsState()
            live.draw(env: env)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Overlays in view space (constant screen size).
        if let sel = selected, !cropActive, editingAnnotation == nil {
            drawSelection(sel)
        }
        if cropActive { drawCropOverlay() }
    }

    private func drawSelection(_ sel: Annotation) {
        let r = viewRect(sel.bounds).insetBy(dx: -3, dy: -3)
        let path = NSBezierPath(rect: r)
        path.lineWidth = 1
        NSColor.controlAccentColor.setStroke()
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()

        // Resize handles
        for h in sel.resizeHandles() {
            let v = CGPoint(x: h.x * zoom, y: h.y * zoom)
            let box = CGRect(x: v.x - 4, y: v.y - 4, width: 8, height: 8)
            NSColor.white.setFill(); NSBezierPath(ovalIn: box).fill()
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(ovalIn: box); ring.lineWidth = 1.5; ring.stroke()
        }
    }

    private func handleIndexAt(_ sel: Annotation, _ p: CGPoint) -> Int? {
        let tol = 9 / zoom
        for (i, h) in sel.resizeHandles().enumerated()
        where hypot(p.x - h.x, p.y - h.y) <= tol { return i }
        return nil
    }

    private func drawCropOverlay() {
        guard let cr = cropRect else { return }
        let full = bounds
        let rect = viewRect(cr)

        NSColor.black.withAlphaComponent(0.5).setFill()
        let outside = NSBezierPath(rect: full)
        outside.append(NSBezierPath(rect: rect).reversed)
        outside.windingRule = .evenOdd
        outside.fill()

        // Rule-of-thirds guides
        NSColor.white.withAlphaComponent(0.25).setStroke()
        let thirds = NSBezierPath()
        for i in 1...2 {
            let x = rect.minX + rect.width * CGFloat(i) / 3
            thirds.move(to: CGPoint(x: x, y: rect.minY)); thirds.line(to: CGPoint(x: x, y: rect.maxY))
            let y = rect.minY + rect.height * CGFloat(i) / 3
            thirds.move(to: CGPoint(x: rect.minX, y: y)); thirds.line(to: CGPoint(x: rect.maxX, y: y))
        }
        thirds.lineWidth = 1; thirds.stroke()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1.5
        border.stroke()

        // 8 handles
        for (_, c) in cropHandlePoints(cr) {
            let v = CGPoint(x: c.x * zoom, y: c.y * zoom)
            let h = CGRect(x: v.x - 5, y: v.y - 5, width: 10, height: 10)
            NSColor.white.setFill(); NSBezierPath(ovalIn: h).fill()
            NSColor.black.withAlphaComponent(0.4).setStroke()
            let ring = NSBezierPath(ovalIn: h); ring.lineWidth = 1; ring.stroke()
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        commitTextEditingIfNeeded()
        let p = imagePoint(event)
        dragStart = p
        stateBeforeGesture = snapshotAnnotations()

        if cropActive {
            cropDrag = cropDragMode(at: p)
            switch cropDrag {
            case .drawNew:
                cropRect = CGRect(origin: p, size: .zero)
            case .move:
                cropMoveLast = p
            case .resize, .none:
                break
            }
            needsDisplay = true
            return
        }

        // Double-click any editable text/callout to edit it, whatever the tool.
        if event.clickCount >= 2,
           let te = document.hitTest(p, tolerance: hitTolerance) as? (Annotation & TextEditable) {
            beginEditing(te)
            return
        }

        // Select tool: pick and move. Repeated clicks on a stack of overlapping
        // objects cycle downward through the layers.
        if settings.current == .select {
            // Grab a resize handle of the current selection first.
            if let sel = selected, let hi = handleIndexAt(sel, p) {
                resizingHandle = hi
                movingFrom = p
                draggingExisting = true
                needsDisplay = true
                return
            }
            let stack = annotationsAt(p)
            if let cur = selected, let idx = stack.firstIndex(where: { $0 === cur }), stack.count > 1 {
                selected = stack[(idx + 1) % stack.count]
            } else {
                selected = stack.first
            }
            movingFrom = p
            draggingExisting = selected != nil
            needsDisplay = true
            return
        }

        // Text tool: edit on hit, otherwise create + edit.
        if settings.current == .text {
            if let hit = document.hitTest(p, tolerance: hitTolerance) as? (Annotation & TextEditable) {
                beginEditing(hit)
            } else {
                let ann = TextAnnotation(origin: p, string: "", font: settings.font)
                ann.color = settings.color
                ann.backgroundColor = settings.textBackground
                document.add(ann)
                beginEditing(ann)
            }
            return
        }

        // Any drawing tool: clicking an existing object grabs it to move —
        // no need to switch to the cursor tool first.
        if let hit = document.hitTest(p, tolerance: hitTolerance) {
            selected = hit
            movingFrom = p
            draggingExisting = true
            needsDisplay = true
            return
        }

        selected = nil
        switch settings.current {
        case .arrow:
            let ann = ArrowAnnotation(start: p, end: p, style: settings.arrowStyle)
            configure(ann); liveAnnotation = ann
        case .shape:
            let ann = ShapeAnnotation(kind: settings.shapeKind, p0: p, p1: p)
            ann.filled = settings.shapeFilled
            configure(ann); liveAnnotation = ann
        case .pen:
            let ann = PenAnnotation(points: [p])
            configure(ann); liveAnnotation = ann
        case .highlighter:
            let ann = PenAnnotation(points: [p])
            ann.isHighlighter = true
            ann.color = settings.color
            ann.lineWidth = max(14, settings.lineWidth * 4)
            liveAnnotation = ann
        case .number:
            let d = 26 + settings.lineWidth * 2.5
            let ann = NumberAnnotation(center: p, number: settings.nextNumber, diameter: d)
            ann.color = settings.color
            liveAnnotation = ann
        case .callout:
            let ann = CalloutAnnotation(rect: CGRect(origin: p, size: .zero), tailTip: p, font: settings.font)
            ann.color = settings.color
            liveAnnotation = ann
        case .blur:
            let ann = BlurAnnotation(rect: CGRect(origin: p, size: .zero), style: settings.blurStyle)
            ann.amount = settings.blurAmount
            liveAnnotation = ann
        case .select, .text, .crop:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = imagePoint(event)

        if cropActive {
            updateCropDrag(to: p)
            needsDisplay = true
            return
        }

        // Moving or resizing an existing (or just-drawn) object — any tool.
        if draggingExisting, let sel = selected, let from = movingFrom {
            if let hi = resizingHandle {
                sel.moveHandle(hi, to: p)
            } else {
                sel.translate(by: CGVector(dx: p.x - from.x, dy: p.y - from.y))
                movingFrom = p
            }
            needsDisplay = true
            return
        }

        switch settings.current {
        case .select:
            break
        case .arrow:
            (liveAnnotation as? ArrowAnnotation)?.end = p
            needsDisplay = true
        case .shape:
            (liveAnnotation as? ShapeAnnotation)?.p1 = p
            needsDisplay = true
        case .pen, .highlighter:
            (liveAnnotation as? PenAnnotation)?.points.append(p)
            needsDisplay = true
        case .number:
            (liveAnnotation as? NumberAnnotation)?.center = p
            needsDisplay = true
        case .callout:
            if let s = dragStart, let c = liveAnnotation as? CalloutAnnotation {
                c.rect = normalizedRect(from: s, to: p)
                c.tailTip = CGPoint(x: c.rect.minX + c.rect.width * 0.3, y: c.rect.minY - 45)
                needsDisplay = true
            }
        case .blur:
            if let s = dragStart {
                (liveAnnotation as? BlurAnnotation)?.rect = normalizedRect(from: s, to: p)
                needsDisplay = true
            }
        case .text, .crop:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if cropActive {
            cropDrag = .none
            cropMoveLast = nil
            needsDisplay = true
            return
        }

        // Finished moving or resizing an existing object.
        if draggingExisting {
            if let before = stateBeforeGesture, movedSince(before) {
                registerUndo(before)
                notifyChange()
            }
            draggingExisting = false
            resizingHandle = nil
            dragStart = nil; movingFrom = nil
            return
        }

        if let live = liveAnnotation {
            if annotationIsMeaningful(live) {
                let before = stateBeforeGesture
                document.add(live)
                if live is NumberAnnotation { settings.nextNumber += 1 }
                selected = live          // keep it selected so it can be dragged right away
                if let before { registerUndo(before) }
                notifyChange()
                if let callout = live as? CalloutAnnotation {
                    liveAnnotation = nil
                    beginEditing(callout)   // type your text right after drawing
                    dragStart = nil
                    return
                }
            } else {
                selected = nil
            }
            liveAnnotation = nil
            needsDisplay = true
        }
        dragStart = nil
    }

    private func annotationIsMeaningful(_ a: Annotation) -> Bool {
        switch a {
        case let arrow as ArrowAnnotation:
            return hypot(arrow.end.x - arrow.start.x, arrow.end.y - arrow.start.y) > 3
        case let shape as ShapeAnnotation:
            return shape.rect.width > 3 || shape.rect.height > 3
        case let pen as PenAnnotation:
            return pen.points.count > 1
        case let blur as BlurAnnotation:
            return blur.rect.width > 3 && blur.rect.height > 3
        case let callout as CalloutAnnotation:
            return callout.rect.width > 12 && callout.rect.height > 12
        default:
            return true
        }
    }

    private func configure(_ a: Annotation) {
        a.color = settings.color
        a.lineWidth = settings.lineWidth
        a.dashed = settings.dashed
    }

    private func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    // MARK: Selection ops

    var hasSelection: Bool { selected != nil }
    var selectedKind: ToolKind? {
        switch selected {
        case is ArrowAnnotation: return .arrow
        case is ShapeAnnotation: return .shape
        case let p as PenAnnotation: return p.isHighlighter ? .highlighter : .pen
        case is NumberAnnotation: return .number
        case is TextAnnotation: return .text
        case is CalloutAnnotation: return .callout
        case is BlurAnnotation: return .blur
        default: return nil
        }
    }

    /// Mutate the selected object (color/width/style/etc.) with undo + redraw.
    /// Called by the inspector so editing an already-placed object works without
    /// deleting and redrawing it.
    @discardableResult
    func applyToSelection(_ apply: (Annotation) -> Void) -> Bool {
        guard let sel = selected else { return false }
        let before = snapshotAnnotations()
        apply(sel)
        registerUndo(before)
        notifyChange()
        needsDisplay = true
        return true
    }

    func deleteSelection() {
        guard let sel = selected else { return }
        let before = snapshotAnnotations()
        document.remove(sel)
        selected = nil
        registerUndo(before)
        notifyChange()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        // Delete selected object.
        if (event.keyCode == 51 || event.keyCode == 117), selected != nil, editor == nil {
            deleteSelection()
            return
        }
        // Single-key tool shortcuts (only when not editing text and no modifiers).
        if editor == nil,
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           let ch = event.charactersIgnoringModifiers?.lowercased(),
           let tool = ToolKind.allCases.first(where: { $0.shortcut == ch }) {
            delegate?.canvas(self, requestSelectTool: tool)
            return
        }
        super.keyDown(with: event)
    }

    override func resetCursorRects() {
        let cursor: NSCursor
        switch settings.current {
        case .select: cursor = .arrow
        case .text:   cursor = .iBeam
        default:      cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: Layers (right-click)

    /// Annotations under a point, topmost first.
    private func annotationsAt(_ p: CGPoint) -> [Annotation] {
        document.annotations.reversed().filter { $0.hitTest(p, tolerance: hitTolerance) }
    }

    private func layerName(_ a: Annotation) -> String {
        switch a {
        case is ArrowAnnotation: return "Arrow"
        case let s as ShapeAnnotation: return "Shape · \(String(describing: s.kind))"
        case is PenAnnotation: return "Pen"
        case let t as TextAnnotation:
            let s = t.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Text · \"\(s.prefix(16))\""
        case let b as BlurAnnotation: return "Redaction · \(b.style.title)"
        default: return "Object"
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if cropActive { return }
        commitTextEditingIfNeeded()
        let p = imagePoint(event)
        let stack = annotationsAt(p)
        guard !stack.isEmpty else { return }

        let menu = NSMenu()
        let header = NSMenuItem(title: "Select layer", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for a in stack {
            let item = NSMenuItem(title: layerName(a), action: #selector(pickLayer(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = a
            item.state = (a === selected) ? .on : .off
            menu.addItem(item)
        }

        let target = (selected != nil && stack.contains { $0 === selected! }) ? selected! : stack[0]
        menu.addItem(.separator())
        menu.addItem(orderItem("Bring to Front", #selector(bringToFrontMenu(_:)), target))
        menu.addItem(orderItem("Bring Forward",  #selector(bringForwardMenu(_:)), target))
        menu.addItem(orderItem("Send Backward",  #selector(sendBackwardMenu(_:)), target))
        menu.addItem(orderItem("Send to Back",   #selector(sendToBackMenu(_:)), target))
        menu.addItem(.separator())
        menu.addItem(orderItem("Delete", #selector(deleteLayerMenu(_:)), target))

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func orderItem(_ title: String, _ action: Selector, _ a: Annotation) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = a
        return item
    }

    @objc private func pickLayer(_ sender: NSMenuItem) {
        selected = sender.representedObject as? Annotation
        needsDisplay = true
    }

    private func reorder(_ a: Annotation, _ mutate: (Int) -> Void) {
        guard let idx = document.annotations.firstIndex(where: { $0 === a }) else { return }
        let before = snapshotAnnotations()
        mutate(idx)
        registerUndo(before)
        selected = a
        notifyChange()
        needsDisplay = true
    }

    @objc private func bringToFrontMenu(_ s: NSMenuItem) {
        guard let a = s.representedObject as? Annotation else { return }
        reorder(a) { idx in
            let obj = document.annotations.remove(at: idx)
            document.annotations.append(obj)
        }
    }
    @objc private func sendToBackMenu(_ s: NSMenuItem) {
        guard let a = s.representedObject as? Annotation else { return }
        reorder(a) { idx in
            let obj = document.annotations.remove(at: idx)
            document.annotations.insert(obj, at: 0)
        }
    }
    @objc private func bringForwardMenu(_ s: NSMenuItem) {
        guard let a = s.representedObject as? Annotation else { return }
        reorder(a) { idx in
            guard idx < document.annotations.count - 1 else { return }
            document.annotations.swapAt(idx, idx + 1)
        }
    }
    @objc private func sendBackwardMenu(_ s: NSMenuItem) {
        guard let a = s.representedObject as? Annotation else { return }
        reorder(a) { idx in
            guard idx > 0 else { return }
            document.annotations.swapAt(idx, idx - 1)
        }
    }
    @objc private func deleteLayerMenu(_ s: NSMenuItem) {
        guard let a = s.representedObject as? Annotation else { return }
        let before = snapshotAnnotations()
        document.remove(a)
        if selected === a { selected = nil }
        registerUndo(before)
        notifyChange()
        needsDisplay = true
    }

    // MARK: Crop

    func beginCrop() {
        cropActive = true
        selected = nil
        cropDrag = .none
        // Start slightly inset so the handles are visible and obviously grabbable.
        let s = document.imageSize
        let ix = s.width * 0.08, iy = s.height * 0.08
        cropRect = CGRect(x: ix, y: iy, width: s.width - ix * 2, height: s.height - iy * 2)
        delegate?.canvas(self, requestCropConfirm: true)
        needsDisplay = true
    }

    // MARK: Crop interaction helpers

    /// The 8 handle centers (image space) for the current crop rect.
    private func cropHandlePoints(_ r: CGRect) -> [(CropHandle, CGPoint)] {
        [(.bl, CGPoint(x: r.minX, y: r.minY)),
         (.br, CGPoint(x: r.maxX, y: r.minY)),
         (.tl, CGPoint(x: r.minX, y: r.maxY)),
         (.tr, CGPoint(x: r.maxX, y: r.maxY)),
         (.left,   CGPoint(x: r.minX, y: r.midY)),
         (.right,  CGPoint(x: r.maxX, y: r.midY)),
         (.bottom, CGPoint(x: r.midX, y: r.minY)),
         (.top,    CGPoint(x: r.midX, y: r.maxY))]
    }

    private func cropDragMode(at p: CGPoint) -> CropDrag {
        guard let r = cropRect else { return .drawNew }
        let tol = 10 / zoom
        for (handle, c) in cropHandlePoints(r) where hypot(p.x - c.x, p.y - c.y) <= tol {
            return .resize(handle)
        }
        if r.insetBy(dx: tol, dy: tol).contains(p) { return .move }
        return .drawNew
    }

    private func updateCropDrag(to p: CGPoint) {
        switch cropDrag {
        case .drawNew:
            if let s = dragStart { cropRect = clampToImage(normalizedRect(from: s, to: p)) }
        case .move:
            guard var r = cropRect, let last = cropMoveLast else { return }
            r.origin.x += p.x - last.x
            r.origin.y += p.y - last.y
            cropRect = clampRectInside(r)
            cropMoveLast = p
        case .resize(let handle):
            guard var r = cropRect else { return }
            resize(&r, handle: handle, to: p)
            cropRect = clampToImage(r)
        case .none:
            break
        }
    }

    private func resize(_ r: inout CGRect, handle: CropHandle, to p: CGPoint) {
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch handle {
        case .left:   minX = p.x
        case .right:  maxX = p.x
        case .bottom: minY = p.y
        case .top:    maxY = p.y
        case .bl:     minX = p.x; minY = p.y
        case .br:     maxX = p.x; minY = p.y
        case .tl:     minX = p.x; maxY = p.y
        case .tr:     maxX = p.x; maxY = p.y
        }
        // Keep a sane minimum and allow edges to cross (normalize).
        r = CGRect(x: min(minX, maxX), y: min(minY, maxY),
                   width: abs(maxX - minX), height: abs(maxY - minY))
        if r.width < 8 { r.size.width = 8 }
        if r.height < 8 { r.size.height = 8 }
    }

    private func clampToImage(_ rect: CGRect) -> CGRect {
        let s = document.imageSize
        let minX = max(0, rect.minX), minY = max(0, rect.minY)
        let maxX = min(s.width, rect.maxX), maxY = min(s.height, rect.maxY)
        return CGRect(x: minX, y: minY,
                      width: max(8, maxX - minX), height: max(8, maxY - minY))
    }

    /// Clamp a moved rect to stay fully inside the image (keeps its size).
    private func clampRectInside(_ rect: CGRect) -> CGRect {
        let s = document.imageSize
        var r = rect
        r.origin.x = min(max(0, r.origin.x), max(0, s.width - r.width))
        r.origin.y = min(max(0, r.origin.y), max(0, s.height - r.height))
        return r
    }

    func cancelCrop() {
        cropActive = false
        cropRect = nil
        delegate?.canvas(self, requestCropConfirm: false)
        needsDisplay = true
    }

    /// Replace the base image (rotate/flip/scale), baking current annotations, with undo.
    func bakeReplace(with image: NSImage) {
        commitTextEditingIfNeeded()
        let before = snapshotFull()
        document.replaceBase(with: image, annotations: [])
        selected = nil
        registerUndoFull(before)
        resizeToImage()
        notifyChange()
        needsDisplay = true
    }

    func applyCrop() {
        guard cropActive, let rect = cropRect, rect.width > 4, rect.height > 4 else {
            cancelCrop(); return
        }
        let before = snapshotFull()
        let flat = Renderer.flatten(document)
        let cropped = Renderer.crop(flat, to: rect)
        document.replaceBase(with: cropped, annotations: [])
        cropActive = false
        cropRect = nil
        registerUndoFull(before)
        delegate?.canvas(self, requestCropConfirm: false)
        resizeToImage()
        notifyChange()
        needsDisplay = true
    }

    // MARK: Text editing

    private func beginEditing(_ annotation: Annotation & TextEditable) {
        editingAnnotation = annotation
        selected = annotation
        // Anchor the editor's top-left at the annotation's text rect.
        let r = annotation.textEditRect
        let originView = CGPoint(x: r.minX * zoom, y: r.maxY * zoom)
        let w = max(120, r.width * zoom)

        let tv = NSTextView(frame: CGRect(x: originView.x, y: originView.y - 40, width: w, height: 40))
        tv.delegate = self
        tv.isRichText = false
        tv.drawsBackground = true
        tv.backgroundColor = NSColor.white.withAlphaComponent(0.95)
        // Always dark text on the light editor background so typing is visible,
        // regardless of the annotation's own colour.
        tv.textColor = NSColor(white: 0.1, alpha: 1)
        tv.insertionPointColor = NSColor(white: 0.1, alpha: 1)
        tv.font = NSFont(name: annotation.editFont.fontName, size: annotation.editFont.pointSize * zoom)
            ?? NSFont.systemFont(ofSize: annotation.editFont.pointSize * zoom)
        tv.string = annotation.string
        tv.textContainerInset = NSSize(width: 4, height: 4)
        // Let it grow freely instead of wrapping at a fixed width.
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.wantsLayer = true
        tv.layer?.cornerRadius = 3
        addSubview(tv)
        editor = tv
        window?.makeFirstResponder(tv)
        sizeEditorToFit()
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        guard let tv = editor, let ann = editingAnnotation else { return }
        ann.string = tv.string
        sizeEditorToFit()
    }

    /// Grow the text editor to fit its content, keeping the top-left anchored.
    private func sizeEditorToFit() {
        guard let tv = editor, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).size
        let w = max(80, ceil(used.width) + 24)
        let h = max(ceil((tv.font?.pointSize ?? 20)) + 16, ceil(used.height) + 12)
        let top = tv.frame.maxY                       // keep the top edge fixed
        tv.frame = CGRect(x: tv.frame.minX, y: top - h, width: w, height: h)
    }

    func commitTextEditingIfNeeded() {
        guard let ann = editingAnnotation, let tv = editor else { return }
        ann.string = tv.string
        if let t = ann as? TextAnnotation {
            t.color = settings.color
            t.font = settings.font
            t.backgroundColor = settings.textBackground
        }
        tv.removeFromSuperview()
        editor = nil
        editingAnnotation = nil
        if ann.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            document.remove(ann)
        }
        notifyChange()
        needsDisplay = true
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            // Shift-Enter inserts a newline; plain Enter commits.
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                return false
            }
            commitTextEditingIfNeeded()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            commitTextEditingIfNeeded()
            return true
        }
        return false
    }

    // MARK: Undo

    private func snapshotAnnotations() -> [Annotation] {
        document.annotations.map { $0.clone() }
    }

    private struct FullSnapshot { let base: NSImage; let anns: [Annotation] }

    private func snapshotFull() -> FullSnapshot {
        FullSnapshot(base: document.baseImage, anns: snapshotAnnotations())
    }

    private func movedSince(_ before: [Annotation]) -> Bool {
        // cheap check: bounds of any current annotation differs
        guard before.count == document.annotations.count else { return true }
        for (a, b) in zip(before, document.annotations) where a.bounds != b.bounds {
            return true
        }
        return false
    }

    private func registerUndo(_ before: [Annotation]) {
        guard let um = undoManager else { return }
        let redoState = snapshotAnnotations()
        um.registerUndo(withTarget: self) { canvas in
            canvas.registerUndo(redoState)
            canvas.document.annotations = before.map { $0.clone() }
            canvas.selected = nil
            canvas.notifyChange()
            canvas.needsDisplay = true
        }
    }

    private func registerUndoFull(_ before: FullSnapshot) {
        guard let um = undoManager else { return }
        let redo = snapshotFull()
        um.registerUndo(withTarget: self) { canvas in
            canvas.registerUndoFull(redo)
            canvas.document.replaceBase(with: before.base,
                                        annotations: before.anns.map { $0.clone() })
            canvas.selected = nil
            canvas.resizeToImage()
            canvas.notifyChange()
            canvas.needsDisplay = true
        }
    }

    private func notifyChange() {
        delegate?.canvasDidChange(self)
    }

    // MARK: Tool change hook

    func toolDidChange() {
        commitTextEditingIfNeeded()
        if settings.current != .crop && cropActive { cancelCrop() }
        selected = nil
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }
}
