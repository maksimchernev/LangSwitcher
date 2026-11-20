import AppKit

enum MenuBarIcon {
    static func make(needsPermission: Bool = false) -> NSImage {
        let size = NSSize(width: needsPermission ? 34 : 28, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            drawKey("A", at: 1)
            drawKey("Я", at: 15)
            if needsPermission {
                drawGlyph("!", centeredIn: NSRect(x: 28, y: 2, width: 6, height: 12), size: 10)
            }
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
        drawGlyph(label, centeredIn: key, size: 8)
    }

    private static func drawGlyph(_ text: String, centeredIn rect: NSRect, size: CGFloat) {
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        let glyph = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        glyph.draw(at: NSPoint(
            x: rect.midX - glyph.size().width / 2,
            y: rect.midY - font.capHeight / 2 + font.descender
        ))
    }
}
