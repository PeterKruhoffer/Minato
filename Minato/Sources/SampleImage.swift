import AppKit

enum SampleImage {
    static func make() -> CaptureDocument {
        let size = CGSize(width: 1120, height: 730)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor(hex: 0xFCFCFC).setFill(); rect.fill()
            NSColor(hex: 0xF4F5F7).setFill(); CGRect(x: 0, y: 0, width: 1120, height: 48).fill()
            for (i, color) in [0xF2A49C, 0xF2D192, 0xA8CBB0].enumerated() {
                NSColor(hex: UInt32(color)).setFill()
                NSBezierPath(ovalIn: CGRect(x: 20 + i * 21, y: 18, width: 11, height: 11)).fill()
            }
            Theme.drawText("studio / website-refresh", in: CGRect(x: 370, y: 15, width: 380, height: 24), size: 14, color: Theme.imageSecondary, alignment: .center)
            Theme.drawText("S", in: CGRect(x: 42, y: 83, width: 40, height: 40), size: 28, weight: .bold, color: Theme.imageAccent)
            Theme.drawText("studio", in: CGRect(x: 78, y: 90, width: 120, height: 30), size: 23, weight: .semibold)
            Theme.drawText("Overview     Projects     Team", in: CGRect(x: 320, y: 94, width: 420, height: 28), size: 16, color: Theme.imageSecondary)
            NSColor(hex: 0xEEEAFB).setFill()
            NSBezierPath(roundedRect: CGRect(x: 930, y: 83, width: 145, height: 40), xRadius: 8, yRadius: 8).fill()
            Theme.drawText("+ New project", in: CGRect(x: 940, y: 93, width: 125, height: 22), size: 14, weight: .semibold, color: Theme.imageAccent, alignment: .center)
            Theme.imageLine.setFill(); CGRect(x: 40, y: 148, width: 1035, height: 1).fill()
            Theme.drawText("PROJECT OVERVIEW", in: CGRect(x: 48, y: 186, width: 500, height: 24), size: 12, weight: .semibold, color: Theme.imageSecondary)
            Theme.drawText("Website refresh", in: CGRect(x: 46, y: 220, width: 670, height: 56), size: 38, weight: .semibold)
            Theme.drawText("A fresh start for everything we’re building.", in: CGRect(x: 48, y: 280, width: 700, height: 30), size: 18, color: Theme.imageSecondary)
            let labels = ["In progress", "Tasks completed", "Next milestone"]
            let values = ["Design system", "24 of 32", "Launch day"]
            let subtitles = ["Everything, coming together", "8 little things left to do", "Friday, October 16"]
            for i in 0..<3 {
                let x = CGFloat(48 + i * 347)
                NSColor.white.setFill()
                let card = NSBezierPath(roundedRect: CGRect(x: x, y: 351, width: 326, height: 166), xRadius: 12, yRadius: 12)
                card.fill(); Theme.imageLine.setStroke(); card.lineWidth = 1; card.stroke()
                Theme.drawText(labels[i], in: CGRect(x: x + 22, y: 374, width: 280, height: 24), size: 14, color: Theme.imageSecondary)
                Theme.drawText(values[i], in: CGRect(x: x + 22, y: 411, width: 280, height: 40), size: 25, weight: .semibold)
                Theme.drawText(subtitles[i], in: CGRect(x: x + 22, y: 467, width: 280, height: 28), size: 14, color: Theme.imageSecondary)
            }
            Theme.drawText("THE NEXT CHAPTER", in: CGRect(x: 48, y: 561, width: 600, height: 24), size: 12, weight: .semibold, color: Theme.imageSecondary)
            Theme.drawText("Good things take a little collaboration.", in: CGRect(x: 48, y: 600, width: 880, height: 40), size: 24, weight: .medium)
            Theme.drawText("Bring your ideas. We’ll make room for them.", in: CGRect(x: 48, y: 646, width: 880, height: 30), size: 16, color: Theme.imageSecondary)
            return true
        }
        // NSImage drawing handlers otherwise resolve at the current display's Retina scale.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let raster = NSImage(cgImage: bitmap.cgImage!, size: size)
        let document = CaptureDocument(image: raster, title: "A little room for feedback", isSample: true)
        document.metadata.annotations = [
            Annotation(kind: .arrow, points: [CGPoint(x: 820, y: 234), CGPoint(x: 966, y: 133)], color: .coral, lineWidth: 5),
            Annotation(kind: .note, points: [CGPoint(x: 696, y: 445), CGPoint(x: 759, y: 543)], color: .violet, text: "Looking good! Let’s ship it.")
        ]
        return document
    }
}
