import AppKit

/// Native split panes keep the screenshot central and allow each side panel to be resized or hidden.
final class WorkspaceController: NSSplitViewController, NSTableViewDataSource, NSTableViewDelegate {
    let canvas = CanvasView()
    let statusLabel = Theme.text("", size: 11, color: Theme.secondary)
    let hintLabel = Theme.text("", size: 11, color: Theme.secondary)
    let annotationLabel = Theme.text("Annotations", weight: .semibold)
    let colorLabel = Theme.text("Color")
    let captureTable = NSTableView()
    let annotationTable = AnnotationTableView()
    let emptyLabel = Theme.text("No annotations\nChoose a tool to get started.", size: 12, color: Theme.secondary)
    let widthControl = NSSegmentedControl(labels: ["2 px", "4 px", "8 px"], trackingMode: .selectOne, target: nil, action: nil)
    let zoomControl = NSSegmentedControl(labels: ["Fit", "100%"], trackingMode: .selectOne, target: nil, action: nil)
    var settingsButton: ActionButton!
    var deleteButton: ActionButton!
    var editNoteButton: ActionButton!
    private(set) var colorButtons: [ColorButton] = []
    private(set) var sidebarItem: NSSplitViewItem!
    private(set) var inspectorItem: NSSplitViewItem!
    private weak var editor: EditorController?
    private var captures: [CaptureDocument] = []
    private var annotations: [Annotation] = []
    private var updatingSelection = false

    init(controller: EditorController) {
        editor = controller
        super.init(nibName: nil, bundle: nil)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = "MinatoEditorPanes"
        let library = NSViewController()
        library.view = makeLibrary()
        library.view.translatesAutoresizingMaskIntoConstraints = false
        sidebarItem = NSSplitViewItem(sidebarWithViewController: library)
        sidebarItem.minimumThickness = 190
        sidebarItem.maximumThickness = 320
        sidebarItem.preferredThicknessFraction = 0.19
        // Keep panels steadier than the canvas, but below AppKit’s divider-drag priority.
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)
        sidebarItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        addSplitViewItem(sidebarItem)

        let content = NSViewController()
        content.view = makeCanvas()
        content.view.translatesAutoresizingMaskIntoConstraints = false
        let contentItem = NSSplitViewItem(viewController: content)
        contentItem.minimumThickness = 360
        addSplitViewItem(contentItem)

        let inspector = NSViewController()
        inspector.view = makeInspector()
        inspector.view.translatesAutoresizingMaskIntoConstraints = false
        inspectorItem = NSSplitViewItem(inspectorWithViewController: inspector)
        inspectorItem.minimumThickness = 224
        inspectorItem.maximumThickness = 320
        inspectorItem.preferredThicknessFraction = 0.2
        inspectorItem.holdingPriority = NSLayoutConstraint.Priority(260)
        inspectorItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        addSplitViewItem(inspectorItem)
        view.setAccessibilityLabel("Screenshot editor")
    }
    required init?(coder: NSCoder) { fatalError() }

    private func makeLibrary() -> NSView {
        let root = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 220, height: 700))
        root.material = .sidebar
        root.blendingMode = .behindWindow
        let label = Theme.text("Captures", weight: .semibold, color: Theme.secondary)
        let scroll = configureTable(captureTable, label: "Captures", style: .sourceList, rowHeight: 64)
        settingsButton = ActionButton("Settings…", symbol: "keyboard") { [weak editor] in editor?.showSettings?() }
        let sampleButton = ActionButton("Open Sample", symbol: "photo") { [weak editor] in editor?.showSample() }
        for child in [label, scroll, sampleButton, settingsButton!] { add(child, to: root) }
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 18),
            label.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: sampleButton.topAnchor, constant: -16),
            sampleButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            sampleButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            sampleButton.bottomAnchor.constraint(equalTo: settingsButton.topAnchor, constant: -8),
            settingsButton.leadingAnchor.constraint(equalTo: sampleButton.leadingAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: sampleButton.trailingAnchor),
            settingsButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        return root
    }

    private func makeCanvas() -> NSView {
        let root = Surface(Theme.background)
        root.frame = CGRect(x: 0, y: 0, width: 700, height: 700)
        zoomControl.controlSize = .small
        zoomControl.selectedSegment = 0
        zoomControl.target = self
        zoomControl.action = #selector(changeZoom)
        zoomControl.setAccessibilityLabel("Image zoom")
        zoomControl.setToolTip("Fit Image (⌘0)", forSegment: 0)
        zoomControl.setToolTip("Actual Size (⌘1)", forSegment: 1)
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let separator = NSBox(); separator.boxType = .separator
        for child in [canvas, separator, hintLabel, statusLabel, zoomControl] { add(child, to: root) }
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: separator.topAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -60),
            hintLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            hintLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            hintLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: hintLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: zoomControl.leadingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: zoomControl.centerYAnchor),
            zoomControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            zoomControl.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8)
        ])
        canvas.setAccessibilityElement(true)
        canvas.setAccessibilityRole(.layoutArea)
        canvas.setAccessibilityLabel("Screenshot annotation canvas")
        canvas.setAccessibilityHelp("Use the Tools menu to choose a tool. Select annotations in the inspector; arrow keys move the selection and Delete removes it.")
        return root
    }

    private func makeInspector() -> NSView {
        let root = Surface(Theme.background)
        root.frame = CGRect(x: 0, y: 0, width: 240, height: 700)
        let heading = Theme.text("Style", weight: .semibold)
        let weightLabel = Theme.text("Stroke Width")
        let palette = NSStackView()
        palette.orientation = .horizontal
        palette.spacing = 4
        palette.distribution = .fillEqually
        palette.setHuggingPriority(.defaultLow, for: .horizontal)
        palette.setClippingResistancePriority(.defaultLow, for: .horizontal)
        palette.setAccessibilityLabel("Annotation colors")
        for ink in InkColor.palette {
            let button = ColorButton(ink)
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
            button.onChoose = { [weak editor] in editor?.chooseColor($0) }
            colorButtons.append(button)
            palette.addArrangedSubview(button)
        }
        widthControl.target = self
        widthControl.action = #selector(changeWidth)
        widthControl.setAccessibilityLabel("Stroke width in image pixels")
        widthControl.segmentDistribution = .fillEqually
        let divider = NSBox(); divider.boxType = .separator
        let scroll = configureTable(annotationTable, label: "Annotations", style: .fullWidth, rowHeight: 54)
        annotationTable.onDelete = { [weak editor] in editor?.deleteAnnotation() }
        annotationTable.onEdit = { [weak editor] in editor?.editSelectedNote() }
        annotationTable.target = self
        annotationTable.doubleAction = #selector(editNote)
        emptyLabel.maximumNumberOfLines = 2
        emptyLabel.alignment = .center
        emptyLabel.lineBreakMode = .byWordWrapping
        editNoteButton = ActionButton("Edit Note…") { [weak editor] in editor?.editSelectedNote() }
        deleteButton = ActionButton("Delete", symbol: "trash") { [weak editor] in editor?.deleteAnnotation() }
        let actions = NSStackView(views: [editNoteButton, deleteButton])
        actions.distribution = .fill
        actions.setHuggingPriority(.defaultLow, for: .horizontal)
        actions.spacing = 8
        for child in [heading, colorLabel, palette, weightLabel, widthControl, divider, annotationLabel, scroll, emptyLabel, actions] { add(child, to: root) }
        for child in [heading, colorLabel, palette, weightLabel, widthControl, divider, annotationLabel, actions] {
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
                child.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16)
            ])
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 18),
            colorLabel.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 20),
            palette.topAnchor.constraint(equalTo: colorLabel.bottomAnchor, constant: 8),
            palette.heightAnchor.constraint(equalToConstant: 30),
            weightLabel.topAnchor.constraint(equalTo: palette.bottomAnchor, constant: 18),
            widthControl.topAnchor.constraint(equalTo: weightLabel.bottomAnchor, constant: 8),
            divider.topAnchor.constraint(equalTo: widthControl.bottomAnchor, constant: 22),
            annotationLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 18),
            scroll.topAnchor.constraint(equalTo: annotationLabel.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -12),
            emptyLabel.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 24),
            emptyLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            actions.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        return root
    }

    private func add(_ child: NSView, to parent: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
    }

    private func configureTable(_ table: NSTableView, label: String, style: NSTableView.Style, rowHeight: CGFloat) -> NSScrollView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = style
        table.backgroundColor = .clear
        table.rowHeight = rowHeight
        table.intercellSpacing = CGSize(width: 0, height: 2)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel(label)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table
        return scroll
    }

    func updateLibrary(_ documents: [CaptureDocument], selectedID: UUID?) {
        updatingSelection = true
        defer { updatingSelection = false }
        captures = documents
        captureTable.reloadData()
        selectRow(captures.firstIndex { $0.metadata.id == selectedID }, in: captureTable)
    }

    func updateAnnotations(_ values: [Annotation], selectedID: UUID?) {
        updatingSelection = true
        defer { updatingSelection = false }
        if annotations != values { annotations = values; annotationTable.reloadData() }
        selectRow(annotations.firstIndex { $0.id == selectedID }, in: annotationTable)
        emptyLabel.isHidden = !values.isEmpty
        annotationLabel.stringValue = "Annotations (\(values.count))"
    }

    private func selectRow(_ row: Int?, in table: NSTableView) {
        table.selectRowIndexes(row.map { IndexSet(integer: $0) } ?? [], byExtendingSelection: false)
        if let row { table.scrollRowToVisible(row) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === captureTable ? captures.count : annotations.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = LibraryCell(isCapture: tableView === captureTable)
        if tableView === captureTable {
            let capture = captures[row]
            cell.heading.stringValue = capture.isSample ? "Sample Capture" : capture.metadata.title
            cell.detail.stringValue = capture.isSample ? "Practice with the tools" : capture.metadata.createdAt.formatted(date: .abbreviated, time: .shortened)
            cell.preview.image = capture.image
            cell.setAccessibilityLabel("\(cell.heading.stringValue), \(cell.detail.stringValue)")
        } else {
            let annotation = annotations[row]
            cell.heading.stringValue = "\(annotation.kind.title) \(row + 1)"
            cell.detail.stringValue = annotation.kind == .note ? annotation.text : "\(annotation.color.name) · \(Int(annotation.lineWidth)) px"
            let symbol = annotation.kind.symbol
            cell.preview.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            cell.preview.contentTintColor = annotation.color.nsColor
            cell.setAccessibilityLabel("\(cell.heading.stringValue), \(cell.detail.stringValue)" + (annotation.kind == .note ? ", \(annotation.color.name)" : ""))
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingSelection, let table = notification.object as? NSTableView, table.selectedRow >= 0 else { return }
        if table === captureTable { editor?.selectDocument(captures[table.selectedRow], focusCanvas: false) }
        else { editor?.selectAnnotation(annotations[table.selectedRow].id) }
    }
    @objc private func changeWidth() { editor?.chooseWidth(CGFloat([2, 4, 8][widthControl.selectedSegment])) }
    @objc private func changeZoom() { editor?.setZoom(actual: zoomControl.selectedSegment == 1) }
    @objc private func editNote() { editor?.editSelectedNote() }
}

final class AnnotationTableView: NSTableView {
    var onDelete: (() -> Void)?
    var onEdit: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { onDelete?(); return }
        if event.keyCode == 36 { onEdit?(); return }
        super.keyDown(with: event)
    }
}

private final class LibraryCell: NSTableCellView {
    let heading = Theme.text("", weight: .medium)
    let detail = Theme.text("", size: 11, color: Theme.secondary)
    let preview = NSImageView()
    init(isCapture: Bool) {
        super.init(frame: .zero)
        textField = heading
        imageView = preview
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setAccessibilityElement(false)
        for child in [heading, detail, preview] { child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child) }
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            preview.centerYAnchor.constraint(equalTo: centerYAnchor),
            preview.widthAnchor.constraint(equalToConstant: isCapture ? 44 : 24),
            preview.heightAnchor.constraint(equalToConstant: isCapture ? 40 : 24),
            heading.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 10),
            heading.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            heading.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            detail.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            detail.topAnchor.constraint(equalTo: centerYAnchor, constant: 3)
        ])
        heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            heading.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : Theme.ink
            detail.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : Theme.secondary
        }
    }
}
