import AppKit

enum AnnotationRenderer {
    static func noteRect(_ annotation: Annotation, imageSize: CGSize) -> CGRect {
        let font = NSFont.systemFont(ofSize: 18, weight: .medium)
        let maxWidth = min(260, max(80, imageSize.width - 24))
        let measured = (annotation.text as NSString).boundingRect(with: CGSize(width: maxWidth - 28, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        let size = CGSize(width: min(maxWidth, max(100, ceil(measured.width) + 28)), height: ceil(measured.height) + 24)
        let anchor = annotation.points.first ?? .zero
        let proposed = annotation.points.count > 1 ? annotation.points[1] : CGPoint(x: anchor.x + 35, y: anchor.y - size.height - 25)
        return CGRect(x: max(4, min(proposed.x, imageSize.width - size.width - 4)), y: max(4, min(proposed.y, imageSize.height - size.height - 4)), width: size.width, height: size.height)
    }

    static func draw(_ annotation: Annotation, imageSize: CGSize, selected: Bool = false) {
        guard let first = annotation.points.first else { return }
        NSGraphicsContext.saveGraphicsState()
        annotation.color.nsColor.setStroke()
        annotation.color.nsColor.setFill()
        let path = NSBezierPath()
        path.lineWidth = annotation.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch annotation.kind {
        case .pen:
            if annotation.points.count == 1 {
                NSBezierPath(ovalIn: CGRect(x: first.x - annotation.lineWidth / 2, y: first.y - annotation.lineWidth / 2, width: annotation.lineWidth, height: annotation.lineWidth)).fill()
            } else {
                path.move(to: first)
                for point in annotation.points.dropFirst() { path.line(to: point) }
                path.stroke()
            }
        case .arrow:
            guard let end = annotation.points.last else { break }
            let angle = atan2(end.y - first.y, end.x - first.x)
            let length = min(max(16, annotation.lineWidth * 4.5), hypot(end.x - first.x, end.y - first.y) * 0.6)
            path.move(to: first)
            path.line(to: end)
            path.move(to: CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)))
            path.line(to: end)
            path.line(to: CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6)))
            path.stroke()
        case .note:
            let rect = noteRect(annotation, imageSize: imageSize)
            let nearest = CGPoint(x: min(max(first.x, rect.minX + 10), rect.maxX - 10), y: min(max(first.y, rect.minY + 10), rect.maxY - 10))
            path.lineWidth = 2
            path.move(to: first)
            path.line(to: nearest)
            path.stroke()
            NSBezierPath(ovalIn: CGRect(x: first.x - 5, y: first.y - 5, width: 10, height: 10)).fill()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
            shadow.shadowBlurRadius = 10
            shadow.shadowOffset = CGSize(width: 0, height: -3)
            shadow.set()
            NSColor.white.setFill()
            let card = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            card.fill()
            NSShadow().set()
            annotation.color.nsColor.withAlphaComponent(0.7).setStroke()
            card.lineWidth = 1.5
            card.stroke()
            Theme.drawText(annotation.text, in: rect.insetBy(dx: 14, dy: 12), size: 18, weight: .medium, color: Theme.imageInk)
        }
        if selected {
            let rect = boundingRect(annotation, imageSize: imageSize).insetBy(dx: -6, dy: -6)
            Theme.accent.withAlphaComponent(0.8).setStroke()
            let outline = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            outline.lineWidth = 1.5
            outline.setLineDash([5, 4], count: 2, phase: 0)
            outline.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    static func boundingRect(_ annotation: Annotation, imageSize: CGSize) -> CGRect {
        guard let first = annotation.points.first else { return .zero }
        let xs = annotation.points.map(\.x), ys = annotation.points.map(\.y)
        var rect = CGRect(x: xs.min() ?? first.x, y: ys.min() ?? first.y, width: max(1, (xs.max() ?? first.x) - (xs.min() ?? first.x)), height: max(1, (ys.max() ?? first.y) - (ys.min() ?? first.y)))
        if annotation.kind == .note { rect = rect.union(noteRect(annotation, imageSize: imageSize)) }
        return rect
    }

    static func hitTest(_ point: CGPoint, annotation: Annotation, imageSize: CGSize, tolerance: CGFloat) -> Bool {
        if annotation.kind == .note {
            return noteRect(annotation, imageSize: imageSize).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
                || annotation.points.first.map { hypot(point.x - $0.x, point.y - $0.y) <= tolerance + 6 } == true
        }
        if annotation.points.count == 1, let first = annotation.points.first {
            return hypot(point.x - first.x, point.y - first.y) <= tolerance
        }
        return zip(annotation.points, annotation.points.dropFirst()).contains { a, b in
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared == 0 ? 0 : max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
            return hypot(point.x - a.x - t * dx, point.y - a.y - t * dy) < tolerance + annotation.lineWidth / 2
        }
    }

    static func render(_ document: CaptureDocument) throws -> NSBitmapImageRep {
        let size = document.pixelSize
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw MinatoError.message("The image could not be rendered.") }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let cg = context.cgContext
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        document.image.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        for annotation in document.annotations { draw(annotation, imageSize: size) }
        return bitmap
    }
}
