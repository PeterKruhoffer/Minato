import AppKit

struct InkColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    static let coral = InkColor(red: 0.94, green: 0.34, blue: 0.29)
    static let violet = InkColor(red: 0.43, green: 0.36, blue: 0.86)
    static let blue = InkColor(red: 0.20, green: 0.49, blue: 0.94)
    static let green = InkColor(red: 0.15, green: 0.62, blue: 0.48)
    static let yellow = InkColor(red: 0.94, green: 0.66, blue: 0.16)
    static let dark = InkColor(red: 0.15, green: 0.17, blue: 0.22)
    static let palette = [coral, violet, blue, green, yellow, dark]
}

enum AnnotationKind: String, Codable, CaseIterable {
    case pen, arrow, note
    var title: String {
        switch self { case .pen: return "Drawing"; case .arrow: return "Arrow"; case .note: return "Note" }
    }
    var symbol: String {
        switch self { case .pen: return "pencil.tip"; case .arrow: return "arrow.up.right"; case .note: return "text.bubble" }
    }
}

struct Annotation: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: AnnotationKind
    var points: [CGPoint]
    var color: InkColor
    var lineWidth: CGFloat = 4
    var text = ""
}

struct CaptureMetadata: Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var annotations: [Annotation]
}

final class CaptureDocument {
    var metadata: CaptureMetadata
    let image: NSImage
    let pixelSize: CGSize
    let isSample: Bool
    private var past: [[Annotation]] = []
    private var future: [[Annotation]] = []
    var annotations: [Annotation] { metadata.annotations }
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    init(image: NSImage, title: String, isSample: Bool = false, metadata: CaptureMetadata? = nil) {
        self.image = image
        self.isSample = isSample
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        pixelSize = CGSize(width: cgImage?.width ?? Int(image.size.width), height: cgImage?.height ?? Int(image.size.height))
        self.metadata = metadata ?? CaptureMetadata(id: UUID(), title: title, createdAt: Date(), annotations: [])
    }

    func replaceAnnotations(_ next: [Annotation]) {
        guard next != annotations else { return }
        past.append(annotations)
        if past.count > 100 { past.removeFirst() }
        future.removeAll()
        metadata.annotations = next
    }

    func undo() {
        guard let previous = past.popLast() else { return }
        future.append(annotations)
        metadata.annotations = previous
    }

    func redo() {
        guard let next = future.popLast() else { return }
        past.append(annotations)
        metadata.annotations = next
    }
}

final class CaptureStore {
    let directory: URL
    init(directory: URL? = nil) throws {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Minato/Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func load() throws -> [CaptureDocument] {
        let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("capture.json")),
                  let metadata = try? JSONDecoder().decode(CaptureMetadata.self, from: data),
                  let image = NSImage(contentsOf: folder.appendingPathComponent("original.png")) else { return nil }
            return CaptureDocument(image: image, title: metadata.title, metadata: metadata)
        }.sorted { $0.metadata.createdAt > $1.metadata.createdAt }
    }

    func save(_ document: CaptureDocument) throws {
        guard !document.isSample else { return }
        let folder = directory.appendingPathComponent(document.metadata.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let originalURL = folder.appendingPathComponent("original.png")
        if !FileManager.default.fileExists(atPath: originalURL.path) {
            guard let cg = document.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                throw MinatoError.message("The original image could not be saved.")
            }
            try data.write(to: originalURL, options: .atomic)
        }
        try JSONEncoder().encode(document.metadata).write(to: folder.appendingPathComponent("capture.json"), options: .atomic)
    }

    func delete(_ document: CaptureDocument) throws {
        guard !document.isSample else { return }
        try FileManager.default.removeItem(at: directory.appendingPathComponent(document.metadata.id.uuidString))
    }
}

enum MinatoError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}
