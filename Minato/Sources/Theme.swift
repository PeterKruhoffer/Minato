import AppKit

enum Theme {
    // Interface colors follow appearance, accent, and accessibility preferences.
    static let ink = NSColor.labelColor
    static let secondary = NSColor.secondaryLabelColor
    static let accent = NSColor.controlAccentColor
    static let background = NSColor.windowBackgroundColor
    static let line = NSColor.separatorColor
    static let canvas = NSColor.underPageBackgroundColor

    // Image content has its own fixed palette; changing appearance must not change an export.
    static let imageInk = NSColor(hex: 0x252735)
    static let imageSecondary = NSColor(hex: 0x828491)
    static let imageAccent = NSColor(hex: 0x7360D9)
    static let imageLine = NSColor(hex: 0xE6E6E4)

    static func text(_ string: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = ink) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        return label
    }
    static func drawText(_ text: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = imageInk, alignment: NSTextAlignment = .left) {
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
    var fill: NSColor { didSet { needsDisplay = true } }
    init(_ color: NSColor) { fill = color; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { fill.setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

// Keep AppKit responsible for focus, pressed, disabled, and default-button rendering.
final class ActionButton: NSButton {
    var actionHandler: (() -> Void)?
    init(_ title: String, symbol: String? = nil, primary: Bool = false, action: @escaping () -> Void) {
        actionHandler = action
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: NSFont.systemFontSize)
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            imagePosition = .imageLeading
        }
        if primary { bezelColor = .controlAccentColor }
        setAccessibilityLabel(title)
        target = self
        self.action = #selector(performAction)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func performAction() { actionHandler?() }
}

final class ColorButton: NSButton {
    let ink: InkColor
    var selected = false {
        didSet {
            state = selected ? .on : .off
            updateSwatch()
            setAccessibilityValue(selected ? 1 : 0)
        }
    }
    var onChoose: ((InkColor) -> Void)?
    init(_ ink: InkColor) {
        self.ink = ink
        super.init(frame: .zero)
        title = ink.name
        bezelStyle = .regularSquare
        setButtonType(.pushOnPushOff)
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        toolTip = ink.name
        setAccessibilityLabel(ink.name)
        target = self
        action = #selector(choose)
        updateSwatch()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func choose() { onChoose?(ink) }
    private func updateSwatch() {
        let color = ink.nsColor
        let checked = selected
        let checkColor: NSColor = ink == .yellow ? .black : .white
        image = NSImage(size: CGSize(width: 18, height: 18), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            if checked {
                checkColor.setStroke()
                let check = NSBezierPath()
                check.move(to: CGPoint(x: 5, y: 9))
                check.line(to: CGPoint(x: 8, y: 6))
                check.line(to: CGPoint(x: 13, y: 12))
                check.lineWidth = 1.7
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.stroke()
            }
            return true
        }
    }
}

extension InkColor {
    var name: String {
        switch self {
        case .coral: return "Coral"
        case .violet: return "Violet"
        case .blue: return "Blue"
        case .green: return "Green"
        case .yellow: return "Amber"
        case .dark: return "Charcoal"
        default: return "Custom Color"
        }
    }
}
