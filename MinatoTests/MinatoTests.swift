import XCTest
import AppKit
@testable import Minato

final class MinatoTests: XCTestCase {
    private func image(width: Int = 120, height: Int = 80) -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<height {
            for x in 0..<width {
                let value: CGFloat = y < height / 2 ? 1 : 0
                bitmap.setColor(NSColor(deviceRed: value, green: value, blue: value, alpha: 1), atX: x, y: y)
            }
        }
        let image = NSImage(size: CGSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }

    func testUndoRedoAndNewEditDiscardsRedo() {
        let document = CaptureDocument(image: image(), title: "Test")
        let arrow = Annotation(kind: .arrow, points: [.zero, CGPoint(x: 30, y: 20)], color: .coral)
        document.replaceAnnotations([arrow])
        document.replaceAnnotations([])
        document.undo()
        XCTAssertEqual(document.annotations, [arrow])
        document.undo()
        XCTAssertTrue(document.annotations.isEmpty)
        document.redo()
        XCTAssertEqual(document.annotations, [arrow])
        document.replaceAnnotations([arrow, arrow])
        XCTAssertFalse(document.canRedo)
    }

    func testStoreRoundTripKeepsOriginalAndEditableAnnotations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(directory: directory)
        let document = CaptureDocument(image: image(), title: "A capture")
        document.replaceAnnotations([Annotation(kind: .note, points: [CGPoint(x: 40, y: 50), CGPoint(x: 20, y: 10)], color: .violet, text: "Keep this editable")])
        try store.save(document)
        let loaded = try XCTUnwrap(store.load().first)
        XCTAssertEqual(loaded.metadata.id, document.metadata.id)
        XCTAssertEqual(loaded.annotations, document.annotations)
        XCTAssertEqual(loaded.pixelSize, CGSize(width: 120, height: 80))
        document.replaceAnnotations([])
        try store.save(document)
        XCTAssertEqual(try store.load().first?.annotations, [])
        try store.delete(document)
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testExportPreservesResolutionOrientationAndPaintsAnnotation() throws {
        let document = CaptureDocument(image: image(), title: "Render")
        document.replaceAnnotations([Annotation(kind: .pen, points: [CGPoint(x: 10, y: 15), CGPoint(x: 95, y: 15)], color: .coral, lineWidth: 6)])
        let rendered = try AnnotationRenderer.render(document)
        XCTAssertEqual(rendered.pixelsWide, 120)
        XCTAssertEqual(rendered.pixelsHigh, 80)
        let top = try XCTUnwrap(rendered.colorAt(x: 5, y: 5)?.usingColorSpace(.sRGB))
        let bottom = try XCTUnwrap(rendered.colorAt(x: 5, y: 75)?.usingColorSpace(.sRGB))
        let stroke = try XCTUnwrap(rendered.colorAt(x: 50, y: 15)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(top.redComponent, 0.95)
        XCTAssertLessThan(bottom.redComponent, 0.05)
        XCTAssertGreaterThan(stroke.redComponent, 0.8)
        XCTAssertLessThan(stroke.greenComponent, 0.5)
    }

    @MainActor
    func testRetinaCropUsesTopLeftCoordinatesAndClampsToDisplay() {
        let crop = ScreenCaptureCoordinator.pixelRect(selection: CGRect(x: 10.2, y: 25, width: 100, height: 60), screenSize: CGSize(width: 1440, height: 900), pixelSize: CGSize(width: 2880, height: 1800))
        XCTAssertEqual(crop, CGRect(x: 20, y: 50, width: 201, height: 120))
        let clipped = ScreenCaptureCoordinator.pixelRect(selection: CGRect(x: 1400, y: 870, width: 100, height: 100), screenSize: CGSize(width: 1440, height: 900), pixelSize: CGSize(width: 2880, height: 1800))
        XCTAssertEqual(clipped, CGRect(x: 2800, y: 1740, width: 80, height: 60))
    }

    func testHitTestingSelectsStrokeInsteadOfItsEmptyBoundingBox() {
        let arrow = Annotation(kind: .arrow, points: [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 100)], color: .coral)
        XCTAssertTrue(AnnotationRenderer.hitTest(CGPoint(x: 50, y: 52), annotation: arrow, imageSize: CGSize(width: 200, height: 200), tolerance: 6))
        XCTAssertFalse(AnnotationRenderer.hitTest(CGPoint(x: 15, y: 90), annotation: arrow, imageSize: CGSize(width: 200, height: 200), tolerance: 6))
    }

    func testCalloutNearEdgeFitsInImage() {
        let annotation = Annotation(kind: .note, points: [CGPoint(x: 1090, y: 20)], color: .violet, text: "A note near the edge")
        let rect = AnnotationRenderer.noteRect(annotation, imageSize: CGSize(width: 1120, height: 730))
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, 1120)
        XCTAssertLessThanOrEqual(rect.maxY, 730)
    }

    @MainActor
    func testNewArrowsCycleAndUndoRedoKeepTheirColors() {
        let canvas = CanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let document = CaptureDocument(image: image(), title: "Arrow colors")
        canvas.document = document
        canvas.tool = .arrow
        for _ in 0...InkColor.palette.count { drawStroke(on: canvas) }
        let colors = document.annotations.map(\.color)
        XCTAssertEqual(Array(colors.prefix(InkColor.palette.count)), InkColor.palette)
        XCTAssertEqual(colors.last, .coral)
        document.undo()
        XCTAssertEqual(canvas.activeInk, .coral)
        document.redo()
        XCTAssertEqual(document.annotations.map(\.color), colors)
        XCTAssertEqual(canvas.activeInk, .violet)

        canvas.tool = .select
        mouse(.leftMouseDown, on: canvas, at: CGPoint(x: 30, y: 30))
        mouse(.leftMouseDragged, on: canvas, at: CGPoint(x: 40, y: 35))
        mouse(.leftMouseUp, on: canvas, at: CGPoint(x: 40, y: 35))
        XCTAssertEqual(document.annotations.map(\.color), colors)
        XCTAssertNotEqual(document.annotations.last?.points.first, CGPoint(x: 10, y: 20))
    }

    @MainActor
    func testManualArrowColorSurvivesCancellationAndDoesNotCyclePenInk() {
        let canvas = CanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let document = CaptureDocument(image: image(), title: "Manual colors")
        canvas.document = document
        canvas.tool = .arrow
        drawStroke(on: canvas)
        canvas.chooseInk(.coral)
        // A click without a drag must not consume the manually chosen next color.
        mouse(.leftMouseDown, on: canvas, at: CGPoint(x: 10, y: 20))
        mouse(.leftMouseUp, on: canvas, at: CGPoint(x: 10, y: 20))
        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertEqual(canvas.activeInk, .coral)
        drawStroke(on: canvas)
        XCTAssertEqual(document.annotations.map(\.color), [.coral, .coral])
        XCTAssertEqual(canvas.activeInk, .violet)

        mouse(.leftMouseDown, on: canvas, at: CGPoint(x: 10, y: 20))
        mouse(.leftMouseDragged, on: canvas, at: CGPoint(x: 50, y: 40))
        canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
        mouse(.leftMouseUp, on: canvas, at: CGPoint(x: 50, y: 40))
        XCTAssertEqual(document.annotations.count, 2)
        XCTAssertEqual(canvas.activeInk, .violet)

        canvas.tool = .pen
        canvas.chooseInk(.green)
        drawStroke(on: canvas)
        drawStroke(on: canvas)
        XCTAssertEqual(document.annotations.suffix(2).map(\.color), [.green, .green])
        canvas.tool = .arrow
        drawStroke(on: canvas)
        XCTAssertEqual(document.annotations.last?.color, .violet)
    }

    @MainActor
    func testKeyboardMovementClampsToImageAndCanBeUndone() {
        let canvas = CanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let document = CaptureDocument(image: image(), title: "Keyboard movement")
        let arrow = Annotation(kind: .arrow, points: [CGPoint(x: 10, y: 20), CGPoint(x: 50, y: 40)], color: .blue)
        document.replaceAnnotations([arrow])
        canvas.document = document
        canvas.selectedID = arrow.id
        canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124)!)
        XCTAssertEqual(document.annotations[0].points[0], CGPoint(x: 20, y: 20))
        XCTAssertEqual(document.annotations[0].color, .blue)
        document.undo()
        XCTAssertEqual(document.annotations, [arrow])
        canvas.moveSelection(by: CGPoint(x: -200, y: 200))
        XCTAssertEqual(document.annotations[0].points, [CGPoint(x: 0, y: 60), CGPoint(x: 40, y: 80)])
        document.undo()
        XCTAssertEqual(document.annotations, [arrow])
    }

    @MainActor
    func testExportAndSampleAreIndependentOfInterfaceAppearance() throws {
        let document = CaptureDocument(image: image(width: 400, height: 300), title: "Appearance")
        document.replaceAnnotations([
            Annotation(kind: .note, points: [CGPoint(x: 30, y: 120), CGPoint(x: 70, y: 30)], color: .violet, text: "Readable in every appearance"),
            Annotation(kind: .arrow, points: [CGPoint(x: 20, y: 220), CGPoint(x: 240, y: 260)], color: .coral)
        ])
        var exports: [Data] = []
        var samples: [Data] = []
        for name in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastDarkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            var result: Result<(Data, Data), Error>!
            appearance.performAsCurrentDrawingAppearance {
                result = Result {
                    let rendered = try AnnotationRenderer.render(document)
                    let sample = try AnnotationRenderer.render(SampleImage.make())
                    return (try XCTUnwrap(rendered.representation(using: .png, properties: [:])), try XCTUnwrap(sample.representation(using: .png, properties: [:])))
                }
            }
            let (export, sample) = try result.get()
            exports.append(export)
            samples.append(sample)
        }
        XCTAssertEqual(exports[0], exports[1], "Dark Mode must not recolor exported notes or arrows")
        XCTAssertEqual(exports[0], exports[2], "Interface contrast preferences must not recolor exported content")
        XCTAssertEqual(samples[0], samples[1], "The sample screenshot must retain its original colors")
        XCTAssertEqual(samples[0], samples[2])
    }

    @MainActor
    func testActualPixelSizeSurvivesCanvasResize() {
        let canvas = CanvasView(frame: CGRect(x: 0, y: 0, width: 300, height: 240))
        canvas.document = CaptureDocument(image: image(width: 800, height: 600), title: "Zoom")
        canvas.usesActualSize = true
        let originalScale = canvas.imageScale
        canvas.setFrameSize(CGSize(width: 700, height: 500))
        XCTAssertEqual(canvas.imageScale, originalScale)
        XCTAssertEqual(canvas.imageScale, 1)
        canvas.usesActualSize = false
        XCTAssertLessThan(canvas.imageScale, 1)
        XCTAssertTrue(canvas.bounds.contains(canvas.imageRect))
    }

    @MainActor
    func testWorkspaceReflowsWithHiddenPanes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let editor = EditorController(captureStore: try CaptureStore(directory: directory), restoresWindow: false)
        let window = try XCTUnwrap(editor.window)
        let workspace = try XCTUnwrap(editor.workspace)
        workspace.splitView.autosaveName = nil
        defer { window.close() }
        window.setContentSize(CGSize(width: 1200, height: 720))
        workspace.view.layoutSubtreeIfNeeded()
        let sidebar = workspace.sidebarItem.viewController.view
        let originalSidebarWidth = sidebar.frame.width
        workspace.splitView.setPosition(originalSidebarWidth + 30, ofDividerAt: 0)
        workspace.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(sidebar.frame.width, originalSidebarWidth + 20, "The sidebar divider must respond to resizing")
        let inspector = workspace.inspectorItem.viewController.view
        let originalInspectorWidth = inspector.frame.width
        let targetInspectorWidth = originalInspectorWidth + (originalInspectorWidth > 270 ? -30 : 30)
        workspace.splitView.setPosition(workspace.splitView.bounds.width - targetInspectorWidth - workspace.splitView.dividerThickness, ofDividerAt: 1)
        workspace.view.layoutSubtreeIfNeeded()
        if targetInspectorWidth > originalInspectorWidth {
            XCTAssertGreaterThan(inspector.frame.width, originalInspectorWidth + 20)
        } else {
            XCTAssertLessThan(inspector.frame.width, originalInspectorWidth - 20)
        }
        let fullWidth = workspace.canvas.bounds.width
        XCTAssertGreaterThan(fullWidth, 400)
        workspace.sidebarItem.isCollapsed = true
        workspace.inspectorItem.isCollapsed = true
        workspace.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(workspace.canvas.bounds.width, fullWidth + 300)
        workspace.sidebarItem.isCollapsed = false
        workspace.inspectorItem.isCollapsed = false
        window.setContentSize(CGSize(width: 820, height: 510))
        workspace.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(workspace.canvas.bounds.width, 360)
        XCTAssertGreaterThan(workspace.canvas.bounds.height, 300)
        XCTAssertFalse(workspace.canvas.mouseDownCanMoveWindow)
        XCTAssertFalse(window.isMovableByWindowBackground)
    }

    @MainActor
    private func drawStroke(on canvas: CanvasView) {
        mouse(.leftMouseDown, on: canvas, at: CGPoint(x: 10, y: 20))
        mouse(.leftMouseDragged, on: canvas, at: CGPoint(x: 50, y: 40))
        mouse(.leftMouseUp, on: canvas, at: CGPoint(x: 50, y: 40))
    }

    @MainActor
    private func mouse(_ type: NSEvent.EventType, on canvas: CanvasView, at point: CGPoint) {
        let local = CGPoint(x: canvas.imageRect.minX + point.x * canvas.imageScale, y: canvas.imageRect.minY + point.y * canvas.imageScale)
        let event = NSEvent.mouseEvent(with: type, location: canvas.convert(local, to: nil), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        switch type {
        case .leftMouseDown: canvas.mouseDown(with: event)
        case .leftMouseDragged: canvas.mouseDragged(with: event)
        case .leftMouseUp: canvas.mouseUp(with: event)
        default: XCTFail("Unexpected test event")
        }
    }
}
