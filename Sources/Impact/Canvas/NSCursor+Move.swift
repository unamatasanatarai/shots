import AppKit

public extension NSCursor {
    /// A high-contrast 4-directional move cursor styled with dark shadow and white fill.
    static let fourDirectionalMove: NSCursor = {
        let symConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        guard let sym = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right", accessibilityDescription: "Move")?.withSymbolConfiguration(symConfig) else {
            return NSCursor.openHand
        }
        let size = NSSize(width: 26, height: 26)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let symRect = CGRect(
                x: (rect.width - sym.size.width) / 2.0,
                y: (rect.height - sym.size.height) / 2.0,
                width: sym.size.width,
                height: sym.size.height
            )

            // Multi-pass dark outline/shadow for high contrast across dark and light canvases
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 2.5, color: NSColor.black.withAlphaComponent(0.9).cgColor)
            sym.draw(in: symRect.offsetBy(dx: 0.5, dy: 0))
            sym.draw(in: symRect.offsetBy(dx: -0.5, dy: 0))
            sym.draw(in: symRect.offsetBy(dx: 0, dy: 0.5))
            sym.draw(in: symRect.offsetBy(dx: 0, dy: -0.5))
            ctx.restoreGState()

            // Crisp white foreground symbol
            let tinted = NSImage(size: sym.size, flipped: false) { r in
                sym.draw(in: r)
                NSColor.white.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: symRect)
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 13, y: 13))
    }()
}
