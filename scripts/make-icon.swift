import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
var entries: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 35
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.shadowOffset = CGSize(width: 0, height: -12)
        shadow.set()
        let card = NSBezierPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), xRadius: 180, yRadius: 180)
        NSColor(srgbRed: 0.45, green: 0.37, blue: 0.86, alpha: 1).setFill()
        card.fill()
        NSShadow().set()
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.56, green: 0.47, blue: 0.96, alpha: 1), ending: NSColor(srgbRed: 0.38, green: 0.31, blue: 0.77, alpha: 1))!
        gradient.draw(in: card, angle: -90)
        NSColor.white.setStroke()
        let mark = NSBezierPath()
        mark.lineWidth = 70
        mark.lineCapStyle = .round
        mark.lineJoinStyle = .round
        mark.move(to: CGPoint(x: 290, y: 340))
        mark.line(to: CGPoint(x: 290, y: 650))
        mark.line(to: CGPoint(x: 512, y: 441))
        mark.line(to: CGPoint(x: 734, y: 650))
        mark.line(to: CGPoint(x: 734, y: 340))
        mark.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(points)x\(points)@\(scale)x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(filename))
        entries.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename])
    }
}
let data = try JSONSerialization.data(withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys])
try data.write(to: destination.appendingPathComponent("Contents.json"))
