import AppKit

final class WorkspaceView: FlippedView {
    let sidebar = Surface(Theme.sidebar)
    let canvas = CanvasView()
    let inspector = Surface(Theme.background)
    let titleLabel = Theme.text("A little room for feedback", size: 24, weight: .semibold)
    let subtitleLabel = Theme.text("Sample capture", size: 12, color: Theme.secondary)
    let statusLabel = Theme.text("Your ideas, a little clearer.", size: 11, color: Theme.secondary)
    let hintLabel = Theme.text("", size: 11, color: Theme.secondary)
    let zoomLabel = Theme.text("Fit", size: 11, weight: .medium, color: Theme.secondary)
    let annotationLabel = Theme.text("ANNOTATIONS", size: 10, weight: .semibold, color: Theme.secondary)
    let captureScroll = NSScrollView()
    let captureList = FlippedView()
    let annotationScroll = NSScrollView()
    let annotationList = FlippedView()
    let brand = Theme.text("minato", size: 25, weight: .bold)
    let tagline = Theme.text("Make your point.", size: 11, color: Theme.secondary)
    let libraryLabel = Theme.text("YOUR WORKSPACE", size: 10, weight: .semibold, color: Theme.secondary)
    let styleLabel = Theme.text("STYLE", size: 10, weight: .semibold, color: Theme.secondary)
    let colorLabel = Theme.text("Color", size: 12, weight: .medium)
    let weightLabel = Theme.text("Stroke", size: 12, weight: .medium)
    let noteHelp = Theme.text("Little details.\nBig understanding.", size: 16, weight: .medium)
    let noteHelpDetail = Theme.text("Draw, point, or leave a note.\nA little context goes a long way.", size: 11, color: Theme.secondary)
    var captureButton: ActionButton!
    var openButton: ActionButton!
    var sampleButton: ActionButton!
    var copyButton: ActionButton!
    var exportButton: ActionButton!
    var undoButton: ActionButton!
    var redoButton: ActionButton!
    var settingsButton: ActionButton!
    var fitButton: ActionButton!
    var actualButton: ActionButton!
    var deleteButton: ActionButton!
    var toolButtons: [EditorTool: ActionButton] = [:]
    var colorButtons: [ColorButton] = []
    var weightButtons: [ActionButton] = []
    private let toolbar = Surface(.white, radius: 11)
    private let brandMark = BrandMark()
    private let tip = Surface(NSColor(hex: 0xF0EEE8), radius: 12)

    init(controller: EditorController) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.background.cgColor
        captureButton = ActionButton("New capture", symbol: "viewfinder", primary: true) { [weak controller] in controller?.capture() }
        openButton = ActionButton("Open image", symbol: "plus") { [weak controller] in controller?.openImage() }
        sampleButton = ActionButton("Try the sample", symbol: "sparkles") { [weak controller] in controller?.showSample() }
        copyButton = ActionButton("Copy", symbol: "doc.on.doc") { [weak controller] in controller?.copyImage() }
        exportButton = ActionButton("Export PNG", symbol: "arrow.up.right", primary: true) { [weak controller] in controller?.exportImage() }
        undoButton = ActionButton("Undo", symbol: "arrow.uturn.backward") { [weak controller] in controller?.undoEdit() }
        redoButton = ActionButton("Redo", symbol: "arrow.uturn.forward") { [weak controller] in controller?.redoEdit() }
        settingsButton = ActionButton("⇧⌘2", symbol: "keyboard") { [weak controller] in controller?.showSettings?() }
        fitButton = ActionButton("Fit") { [weak controller] in controller?.setZoom(actual: false) }
        actualButton = ActionButton("100%") { [weak controller] in controller?.setZoom(actual: true) }
        deleteButton = ActionButton("Delete", symbol: "trash") { [weak controller] in controller?.deleteAnnotation() }
        for tool in EditorTool.allCases {
            let button = ActionButton(tool.title, symbol: tool.symbol) { [weak controller] in controller?.selectTool(tool) }
            button.toolTip = "\(tool.title) (\([EditorTool.select: "V", .pen: "P", .arrow: "A", .note: "T"][tool]!))"
            toolbar.addSubview(button)
            toolButtons[tool] = button
        }
        for (index, ink) in InkColor.palette.enumerated() {
            let button = ColorButton(ink, name: ["Coral", "Violet", "Blue", "Green", "Amber", "Charcoal"][index])
            button.onChoose = { [weak controller] in controller?.chooseColor($0) }
            colorButtons.append(button)
            inspector.addSubview(button)
        }
        for width in [2, 4, 8] {
            let button = ActionButton("\(width) px") { [weak controller] in controller?.chooseWidth(CGFloat(width)) }
            weightButtons.append(button)
            inspector.addSubview(button)
        }
        undoButton.compact = true; redoButton.compact = true
        undoButton.toolTip = "Undo (⌘Z)"; redoButton.toolTip = "Redo (⇧⌘Z)"
        for view in [sidebar, canvas, inspector, titleLabel, subtitleLabel, copyButton!, exportButton!, toolbar, undoButton!, redoButton!, statusLabel, hintLabel, fitButton!, actualButton!] { addSubview(view) }
        for view in [brandMark, brand, tagline, captureButton!, openButton!, sampleButton!, libraryLabel, captureScroll, settingsButton!] { sidebar.addSubview(view) }
        for view in [styleLabel, colorLabel, weightLabel, annotationLabel, annotationScroll, deleteButton!, tip] { inspector.addSubview(view) }
        noteHelp.maximumNumberOfLines = 2
        noteHelp.lineBreakMode = .byWordWrapping
        noteHelpDetail.maximumNumberOfLines = 2
        noteHelpDetail.lineBreakMode = .byWordWrapping
        tip.addSubview(noteHelp); tip.addSubview(noteHelpDetail)
        configureScroll(captureScroll, document: captureList)
        configureScroll(annotationScroll, document: annotationList)
        canvas.setAccessibilityLabel("Screenshot annotation canvas")
        canvas.setAccessibilityHelp("Choose Draw, Arrow, or Note, then click or drag on the image. Use Select to move annotations.")
        setAccessibilityLabel("Minato workspace")
    }
    required init?(coder: NSCoder) { fatalError() }

    private func configureScroll(_ scroll: NSScrollView, document: NSView) {
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height, left: CGFloat = 208, right: CGFloat = 212
        sidebar.frame = CGRect(x: 0, y: 0, width: left, height: h)
        brandMark.frame = CGRect(x: 21, y: 67, width: 31, height: 31)
        brand.frame = CGRect(x: 61, y: 66, width: 123, height: 33)
        tagline.frame = CGRect(x: 23, y: 111, width: 160, height: 18)
        captureButton.frame = CGRect(x: 16, y: 156, width: 176, height: 40)
        openButton.frame = CGRect(x: 16, y: 202, width: 176, height: 35)
        libraryLabel.frame = CGRect(x: 23, y: 274, width: 164, height: 16)
        captureScroll.frame = CGRect(x: 12, y: 302, width: 184, height: max(100, h - 420))
        captureList.frame.size.width = 184
        sampleButton.frame = CGRect(x: 16, y: h - 101, width: 176, height: 33)
        settingsButton.frame = CGRect(x: 16, y: h - 55, width: 176, height: 34)
        titleLabel.frame = CGRect(x: left + 28, y: 51, width: w - left - 300, height: 35)
        subtitleLabel.frame = CGRect(x: left + 29, y: 92, width: w - left - 300, height: 20)
        copyButton.frame = CGRect(x: w - 232, y: 57, width: 87, height: 36)
        exportButton.frame = CGRect(x: w - 137, y: 57, width: 112, height: 36)
        let centerWidth = w - left - right
        toolbar.frame = CGRect(x: left + 24, y: 134, width: 345, height: 44)
        for (i, tool) in EditorTool.allCases.enumerated() { toolButtons[tool]?.frame = CGRect(x: 5 + CGFloat(i) * 84, y: 5, width: 82, height: 34) }
        undoButton.frame = CGRect(x: left + centerWidth - 92, y: 137, width: 34, height: 36)
        redoButton.frame = CGRect(x: left + centerWidth - 55, y: 137, width: 34, height: 36)
        canvas.frame = CGRect(x: left + 24, y: 195, width: centerWidth - 48, height: h - 290)
        canvas.wantsLayer = true
        canvas.layer?.cornerRadius = 10
        canvas.layer?.masksToBounds = true
        hintLabel.frame = CGRect(x: left + 27, y: h - 82, width: centerWidth - 48, height: 19)
        statusLabel.frame = CGRect(x: left + 27, y: h - 42, width: centerWidth - 170, height: 19)
        fitButton.frame = CGRect(x: left + centerWidth - 118, y: h - 48, width: 38, height: 28)
        actualButton.frame = CGRect(x: left + centerWidth - 78, y: h - 48, width: 54, height: 28)
        inspector.frame = CGRect(x: w - right, y: 134, width: right - 20, height: h - 157)
        styleLabel.frame = CGRect(x: 16, y: 12, width: 160, height: 16)
        colorLabel.frame = CGRect(x: 16, y: 46, width: 160, height: 20)
        for (i, button) in colorButtons.enumerated() { button.frame = CGRect(x: 12 + CGFloat(i) * 29, y: 76, width: 28, height: 28) }
        weightLabel.frame = CGRect(x: 16, y: 127, width: 160, height: 20)
        for (i, button) in weightButtons.enumerated() { button.frame = CGRect(x: 12 + CGFloat(i) * 57, y: 157, width: 54, height: 30) }
        annotationLabel.frame = CGRect(x: 16, y: 229, width: 168, height: 20)
        annotationScroll.frame = CGRect(x: 6, y: 264, width: 186, height: max(85, inspector.bounds.height - 451))
        annotationList.frame.size.width = 186
        deleteButton.frame = CGRect(x: 9, y: inspector.bounds.height - 181, width: 170, height: 32)
        tip.frame = CGRect(x: 10, y: inspector.bounds.height - 135, width: 179, height: 126)
        noteHelp.frame = CGRect(x: 15, y: 16, width: 153, height: 49)
        noteHelpDetail.frame = CGRect(x: 15, y: 78, width: 153, height: 35)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill(); bounds.fill()
        Theme.line.setFill()
        CGRect(x: 207, y: 0, width: 1, height: bounds.height).fill()
        CGRect(x: 232, y: 122, width: bounds.width - 258, height: 1).fill()
    }
}

final class CaptureRow: NSButton {
    let document: CaptureDocument
    var selected: Bool
    var onChoose: (() -> Void)?
    init(document: CaptureDocument, selected: Bool) {
        self.document = document; self.selected = selected
        super.init(frame: .zero)
        isBordered = false; target = self; action = #selector(choose)
        setAccessibilityLabel(document.metadata.title)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func choose() { onChoose?() }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        (selected ? NSColor.white : NSColor.clear).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 9, yRadius: 9).fill()
        if selected { Theme.line.setStroke(); NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 9, yRadius: 9).stroke() }
        let rect = CGRect(x: 12, y: 13, width: 48, height: 38)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
        NSColor.white.setFill(); rect.fill()
        document.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        Theme.drawText(document.isSample ? "Sample capture" : document.metadata.title, in: CGRect(x: 71, y: 15, width: 99, height: 18), size: 11, weight: .medium)
        let detail = document.isSample ? "Try the tools" : document.metadata.createdAt.formatted(date: .abbreviated, time: .shortened)
        Theme.drawText(detail, in: CGRect(x: 71, y: 35, width: 99, height: 16), size: 9, color: Theme.secondary)
    }
}

final class AnnotationRow: NSButton {
    let annotation: Annotation
    let index: Int
    var selected: Bool
    var onChoose: (() -> Void)?
    init(annotation: Annotation, index: Int, selected: Bool) {
        self.annotation = annotation; self.index = index; self.selected = selected
        super.init(frame: .zero)
        isBordered = false; target = self; action = #selector(choose)
        setAccessibilityLabel(annotation.kind == .note ? annotation.text : "\(annotation.kind.title) \(index + 1)")
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func choose() { onChoose?() }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        (selected ? Theme.accentLight : .clear).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 2), xRadius: 7, yRadius: 7).fill()
        annotation.color.nsColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: CGRect(x: 11, y: 11, width: 27, height: 27), xRadius: 6, yRadius: 6).fill()
        Theme.drawText("\(index + 1)", in: CGRect(x: 11, y: 17, width: 27, height: 18), size: 11, weight: .semibold, color: annotation.color.nsColor, alignment: .center)
        Theme.drawText(annotation.kind.title, in: CGRect(x: 48, y: 10, width: 127, height: 20), size: 11, weight: .medium)
        let description = annotation.kind == .note ? annotation.text : annotation.kind == .arrow ? "A nudge in the right direction" : "A little personal touch"
        Theme.drawText(description, in: CGRect(x: 48, y: 29, width: 123, height: 15), size: 9, color: Theme.secondary)
    }
}

private final class BrandMark: FlippedView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.accent.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        NSColor.white.setStroke()
        let path = NSBezierPath(); path.lineWidth = 2.5; path.lineCapStyle = .round; path.lineJoinStyle = .round
        path.move(to: CGPoint(x: 8, y: 22)); path.line(to: CGPoint(x: 8, y: 11)); path.line(to: CGPoint(x: 15.5, y: 18)); path.line(to: CGPoint(x: 23, y: 11)); path.line(to: CGPoint(x: 23, y: 22)); path.stroke()
    }
}
