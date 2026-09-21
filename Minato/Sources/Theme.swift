import AppKit

enum Theme {
    static let ink = NSColor(hex: 0x252735)
    static let secondary = NSColor(hex: 0x828491)
    static let accent = NSColor(hex: 0x7360D9)
    static let accentLight = NSColor(hex: 0xEEEAFB)
    static let background = NSColor(hex: 0xFAFAF8)
    static let sidebar = NSColor(hex: 0xF2F2EF)
    static let line = NSColor(hex: 0xE6E6E4)
    static let canvas = NSColor(hex: 0xECEDEB)
    static func text(_ string: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = ink) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        return label
    }
    static func drawText(_ text: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = ink, alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

class FlippedView: NSView { override var isFlipped: Bool { true } }

final class Surface: FlippedView {
    var fill: NSColor
    init(_ color: NSColor, radius: CGFloat = 0) {
        fill = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = radius
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class ActionButton: NSButton {
    var actionHandler: (() -> Void)?
    var active = false { didSet { needsDisplay = true } }
    var primary = false { didSet { needsDisplay = true } }
    var compact = false
    var symbol: String?
    var tint: NSColor?

    init(_ title: String, symbol: String? = nil, primary: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.primary = primary
        actionHandler = action
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        target = self
        self.action = #selector(performAction)
        setAccessibilityLabel(title)
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func performAction() { actionHandler?() }
    override func draw(_ dirtyRect: NSRect) {
        let background: NSColor = primary ? Theme.accent : (active ? Theme.accentLight : .clear)
        (isHighlighted ? background.blended(withFraction: 0.1, of: .black)! : background).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
        let color = !isEnabled ? Theme.secondary.withAlphaComponent(0.4) : primary ? NSColor.white : (tint ?? (active ? Theme.accent : Theme.ink))
        let font = NSFont.systemFont(ofSize: 12, weight: primary || active ? .semibold : .medium)
        let textWidth = compact ? 0 : (title as NSString).size(withAttributes: [.font: font]).width
        let symbolWidth: CGFloat = symbol == nil ? 0 : 17
        let gap: CGFloat = symbol == nil || compact ? 0 : 7
        let startX = (bounds.width - textWidth - symbolWidth - gap) / 2
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium).applying(.init(paletteColors: [color]))
            let configured = image.withSymbolConfiguration(configuration) ?? image
            let rect = NSRect(x: startX, y: (bounds.height - 17) / 2, width: 17, height: 17)
            configured.draw(in: rect, from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.35, respectFlipped: true, hints: nil)
        }
        if !compact {
            (title as NSString).draw(at: CGPoint(x: startX + symbolWidth + gap, y: (bounds.height - font.boundingRectForFont.height) / 2 + 1), withAttributes: [.font: font, .foregroundColor: color])
        }
    }
}

final class ColorButton: NSButton {
    let ink: InkColor
    var selected = false { didSet { needsDisplay = true } }
    var onChoose: ((InkColor) -> Void)?
    init(_ ink: InkColor, name: String) {
        self.ink = ink
        super.init(frame: .zero)
        isBordered = false
        target = self
        action = #selector(choose)
        toolTip = name
        setAccessibilityLabel(name)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func choose() { onChoose?(ink) }
    override func draw(_ dirtyRect: NSRect) {
        ink.nsColor.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 5, dy: 5)).fill()
        if selected {
            ink.nsColor.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
            ring.lineWidth = 1.5
            ring.stroke()
            NSColor.white.setStroke()
            let check = NSBezierPath()
            check.move(to: CGPoint(x: 10, y: 14))
            check.line(to: CGPoint(x: 13, y: 17))
            check.line(to: CGPoint(x: 19, y: 11))
            check.lineWidth = 1.7
            check.stroke()
        }
    }
}
