import AppKit

/// System toolbar items get native appearance, overflow, customization, and accessibility.
@MainActor
final class EditorToolbar: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "MinatoEditorToolbar")
    private weak var editor: EditorController?
    private var toolGroup: NSToolbarItemGroup?
    private static let sidebar = NSToolbarItem.Identifier("sidebar")
    private static let capture = NSToolbarItem.Identifier("capture")
    private static let open = NSToolbarItem.Identifier("open")
    private static let tools = NSToolbarItem.Identifier("tools")
    private static let undo = NSToolbarItem.Identifier("undo")
    private static let redo = NSToolbarItem.Identifier("redo")
    private static let copy = NSToolbarItem.Identifier("copy")
    private static let export = NSToolbarItem.Identifier("export")
    private static let inspector = NSToolbarItem.Identifier("inspector")

    init(editor: EditorController) {
        self.editor = editor
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebar, Self.capture, Self.open, .flexibleSpace, Self.tools, .flexibleSpace, Self.copy, Self.export, Self.inspector]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebar, Self.capture, Self.open, Self.tools, Self.undo, Self.redo, Self.copy, Self.export, Self.inspector, .flexibleSpace, .space]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == Self.tools {
            let tools = EditorTool.allCases
            let group = NSToolbarItemGroup(itemIdentifier: id, images: tools.map { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: $0.title)! }, selectionMode: .selectOne, labels: tools.map(\.title), target: self, action: #selector(changeTool))
            group.label = "Annotation Tools"
            group.paletteLabel = "Annotation Tools"
            group.selectedIndex = tools.firstIndex(of: editor?.workspace.canvas.tool ?? .arrow) ?? 2
            for (index, item) in group.subitems.enumerated() { item.toolTip = "\(tools[index].title) (\(["V", "P", "A", "T"][index]))" }
            if flag { toolGroup = group }
            return group
        }
        let item = NSToolbarItem(itemIdentifier: id)
        let values: (String, String, Selector)
        switch id {
        case Self.sidebar: values = ("Sidebar", "sidebar.left", #selector(toggleSidebar))
        case Self.capture: values = ("New Capture", "viewfinder", #selector(capture))
        case Self.open: values = ("Open Image…", "photo.badge.plus", #selector(openImage))
        case Self.undo: values = ("Undo", "arrow.uturn.backward", #selector(undo))
        case Self.redo: values = ("Redo", "arrow.uturn.forward", #selector(redo))
        case Self.copy: values = ("Copy Image", "doc.on.doc", #selector(copyImage))
        case Self.export: values = ("Export PNG…", "square.and.arrow.up", #selector(exportImage))
        case Self.inspector: values = ("Inspector", "sidebar.right", #selector(toggleInspector))
        default: return nil
        }
        item.label = values.0
        item.paletteLabel = values.0
        item.toolTip = values.0
        item.image = NSImage(systemSymbolName: values.1, accessibilityDescription: values.0)
        item.target = self
        item.action = values.2
        item.autovalidates = false
        if id == Self.undo { item.isEnabled = editor?.currentDocument?.canUndo == true }
        if id == Self.redo { item.isEnabled = editor?.currentDocument?.canRedo == true }
        return item
    }
    func update() {
        guard let editor else { return }
        toolGroup?.selectedIndex = EditorTool.allCases.firstIndex(of: editor.workspace.canvas.tool) ?? 0
        for item in toolbar.items {
            if item.itemIdentifier == Self.undo { item.isEnabled = editor.currentDocument?.canUndo == true }
            if item.itemIdentifier == Self.redo { item.isEnabled = editor.currentDocument?.canRedo == true }
        }
    }
    @objc private func changeTool(_ sender: NSToolbarItemGroup) {
        guard EditorTool.allCases.indices.contains(sender.selectedIndex) else { return }
        editor?.selectTool(EditorTool.allCases[sender.selectedIndex])
    }
    @objc private func toggleSidebar() { editor?.workspace.toggleSidebar(nil) }
    @objc private func toggleInspector() { editor?.workspace.toggleInspector(nil) }
    @objc private func capture() { editor?.capture() }
    @objc private func openImage() { editor?.openImage() }
    @objc private func undo() { editor?.undoEdit() }
    @objc private func redo() { editor?.redoEdit() }
    @objc private func copyImage() { editor?.copyImage() }
    @objc private func exportImage() { editor?.exportImage() }
}
