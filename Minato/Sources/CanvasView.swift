import AppKit

enum EditorTool: String, CaseIterable {
    case select, pen, arrow, note
    var title: String { switch self { case .select: return "Select"; case .pen: return "Draw"; case .arrow: return "Arrow"; case .note: return "Note" } }
    var symbol: String { switch self { case .select: return "cursorarrow"; case .pen: return "pencil.tip"; case .arrow: return "arrow.up.right"; case .note: return "text.bubble" } }
    var hint: String { switch self {
    case .select: return "Drag or use arrow keys to move · Double-click a note to edit"
    case .pen: return "Draw freely on your capture · Hold ⇧ for a straight line"
    case .arrow: return "New arrows cycle colors · Choose a swatch to override · ⇧ snaps angles"
    case .note: return "Click anywhere to anchor a text note"
    } }
}

final class CanvasView: FlippedView {
    var document: CaptureDocument? { didSet { arrowColorOverride = nil; selectedID = nil; draft = nil; pan = .zero; needsDisplay = true } }
    var tool: EditorTool = .arrow { didSet { window?.invalidateCursorRects(for: self); needsDisplay = true } }
    var ink = InkColor.coral
    private var arrowColorOverride: InkColor?
    var activeInk: InkColor {
        guard tool == .arrow else { return ink }
        if let arrowColorOverride { return arrowColorOverride }
        // Derive the next color from saved arrows so undo, redo, and reopening stay in sync.
        guard let previous = document?.annotations.last(where: { $0.kind == .arrow })?.color,
              let index = InkColor.palette.firstIndex(of: previous) else { return .coral }
        return InkColor.palette[(index + 1) % InkColor.palette.count]
    }
    func chooseInk(_ color: InkColor) {
        ink = color
        if tool == .arrow { arrowColorOverride = color }
    }
    var strokeWidth: CGFloat = 4
    var selectedID: UUID? { didSet { needsDisplay = true; onSelection?() } }
    var onChange: (() -> Void)?
    var onSelection: (() -> Void)?
    var onNote: ((CGPoint, Annotation?) -> Void)?
    var onTool: ((EditorTool) -> Void)?
    var draft: Annotation?
    private var dragStart: CGPoint?
    private var originalAnnotation: Annotation?
    private var movedAnnotation: Annotation?
    private var pan: CGPoint = .zero
    var zoom: CGFloat = 1 { didSet { pan = .zero; needsDisplay = true } }
    var usesActualSize = false { didSet { pan = .zero; needsDisplay = true } }
    var imageRect: CGRect {
        guard let size = document?.pixelSize, size.width > 0, size.height > 0 else { return .zero }
        let scale = usesActualSize ? 1 / (window?.backingScaleFactor ?? 1) : min(max(1, bounds.width - 64) / size.width, max(1, bounds.height - 64) / size.height, 1) * zoom
        return CGRect(x: (bounds.width - size.width * scale) / 2 + pan.x, y: (bounds.height - size.height * scale) / 2 + pan.y, width: size.width * scale, height: size.height * scale)
    }
    var imageScale: CGFloat { guard let document else { return 1 }; return imageRect.width / document.pixelSize.width }
    override var acceptsFirstResponder: Bool { true }
    // Canvas drags belong to annotation tools, never to AppKit window dragging.
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.canvas.setFill()
        bounds.fill()
        guard let document else { return }
        let rect = imageRect
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = CGSize(width: 0, height: -8)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        let transform = AffineTransform(translationByX: rect.minX, byY: rect.minY)
        (transform as NSAffineTransform).concat()
        let scale = AffineTransform(scale: imageScale)
        (scale as NSAffineTransform).concat()
        document.image.draw(in: CGRect(origin: .zero, size: document.pixelSize), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        for annotation in document.annotations {
            AnnotationRenderer.draw(movedAnnotation?.id == annotation.id ? movedAnnotation! : annotation, imageSize: document.pixelSize, selected: selectedID == annotation.id)
        }
        if let draft { AnnotationRenderer.draw(draft, imageSize: document.pixelSize) }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func imagePoint(_ event: NSEvent, clamped: Bool = false) -> CGPoint? {
        guard let document else { return nil }
        let local = convert(event.locationInWindow, from: nil)
        guard clamped || imageRect.contains(local) else { return nil }
        return CGPoint(x: min(max(0, (local.x - imageRect.minX) / imageScale), document.pixelSize.width), y: min(max(0, (local.y - imageRect.minY) / imageScale), document.pixelSize.height))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let document, let point = imagePoint(event) else { selectedID = nil; return }
        switch tool {
        case .select:
            let match = document.annotations.reversed().first { AnnotationRenderer.hitTest(point, annotation: $0, imageSize: document.pixelSize, tolerance: 8 / imageScale) }
            selectedID = match?.id
            if event.clickCount == 2, let match, match.kind == .note { onNote?(point, match); return }
            dragStart = point
            originalAnnotation = match
        case .note: onNote?(point, nil)
        case .pen, .arrow:
            selectedID = nil
            draft = Annotation(kind: tool == .pen ? .pen : .arrow, points: [point], color: activeInk, lineWidth: strokeWidth)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let point = imagePoint(event, clamped: true) else { return }
        if var annotation = draft {
            if annotation.kind == .arrow || event.modifierFlags.contains(.shift) {
                let start = annotation.points[0]
                var end = point
                if event.modifierFlags.contains(.shift) {
                    let angle = (atan2(point.y - start.y, point.x - start.x) / (.pi / 4)).rounded() * (.pi / 4)
                    let distance = hypot(point.x - start.x, point.y - start.y)
                    end = CGPoint(x: start.x + cos(angle) * distance, y: start.y + sin(angle) * distance)
                }
                annotation.points = [start, end]
            } else { annotation.points.append(point) }
            draft = annotation
        } else if let original = originalAnnotation, let start = dragStart, let document {
            var moved = original
            let rect = AnnotationRenderer.boundingRect(original, imageSize: document.pixelSize)
            let dx = max(-rect.minX, min(point.x - start.x, document.pixelSize.width - rect.maxX))
            let dy = max(-rect.minY, min(point.y - start.y, document.pixelSize.height - rect.maxY))
            moved.points = original.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            movedAnnotation = moved
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let document else { return }
        if let draft {
            if draft.kind == .pen || (draft.points.count > 1 && hypot(draft.points[0].x - draft.points[1].x, draft.points[0].y - draft.points[1].y) > 3) {
                document.replaceAnnotations(document.annotations + [draft])
                if draft.kind == .arrow { arrowColorOverride = nil }
                onChange?()
            }
        } else if let movedAnnotation {
            document.replaceAnnotations(document.annotations.map { $0.id == movedAnnotation.id ? movedAnnotation : $0 })
            onChange?()
        }
        draft = nil; movedAnnotation = nil; originalAnnotation = nil; dragStart = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { deleteSelected(); return }
        if event.keyCode == 53 { draft = nil; selectedID = nil; movedAnnotation = nil; originalAnnotation = nil; needsDisplay = true; return }
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { super.keyDown(with: event); return }
        if (123...126).contains(event.keyCode), selectedID != nil {
            let distance: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let delta: CGPoint
            switch event.keyCode {
            case 123: delta = CGPoint(x: -distance, y: 0)
            case 124: delta = CGPoint(x: distance, y: 0)
            case 125: delta = CGPoint(x: 0, y: distance)
            default: delta = CGPoint(x: 0, y: -distance)
            }
            moveSelection(by: delta)
            return
        }
        if event.keyCode == 36, let note = document?.annotations.first(where: { $0.id == selectedID }), note.kind == .note, let point = note.points.first {
            onNote?(point, note)
            return
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v": onTool?(.select)
        case "p": onTool?(.pen)
        case "a": onTool?(.arrow)
        case "t": onTool?(.note)
        default: super.keyDown(with: event)
        }
    }

    func moveSelection(by delta: CGPoint) {
        guard let document, let selectedID, var annotation = document.annotations.first(where: { $0.id == selectedID }) else { return }
        let rect = AnnotationRenderer.boundingRect(annotation, imageSize: document.pixelSize)
        let dx = max(-rect.minX, min(delta.x, document.pixelSize.width - rect.maxX))
        let dy = max(-rect.minY, min(delta.y, document.pixelSize.height - rect.maxY))
        guard dx != 0 || dy != 0 else { return }
        annotation.points = annotation.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        document.replaceAnnotations(document.annotations.map { $0.id == selectedID ? annotation : $0 })
        onChange?()
        needsDisplay = true
    }

    func deleteSelected() {
        guard let document, let selectedID else { return }
        document.replaceAnnotations(document.annotations.filter { $0.id != selectedID })
        self.selectedID = nil
        onChange?()
    }

    override func scrollWheel(with event: NSEvent) {
        let maxX = max(0, (imageRect.width - bounds.width) / 2 + 30)
        let maxY = max(0, (imageRect.height - bounds.height) / 2 + 30)
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        pan.x = min(maxX, max(-maxX, pan.x + event.scrollingDeltaX * multiplier))
        pan.y = min(maxY, max(-maxY, pan.y + event.scrollingDeltaY * multiplier))
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() { addCursorRect(imageRect, cursor: tool == .select ? .arrow : .crosshair) }
}
