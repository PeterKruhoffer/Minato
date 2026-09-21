import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var editor: EditorController!
    private let shortcuts = ShortcutManager()
    private var statusItem: NSStatusItem?
    private var settings: NSWindowController?
    private var shortcutRecorder: ShortcutRecorder?
    private var pendingFiles: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosted unit tests should not open windows or compete for the global shortcut.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        NSApp.setActivationPolicy(.regular)
        makeMenus()
        editor = EditorController()
        editor.showSettings = { [weak self] in self?.openSettings(nil) }
        shortcuts.onCapture = { [weak self] in
            guard let self, self.shortcutRecorder?.recording != true else { return }
            self.editor.capture()
        }
        editor.show()
        updateShortcutLabel()
        do { try shortcuts.register() }
        catch { editor.showError(error) }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Minato")
        status.button?.toolTip = "Minato — capture and annotate"
        let menu = NSMenu()
        menu.addItem(item("New Capture", #selector(newCapture), ""))
        menu.addItem(item("Show Minato", #selector(showEditor), ""))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ""))
        menu.addItem(item("Quit Minato", #selector(quit), "q"))
        status.menu = menu
        statusItem = status
        for path in pendingFiles { editor.openImage(at: URL(fileURLWithPath: path)) }
        pendingFiles.removeAll()
        if let openIndex = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.count > openIndex + 1 {
            editor.openImage(at: URL(fileURLWithPath: CommandLine.arguments[openIndex + 1]))
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { editor.show(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if editor == nil { pendingFiles.append(contentsOf: filenames) }
        else { for name in filenames { editor.openImage(at: URL(fileURLWithPath: name)) } }
        sender.reply(toOpenOrPrint: .success)
    }

    private func item(_ title: String, _ action: Selector, _ key: String, modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target ?? self
        return item
    }

    private func makeMenus() {
        let menu = NSMenu()
        let appMenu = NSMenu(title: "Minato")
        appMenu.addItem(item("About Minato", #selector(about), ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(openSettings), ","))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide Minato", #selector(NSApplication.hide(_:)), "h", target: NSApp))
        appMenu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option], target: NSApp))
        appMenu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:)), "", target: NSApp))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit Minato", #selector(quit), "q"))
        let app = NSMenuItem(); app.submenu = appMenu; menu.addItem(app)
        let file = NSMenu(title: "File")
        file.addItem(item("New Capture", #selector(newCapture), "n"))
        file.addItem(item("Open Image…", #selector(openImage), "o"))
        file.addItem(item("Try the Sample", #selector(showSample), ""))
        file.addItem(.separator())
        file.addItem(item("Export PNG…", #selector(exportImage), "s"))
        file.addItem(item("Copy Image", #selector(copyImage), "c", modifiers: [.command, .shift]))
        file.addItem(.separator())
        file.addItem(item("Delete Capture…", #selector(deleteCapture), ""))
        file.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w", target: nil))
        file.items.last?.target = nil
        let fileItem = NSMenuItem(); fileItem.submenu = file; menu.addItem(fileItem)
        let edit = NSMenu(title: "Edit")
        for (title, action, key, modifiers) in [
            ("Undo", "undo:", "z", NSEvent.ModifierFlags.command),
            ("Redo", "redo:", "z", [.command, .shift]),
            ("Cut", "cut:", "x", .command),
            ("Copy", "copy:", "c", .command),
            ("Paste", "paste:", "v", .command),
            ("Select All", "selectAll:", "a", .command)
        ] {
            let entry = NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)
            entry.keyEquivalentModifierMask = modifiers
            if action == "undo:" || action == "redo:" { entry.target = self }
            edit.addItem(entry)
        }
        let editItem = NSMenuItem(); editItem.submenu = edit; menu.addItem(editItem)
        let window = NSMenu(title: "Window")
        let minimize = NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(minimize)
        window.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        let windowItem = NSMenuItem(); windowItem.submenu = window; menu.addItem(windowItem)
        NSApp.windowsMenu = window
        NSApp.mainMenu = menu
    }

    private func updateShortcutLabel() {
        editor.workspace.settingsButton.title = shortcuts.shortcut.display
        editor.workspace.settingsButton.setAccessibilityLabel("Capture shortcut \(shortcuts.shortcut.display). Open settings.")
        editor.workspace.settingsButton.toolTip = "Global capture shortcut · Click to change"
        editor.workspace.settingsButton.needsDisplay = true
        shortcutRecorder?.title = shortcuts.shortcut.display + "  ·  Click to change"
    }

    @objc func newCapture(_ sender: Any?) { editor.capture() }
    @objc func showEditor(_ sender: Any?) { editor.show() }
    @objc func openImage(_ sender: Any?) { editor.show(); editor.openImage() }
    @objc func showSample(_ sender: Any?) { editor.showSample() }
    @objc func exportImage(_ sender: Any?) { editor.exportImage() }
    @objc func copyImage(_ sender: Any?) { editor.copyImage() }
    @objc func copy(_ sender: Any?) { editor.copyImage() }
    @objc func paste(_ sender: Any?) { editor.pasteImage() }
    @objc func undo(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.undo() }
        else { editor.undoEdit() }
    }
    @objc func redo(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.redo() }
        else { editor.redoEdit() }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undo(_:)) {
            if let text = NSApp.keyWindow?.firstResponder as? NSTextView { return text.undoManager?.canUndo == true }
            return editor?.currentDocument?.canUndo == true
        }
        if menuItem.action == #selector(redo(_:)) {
            if let text = NSApp.keyWindow?.firstResponder as? NSTextView { return text.undoManager?.canRedo == true }
            return editor?.currentDocument?.canRedo == true
        }
        if menuItem.action == #selector(deleteCapture(_:)) { return editor?.currentDocument?.isSample == false }
        return true
    }
    @objc func deleteCapture(_ sender: Any?) { editor.deleteCapture() }
    @objc func quit(_ sender: Any?) { NSApp.terminate(nil) }
    @objc func about(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Minato", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0", .credits: NSAttributedString(string: "Capture. Clarify. Share.\nA little more context, right where it matters.")])
    }

    @objc func openSettings(_ sender: Any?) {
        if settings == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 365), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Minato Settings"
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            let view = Surface(Theme.background)
            let heading = Theme.text("Ready when inspiration strikes.", size: 20, weight: .semibold)
            heading.frame = CGRect(x: 28, y: 28, width: 430, height: 30)
            view.addSubview(heading)
            let description = Theme.text("Use your capture shortcut from any app.\nMinato stays in the menu bar when its window is closed.", size: 12, color: Theme.secondary)
            description.maximumNumberOfLines = 2
            description.frame = CGRect(x: 28, y: 72, width: 425, height: 42)
            view.addSubview(description)
            let label = Theme.text("GLOBAL CAPTURE SHORTCUT", size: 10, weight: .semibold, color: Theme.secondary)
            label.frame = CGRect(x: 28, y: 139, width: 410, height: 20)
            view.addSubview(label)
            let recorder = ShortcutRecorder(frame: CGRect(x: 28, y: 170, width: 424, height: 40))
            recorder.bezelStyle = .rounded
            recorder.font = .systemFont(ofSize: 14, weight: .medium)
            recorder.setAccessibilityLabel("Record global capture shortcut")
            recorder.onRecord = { [weak self] value in
                guard let self else { return }
                do { try self.shortcuts.register(value); self.updateShortcutLabel() }
                catch { self.updateShortcutLabel(); let alert = NSAlert(error: error); alert.beginSheetModal(for: window) }
            }
            view.addSubview(recorder)
            shortcutRecorder = recorder
            let reset = ActionButton("Reset to ⇧⌘2") { [weak self] in
                guard let self else { return }
                do { try self.shortcuts.register(.standard); self.updateShortcutLabel() }
                catch { let alert = NSAlert(error: error); alert.beginSheetModal(for: window) }
            }
            reset.frame = CGRect(x: 28, y: 218, width: 424, height: 32)
            view.addSubview(reset)
            let permissions = ActionButton("Screen recording permissions", symbol: "lock.shield") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
            permissions.frame = CGRect(x: 28, y: 290, width: 424, height: 35)
            view.addSubview(permissions)
            window.contentView = view
            window.center()
            settings = NSWindowController(window: window)
        }
        updateShortcutLabel()
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
