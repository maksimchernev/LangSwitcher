import AppKit

enum MenuBarIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 28, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            drawKey("A", at: 1)
            drawKey("Я", at: 15)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawKey(_ label: String, at x: CGFloat) {
        let key = NSRect(x: x, y: 2, width: 11, height: 12)
        let outline = NSBezierPath(roundedRect: key, xRadius: 2.5, yRadius: 2.5)
        outline.lineWidth = 1
        NSColor.black.setStroke()
        outline.stroke()
        let font = NSFont.systemFont(ofSize: 8, weight: .semibold)
        let glyph = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.black])
        glyph.draw(at: NSPoint(
            x: key.midX - glyph.size().width / 2,
            y: key.midY - font.capHeight / 2 + font.descender
        ))
    }
}
