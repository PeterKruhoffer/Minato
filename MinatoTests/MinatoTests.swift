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
