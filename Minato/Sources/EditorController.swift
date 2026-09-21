import AppKit
import UniformTypeIdentifiers

@MainActor
final class EditorController: NSWindowController, NSWindowDelegate {
    private(set) var workspace: WorkspaceView!
    private(set) var documents: [CaptureDocument] = []
    private var store: CaptureStore?
    private let sample = SampleImage.make()
    private let captureCoordinator = ScreenCaptureCoordinator()
    private var notePopover: NSPopover?
    var showSettings: (() -> Void)?
    var currentDocument: CaptureDocument? { workspace.canvas.document }

    init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1320, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Minato"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = CGSize(width: 1080, height: 700)
        window.backgroundColor = Theme.background
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MinatoEditor")
        window.center()
        window.delegate = self
        workspace = WorkspaceView(controller: self)
        window.contentView = workspace
        workspace.canvas.onChange = { [weak self] in self?.didChange() }
        workspace.canvas.onSelection = { [weak self] in self?.refreshInspector() }
        workspace.canvas.onNote = { [weak self] point, annotation in self?.editNote(at: point, annotation: annotation) }
        workspace.canvas.onTool = { [weak self] in self?.selectTool($0) }
        do { store = try CaptureStore(); documents = try store!.load() }
        catch { DispatchQueue.main.async { [weak self] in self?.showError(error) } }
        selectDocument(documents.first ?? sample)
        selectTool(.arrow)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(workspace.canvas)
    }

    func capture() {
        guard notePopover == nil || notePopover?.isShown == false else { notePopover?.close(); return }
        workspace.statusLabel.stringValue = "Choose a region of your screen…"
        captureCoordinator.begin { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let image):
                if let image {
                    let name = "Capture " + Date().formatted(.dateTime.hour().minute())
                    self.addImage(image, title: name)
                } else { self.workspace.statusLabel.stringValue = "Capture canceled. Ready when you are." }
            case .failure(let error): self.show(); self.showError(error)
            }
        }
    }

    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .webP, .bmp, .gif]
        panel.allowsMultipleSelection = false
        panel.prompt = "Open image"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openImage(at: url)
        }
    }

    func openImage(at url: URL) {
        guard let image = NSImage(contentsOf: url), image.isValid, image.size.width > 0, image.size.height > 0 else {
            showError(MinatoError.message("Minato couldn’t read this image. Try a PNG, JPEG, TIFF, or HEIC file.")); return
        }
        addImage(image, title: url.deletingPathExtension().lastPathComponent)
    }

    func pasteImage() {
        guard let image = NSImage(pasteboard: .general) else { NSSound.beep(); return }
        addImage(image, title: "Pasted image")
    }

    private func addImage(_ image: NSImage, title: String) {
        let document = CaptureDocument(image: image, title: title)
        documents.insert(document, at: 0)
        selectDocument(document)
        persist()
        show()
    }

    func showSample() { selectDocument(sample) }

    func selectDocument(_ document: CaptureDocument) {
        notePopover?.close()
        workspace.canvas.document = document
        workspace.canvas.zoom = 1
        workspace.titleLabel.stringValue = document.metadata.title
        workspace.subtitleLabel.stringValue = "\(document.isSample ? "SAMPLE CAPTURE" : document.metadata.createdAt.formatted(date: .abbreviated, time: .shortened))   ·   \(Int(document.pixelSize.width)) × \(Int(document.pixelSize.height)) px"
        workspace.statusLabel.stringValue = document.isSample ? "A practice canvas. Make yourself at home." : "Saved on this Mac"
        workspace.fitButton.active = true; workspace.actualButton.active = false
        refreshLibrary()
        refreshInspector()
        workspace.canvas.needsDisplay = true
        window?.makeFirstResponder(workspace.canvas)
    }

    private func refreshLibrary() {
        workspace.captureList.subviews.forEach { $0.removeFromSuperview() }
        let list = documents.isEmpty ? [sample] : documents
        for (index, capture) in list.enumerated() {
            let row = CaptureRow(document: capture, selected: capture.metadata.id == currentDocument?.metadata.id)
            row.frame = CGRect(x: 0, y: index * 70, width: 184, height: 64)
            row.onChoose = { [weak self, weak capture] in if let capture { self?.selectDocument(capture) } }
            workspace.captureList.addSubview(row)
        }
        workspace.captureList.frame.size = CGSize(width: 184, height: CGFloat(list.count * 70))
    }

    func refreshInspector() {
        guard let document = currentDocument else { return }
        workspace.undoButton.isEnabled = document.canUndo
        workspace.redoButton.isEnabled = document.canRedo
        workspace.deleteButton.isEnabled = workspace.canvas.selectedID != nil
        workspace.annotationLabel.stringValue = "ANNOTATIONS   \(document.annotations.count)"
        workspace.annotationList.subviews.forEach { $0.removeFromSuperview() }
        if document.annotations.isEmpty {
            let label = Theme.text("Your ideas go here.\nChoose a tool to get started.", size: 11, color: Theme.secondary)
            label.maximumNumberOfLines = 2
            label.frame = CGRect(x: 12, y: 8, width: 164, height: 44)
            workspace.annotationList.addSubview(label)
        }
        for (index, annotation) in document.annotations.enumerated() {
            let row = AnnotationRow(annotation: annotation, index: index, selected: annotation.id == workspace.canvas.selectedID)
            row.frame = CGRect(x: 0, y: index * 56, width: 184, height: 52)
            row.onChoose = { [weak self] in
                guard let self else { return }
                self.selectTool(.select)
                self.workspace.canvas.selectedID = annotation.id
                if annotation.kind == .note { self.editNote(at: annotation.points[0], annotation: annotation) }
            }
            workspace.annotationList.addSubview(row)
        }
        workspace.annotationList.frame.size = CGSize(width: 186, height: CGFloat(max(1, document.annotations.count) * 56))
        let selected = document.annotations.first { $0.id == workspace.canvas.selectedID }
        let ink = selected?.color ?? workspace.canvas.activeInk
        workspace.colorLabel.stringValue = workspace.canvas.tool == .arrow && selected == nil ? "Next arrow color" : "Color"
        let width = selected?.lineWidth ?? workspace.canvas.strokeWidth
        for button in workspace.colorButtons { button.selected = button.ink == ink }
        for (index, button) in workspace.weightButtons.enumerated() { button.active = CGFloat([2, 4, 8][index]) == width }
    }

    func selectTool(_ tool: EditorTool) {
        workspace.canvas.tool = tool
        if tool != .select { workspace.canvas.selectedID = nil }
        workspace.toolButtons.forEach { $0.value.active = $0.key == tool }
        workspace.hintLabel.stringValue = tool.hint
        refreshInspector()
        window?.makeFirstResponder(workspace.canvas)
    }

    func chooseColor(_ color: InkColor) {
        workspace.canvas.chooseInk(color)
        if let document = currentDocument, let id = workspace.canvas.selectedID {
            document.replaceAnnotations(document.annotations.map { annotation in var value = annotation; if value.id == id { value.color = color }; return value })
            didChange()
        }
        refreshInspector()
    }

    func chooseWidth(_ width: CGFloat) {
        workspace.canvas.strokeWidth = width
        if let document = currentDocument, let id = workspace.canvas.selectedID {
            document.replaceAnnotations(document.annotations.map { annotation in var value = annotation; if value.id == id { value.lineWidth = width }; return value })
            didChange()
        }
        refreshInspector()
    }

    func undoEdit() { currentDocument?.undo(); workspace.canvas.selectedID = nil; didChange() }
    func redoEdit() { currentDocument?.redo(); workspace.canvas.selectedID = nil; didChange() }
    func deleteAnnotation() { workspace.canvas.deleteSelected() }

    func setZoom(actual: Bool) {
        workspace.canvas.zoom = 1
        if actual { workspace.canvas.zoom = 1 / workspace.canvas.imageScale / (window?.backingScaleFactor ?? 1) }
        workspace.fitButton.active = !actual
        workspace.actualButton.active = actual
        workspace.canvas.needsDisplay = true
    }

    private func didChange() {
        persist()
        refreshInspector()
        workspace.canvas.needsDisplay = true
    }

    private func persist() {
        guard let document = currentDocument else { return }
        do {
            guard let store else { throw MinatoError.message("Capture storage is unavailable. Export your image to keep a copy.") }
            try store.save(document)
            workspace.statusLabel.stringValue = document.isSample ? "Sample edited · Copy or export to keep it" : "All changes saved on this Mac"
        } catch { workspace.statusLabel.stringValue = "Couldn’t save changes"; showError(error) }
    }

    func copyImage() {
        guard let document = currentDocument else { return }
        do {
            let bitmap = try AnnotationRenderer.render(document)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw MinatoError.message("The image could not be copied.") }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            if let tiff = bitmap.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
            workspace.statusLabel.stringValue = "Copied! Ready to paste anywhere."
        } catch { showError(error) }
    }

    func exportImage() {
        guard let document = currentDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = document.metadata.title + ".png"
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let bitmap = try AnnotationRenderer.render(document)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { throw MinatoError.message("The PNG could not be created.") }
                try data.write(to: url, options: .atomic)
                self?.workspace.statusLabel.stringValue = "Exported \(url.lastPathComponent)"
            } catch { self?.showError(error) }
        }
    }

    func deleteCapture() {
        guard let document = currentDocument, !document.isSample else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this capture?"
        alert.informativeText = "“\(document.metadata.title)” and its editable annotations will be removed from Minato. Exported images are kept."
        alert.addButton(withTitle: "Delete Capture")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window!) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do {
                try self.store?.delete(document)
                self.documents.removeAll { $0.metadata.id == document.metadata.id }
                self.selectDocument(self.documents.first ?? self.sample)
            } catch { self.showError(error) }
        }
    }

    private func editNote(at point: CGPoint, annotation: Annotation?) {
        guard let document = currentDocument else { return }
        notePopover?.close()
        let editor = NoteEditor(text: annotation?.text ?? "")
        let popover = NSPopover()
        popover.contentViewController = editor
        popover.behavior = .semitransient
        popover.contentSize = CGSize(width: 300, height: 222)
        notePopover = popover
        editor.onCancel = { [weak popover] in popover?.close() }
        editor.onSave = { [weak self, weak document, weak popover] text in
            guard let self, let document, document === self.currentDocument else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            var note = annotation ?? Annotation(kind: .note, points: [point], color: self.workspace.canvas.ink)
            note.text = String(trimmed.prefix(500))
            if note.points.count == 1 { note.points.append(AnnotationRenderer.noteRect(note, imageSize: document.pixelSize).origin) }
            if annotation == nil { document.replaceAnnotations(document.annotations + [note]) }
            else { document.replaceAnnotations(document.annotations.map { $0.id == note.id ? note : $0 }) }
            self.didChange()
            popover?.close()
            self.window?.makeFirstResponder(self.workspace.canvas)
        }
        let rect = workspace.canvas.imageRect
        let local = CGPoint(x: rect.minX + point.x * workspace.canvas.imageScale, y: rect.minY + point.y * workspace.canvas.imageScale)
        let visible = workspace.canvas.bounds.insetBy(dx: 8, dy: 8)
        popover.show(relativeTo: CGRect(x: min(max(local.x, visible.minX), visible.maxX), y: min(max(local.y, visible.minY), visible.maxY), width: 1, height: 1), of: workspace.canvas, preferredEdge: .maxX)
        popover.contentViewController?.view.window?.makeFirstResponder(editor.textView)
    }

    func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window, window.attachedSheet == nil { alert.beginSheetModal(for: window) }
        else { alert.runModal() }
    }
}

private final class NoteEditor: NSViewController, NSTextViewDelegate {
    let textView = NoteTextView()
    var onSave: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private let initialText: String
    private var saveButton: ActionButton!
    init(text: String) { initialText = text; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = FlippedView(frame: CGRect(x: 0, y: 0, width: 300, height: 222))
        let label = Theme.text(initialText.isEmpty ? "Add a little context" : "Edit your note", size: 14, weight: .semibold)
        label.frame = CGRect(x: 18, y: 17, width: 264, height: 24)
        view.addSubview(label)
        let scroll = NSScrollView(frame: CGRect(x: 18, y: 53, width: 264, height: 108))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        textView.frame = CGRect(x: 0, y: 0, width: 260, height: 106)
        textView.minSize = CGSize(width: 0, height: 106)
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = CGSize(width: 8, height: 8)
        textView.font = .systemFont(ofSize: 14)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.string = initialText
        textView.delegate = self
        textView.setAccessibilityLabel("Note text")
        textView.onCommit = { [weak self] in guard let self else { return }; self.onSave?(self.textView.string) }
        scroll.documentView = textView
        view.addSubview(scroll)
        let cancel = ActionButton("Cancel") { [weak self] in self?.onCancel?() }
        cancel.frame = CGRect(x: 18, y: 177, width: 85, height: 30)
        view.addSubview(cancel)
        saveButton = ActionButton("Save note", primary: true) { [weak self] in guard let self else { return }; self.onSave?(self.textView.string) }
        saveButton.frame = CGRect(x: 178, y: 177, width: 104, height: 30)
        saveButton.toolTip = "Save note (⌘Return)"
        saveButton.isEnabled = !initialText.isEmpty
        view.addSubview(saveButton)
    }
    func textDidChange(_ notification: Notification) { saveButton.isEnabled = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString else { return true }
        return (textView.string as NSString).replacingCharacters(in: affectedCharRange, with: replacementString).count <= 500
    }
}

private final class NoteTextView: NSTextView {
    var onCommit: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && event.modifierFlags.contains(.command) { onCommit?(); return }
        super.keyDown(with: event)
    }
}
