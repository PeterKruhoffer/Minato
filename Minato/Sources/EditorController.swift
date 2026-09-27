import AppKit
import UniformTypeIdentifiers

@MainActor
final class EditorController: NSWindowController, NSWindowDelegate {
    private(set) var workspace: WorkspaceController!
    private var editorToolbar: EditorToolbar!
    private(set) var documents: [CaptureDocument] = []
    private var store: CaptureStore?
    private let sample = SampleImage.make()
    private let captureCoordinator = ScreenCaptureCoordinator()
    private var notePopover: NSPopover?
    var showSettings: (() -> Void)?
    var currentDocument: CaptureDocument? { workspace.canvas.document }

    init(captureStore: CaptureStore? = nil, restoresWindow: Bool = true) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1320, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Minato"
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = false
        window.minSize = CGSize(width: 820, height: 560)
        window.backgroundColor = Theme.background
        window.isReleasedWhenClosed = false
        window.delegate = self
        workspace = WorkspaceController(controller: self)
        window.contentViewController = workspace
        editorToolbar = EditorToolbar(editor: self)
        window.toolbar = editorToolbar.toolbar
        window.setContentSize(CGSize(width: 1320, height: 780))
        window.center()
        if restoresWindow {
            window.setFrameAutosaveName("MinatoNativeEditor")
            window.setFrameUsingName("MinatoNativeEditor")
        }
        workspace.canvas.onChange = { [weak self] in self?.didChange() }
        workspace.canvas.onSelection = { [weak self] in self?.refreshInspector() }
        workspace.canvas.onNote = { [weak self] point, annotation in self?.editNote(at: point, annotation: annotation) }
        workspace.canvas.onTool = { [weak self] in self?.selectTool($0) }
        do { store = try captureStore ?? CaptureStore(); documents = try store!.load() }
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
                } else { self.workspace.statusLabel.stringValue = "Capture canceled" }
            case .failure(let error): self.show(); self.showError(error)
            }
        }
    }

    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .webP, .bmp, .gif]
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
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

    func selectDocument(_ document: CaptureDocument, focusCanvas: Bool = true) {
        notePopover?.close()
        workspace.canvas.document = document
        workspace.canvas.zoom = 1
        workspace.canvas.usesActualSize = false
        window?.title = document.isSample ? "Sample Capture" : document.metadata.title
        window?.subtitle = "\(document.isSample ? "Sample" : document.metadata.createdAt.formatted(date: .abbreviated, time: .shortened))   ·   \(Int(document.pixelSize.width)) × \(Int(document.pixelSize.height)) px"
        workspace.statusLabel.stringValue = document.isSample ? "Sample · Copy or export to keep your edits" : "Saved on this Mac"
        workspace.zoomControl.selectedSegment = 0
        refreshLibrary()
        refreshInspector()
        workspace.canvas.needsDisplay = true
        if focusCanvas { window?.makeFirstResponder(workspace.canvas) }
    }

    private func refreshLibrary() {
        workspace.updateLibrary(documents.isEmpty ? [sample] : documents, selectedID: currentDocument?.metadata.id)
    }

    func refreshInspector() {
        guard let document = currentDocument else { return }
        editorToolbar?.update()
        workspace.deleteButton.isEnabled = workspace.canvas.selectedID != nil
        workspace.updateAnnotations(document.annotations, selectedID: workspace.canvas.selectedID)
        let selected = document.annotations.first { $0.id == workspace.canvas.selectedID }
        let ink = selected?.color ?? workspace.canvas.activeInk
        workspace.colorLabel.stringValue = workspace.canvas.tool == .arrow && selected == nil ? "Next arrow color" : "Color"
        let width = selected?.lineWidth ?? workspace.canvas.strokeWidth
        for button in workspace.colorButtons { button.selected = button.ink == ink }
        workspace.widthControl.selectedSegment = [CGFloat(2), 4, 8].firstIndex(of: width) ?? -1
        workspace.widthControl.isEnabled = selected?.kind != .note && (selected != nil || workspace.canvas.tool != .note)
        workspace.editNoteButton.isEnabled = selected?.kind == .note
        workspace.canvas.setAccessibilityValue("\(document.annotations.count) annotations; \(workspace.canvas.tool.title) tool")
    }

    func selectTool(_ tool: EditorTool, focusCanvas: Bool = true) {
        workspace.canvas.tool = tool
        if tool != .select { workspace.canvas.selectedID = nil }
        workspace.hintLabel.stringValue = tool.hint
        workspace.hintLabel.toolTip = tool.hint
        refreshInspector()
        if focusCanvas { window?.makeFirstResponder(workspace.canvas) }
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
        workspace.canvas.usesActualSize = actual
        workspace.zoomControl.selectedSegment = actual ? 1 : 0
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
            workspace.statusLabel.stringValue = "Image copied to clipboard"
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

    func selectAnnotation(_ id: UUID) {
        selectTool(.select, focusCanvas: false)
        workspace.canvas.selectedID = id
    }

    func editSelectedNote() {
        guard let note = currentDocument?.annotations.first(where: { $0.id == workspace.canvas.selectedID }), note.kind == .note, let point = note.points.first else { return }
        editNote(at: point, annotation: note)
    }

    func addNoteAtCenter() {
        guard let size = currentDocument?.pixelSize else { return }
        editNote(at: CGPoint(x: size.width / 2, y: size.height / 2), annotation: nil)
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
        let label = Theme.text(initialText.isEmpty ? "Add Note" : "Edit Note", size: 14, weight: .semibold)
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
        cancel.keyEquivalent = "\u{1b}"
        view.addSubview(cancel)
        saveButton = ActionButton("Save Note", primary: true) { [weak self] in guard let self else { return }; self.onSave?(self.textView.string) }
        saveButton.frame = CGRect(x: 178, y: 177, width: 104, height: 30)
        saveButton.toolTip = "Save Note (⌘Return)"
        saveButton.keyEquivalent = "\r"
        saveButton.keyEquivalentModifierMask = .command
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
