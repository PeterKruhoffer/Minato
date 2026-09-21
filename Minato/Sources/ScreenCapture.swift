import AppKit
import ScreenCaptureKit

@MainActor
final class ScreenCaptureCoordinator {
    private var overlays: [NSWindow] = []
    private var eventMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var completion: ((Result<NSImage?, Error>) -> Void)?
    private(set) var isCapturing = false

    func begin(completion: @escaping (Result<NSImage?, Error>) -> Void) {
        guard !isCapturing else { return }
        isCapturing = true
        self.completion = completion
        previousApp = NSWorkspace.shared.frontmostApplication
        Task {
            do {
                // Let ScreenCaptureKit request and evaluate its own authorization. A separate
                // CoreGraphics preflight must not prevent an otherwise authorized capture.
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                var snapshots: [(NSScreen, CGImage)] = []
                for screen in NSScreen.screens {
                    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                          let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
                    let ownWindows = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
                    let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
                    let config = SCStreamConfiguration()
                    config.width = Int(CGFloat(display.width) * screen.backingScaleFactor)
                    config.height = Int(CGFloat(display.height) * screen.backingScaleFactor)
                    config.showsCursor = false
                    config.captureResolution = .best
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    snapshots.append((screen, image))
                }
                guard !snapshots.isEmpty else { throw MinatoError.message("No display is available to capture.") }
                showOverlays(snapshots)
            } catch {
                let failure = error as NSError
                if failure.domain == SCStreamError.errorDomain && failure.code == SCStreamError.Code.userDeclined.rawValue {
                    showPermissionHelp()
                    finish(.success(nil))
                } else {
                    finish(.failure(error))
                }
            }
        }
    }

    private func showPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "Allow screen recording for this copy of Minato"
        alert.informativeText = "macOS denied screen capture. Enable Minato in System Settings → Privacy & Security → Screen & System Audio Recording.\n\nIf it’s already enabled, quit Minato with ⌘Q, turn the permission off and on, then reopen the app. After replacing an older development build, you may need to remove its entry and add this copy again.\n\nApp location: \(Bundle.main.bundleURL.path)"
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    private func showOverlays(_ snapshots: [(NSScreen, CGImage)]) {
        NSApp.activate(ignoringOtherApps: true)
        for (screen, image) in snapshots {
            let overlay = CaptureOverlay(image: image)
            overlay.onFinish = { [weak self] rect in
                guard let self else { return }
                guard let rect else { self.finish(.success(nil)); return }
                let pixelRect = Self.pixelRect(selection: rect, screenSize: screen.frame.size, pixelSize: CGSize(width: image.width, height: image.height))
                guard let crop = image.cropping(to: pixelRect) else {
                    self.finish(.failure(MinatoError.message("The selected region could not be captured."))); return
                }
                self.finish(.success(NSImage(cgImage: crop, size: CGSize(width: crop.width, height: crop.height))))
            }
            let window = CaptureWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.backgroundColor = .clear
            window.contentView = overlay
            window.acceptsMouseMovedEvents = true
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(overlay)
            overlays.append(window)
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.finish(.success(nil)); return nil }
            return event
        }
    }

    static func pixelRect(selection: CGRect, screenSize: CGSize, pixelSize: CGSize) -> CGRect {
        let rect = CGRect(x: selection.minX * pixelSize.width / screenSize.width,
                          y: selection.minY * pixelSize.height / screenSize.height,
                          width: selection.width * pixelSize.width / screenSize.width,
                          height: selection.height * pixelSize.height / screenSize.height)
        return rect.integral.intersection(CGRect(origin: .zero, size: pixelSize))
    }

    private func finish(_ result: Result<NSImage?, Error>) {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        overlays.forEach { $0.close() }
        overlays.removeAll()
        isCapturing = false
        if case .success(nil) = result { previousApp?.activate(options: []) }
        let callback = completion
        completion = nil
        callback?(result)
    }
}

private final class CaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class CaptureOverlay: FlippedView {
    let image: CGImage
    private var start: CGPoint?
    private var end: CGPoint?
    var onFinish: ((CGRect?) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    init(image: CGImage) { self.image = image; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    private var selection: CGRect? {
        guard let start, let end else { return nil }
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let veil = NSBezierPath(rect: bounds)
        if let selection { veil.appendRect(selection) }
        veil.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.38).setFill(); veil.fill()
        if let selection {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection); border.lineWidth = 1; border.stroke()
            let factor = CGFloat(image.width) / bounds.width
            let title = "\(Int(selection.width * factor)) × \(Int(selection.height * factor))"
            let label = CGRect(x: max(8, min(selection.midX - 65, bounds.width - 138)), y: min(bounds.height - 40, selection.maxY + 12), width: 130, height: 28)
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: label, xRadius: 7, yRadius: 7).fill()
            Theme.drawText(title, in: label.insetBy(dx: 8, dy: 5), size: 12, weight: .medium, color: .white, alignment: .center)
        } else {
            let label = CGRect(x: (bounds.width - 370) / 2, y: 60, width: 370, height: 48)
            NSColor(hex: 0x252735).withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: label, xRadius: 12, yRadius: 12).fill()
            Theme.drawText("Drag to capture a region  ·  Esc to cancel", in: label.insetBy(dx: 18, dy: 15), size: 14, weight: .medium, color: .white, alignment: .center)
        }
    }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil); end = start; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        end = CGPoint(x: max(0, min(point.x, bounds.width)), y: max(0, min(point.y, bounds.height)))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard let selection, selection.width >= 3, selection.height >= 3 else { start = nil; end = nil; needsDisplay = true; return }
        onFinish?(selection)
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { onFinish?(nil) } }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
}
