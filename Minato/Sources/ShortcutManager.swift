import AppKit
import Carbon

struct CaptureShortcut: Codable {
    var keyCode: UInt32
    var modifiers: UInt32
    var character: String
    static let standard = CaptureShortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey), character: "2")
    var display: String {
        (modifiers & UInt32(controlKey) != 0 ? "⌃" : "") + (modifiers & UInt32(optionKey) != 0 ? "⌥" : "") + (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "") + (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "") + character.uppercased()
    }
}

final class ShortcutManager {
    var onCapture: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var localMonitor: Any?
    private(set) var shortcut: CaptureShortcut = .standard

    init() {
        if let data = UserDefaults.standard.data(forKey: "captureShortcut"), let saved = try? JSONDecoder().decode(CaptureShortcut.self, from: data) { shortcut = saved }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x4D4E544F else { return OSStatus(eventNotHandledErr) }
            Unmanaged<ShortcutManager>.fromOpaque(context).takeUnretainedValue().onCapture?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        // Also handle key equivalents delivered directly to an active app window.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !(NSApp.keyWindow?.firstResponder is ShortcutRecorder),
                  UInt32(event.keyCode) == self.shortcut.keyCode else { return event }
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
            if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
            guard modifiers == self.shortcut.modifiers else { return event }
            if !event.isARepeat { self.onCapture?() }
            return nil
        }
    }

    func register(_ newShortcut: CaptureShortcut? = nil) throws {
        let value = newShortcut ?? shortcut
        var newReference: EventHotKeyRef?
        if hotKey != nil, value.keyCode == shortcut.keyCode, value.modifiers == shortcut.modifiers { return }
        let status = RegisterEventHotKey(value.keyCode, value.modifiers, EventHotKeyID(signature: 0x4D4E544F, id: 1), GetApplicationEventTarget(), 0, &newReference)
        guard status == noErr else { throw MinatoError.message("The shortcut \(value.display) is already in use. Choose another shortcut in Minato Settings.") }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = newReference
        shortcut = value
        UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: "captureShortcut")
    }

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

final class ShortcutRecorder: NSButton {
    var onRecord: ((CaptureShortcut) -> Void)?
    var recording = false
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        recording = true
        title = "Type a shortcut… (Esc to cancel)"
        window?.makeFirstResponder(self)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; title = "Click to record shortcut"; return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty,
              let characters = event.characters(byApplyingModifiers: []), characters.count == 1,
              characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            title = "Use ⌘, ⌃, or ⌥ with a letter or number"
            return
        }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        recording = false
        onRecord?(CaptureShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, character: characters))
    }
}
