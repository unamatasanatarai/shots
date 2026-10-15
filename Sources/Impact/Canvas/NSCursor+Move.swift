import AppKit

public extension NSCursor {
    /// UFO: Enemy Unknown tactical pointer cursor with vertical left edge, inner notch, and wingtip.
    static let ufoPointer: NSCursor = {
        let size = NSSize(width: 24, height: 26)
        let img = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let originX: CGFloat = 2.0
            let originY: CGFloat = 2.0
            let h: CGFloat = 20.0
            let scale = h / 62.0

            let p0 = CGPoint(x: originX + 0 * scale, y: originY + 0 * scale)
            let p1 = CGPoint(x: originX + 0 * scale, y: originY + 62 * scale)
            let p2 = CGPoint(x: originX + 19 * scale, y: originY + 47 * scale)
            let p3 = CGPoint(x: originX + 46 * scale, y: originY + 45 * scale)

            // Subtle shadow for legibility over any background
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0.5, height: -0.5), blur: 1.5, color: NSColor.black.withAlphaComponent(0.45).cgColor)
            ctx.beginPath()
            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.addLine(to: p2)
            ctx.addLine(to: p3)
            ctx.closePath()
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            // Crisp white outline
            ctx.saveGState()
            ctx.beginPath()
            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.addLine(to: p2)
            ctx.addLine(to: p3)
            ctx.closePath()
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineJoin(.miter)
            ctx.strokePath()
            ctx.restoreGState()

            // Solid black body
            ctx.saveGState()
            ctx.beginPath()
            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.addLine(to: p2)
            ctx.addLine(to: p3)
            ctx.closePath()
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 2, y: 2))
    }()

    /// Helper to render sleek directional arrow cursors
    private static func makeSleekCursor(angles: [CGFloat]) -> NSCursor {
        let size = NSSize(width: 28, height: 28)
        let center = CGPoint(x: 14, y: 14)
        let armLen: CGFloat = 10.0
        let headLen: CGFloat = 4.8
        let headWidth: CGFloat = 4.8
        let stemWidth: CGFloat = 1.6

        let img = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // Pass 1: Crisp white border/halo for high contrast across dark and light canvases
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.setLineWidth(stemWidth + 2.0)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.miter)

            for a in angles {
                let cosA = cos(a)
                let sinA = sin(a)
                let perpX = -sinA
                let perpY = cosA
                let tip = CGPoint(x: center.x + cosA * (armLen + 0.6), y: center.y + sinA * (armLen + 0.6))
                let base = CGPoint(x: tip.x - cosA * (headLen + 0.6), y: tip.y - sinA * (headLen + 0.6))
                let p1 = CGPoint(x: base.x + perpX * (headWidth / 2.0 + 0.8), y: base.y + perpY * (headWidth / 2.0 + 0.8))
                let p2 = CGPoint(x: base.x - perpX * (headWidth / 2.0 + 0.8), y: base.y - perpY * (headWidth / 2.0 + 0.8))

                ctx.move(to: center)
                ctx.addLine(to: base)
                ctx.strokePath()

                ctx.beginPath()
                ctx.move(to: tip)
                ctx.addLine(to: p1)
                ctx.addLine(to: p2)
                ctx.closePath()
                ctx.fillPath()
            }
            ctx.restoreGState()

            // Pass 2: Solid black core
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setLineWidth(stemWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.miter)

            for a in angles {
                let cosA = cos(a)
                let sinA = sin(a)
                let perpX = -sinA
                let perpY = cosA
                let tip = CGPoint(x: center.x + cosA * armLen, y: center.y + sinA * armLen)
                let base = CGPoint(x: tip.x - cosA * headLen, y: tip.y - sinA * headLen)
                let p1 = CGPoint(x: base.x + perpX * (headWidth / 2.0), y: base.y + perpY * (headWidth / 2.0))
                let p2 = CGPoint(x: base.x - perpX * (headWidth / 2.0), y: base.y - perpY * (headWidth / 2.0))

                ctx.move(to: center)
                ctx.addLine(to: base)
                ctx.strokePath()

                ctx.beginPath()
                ctx.move(to: tip)
                ctx.addLine(to: p1)
                ctx.addLine(to: p2)
                ctx.closePath()
                ctx.fillPath()
            }
            ctx.restoreGState()

            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 14, y: 14))
    }

    /// Sleek 4-directional move cursor
    static let sleekMove: NSCursor = makeSleekCursor(angles: [0, .pi / 2, .pi, 3 * .pi / 2])

    /// 4-directional move cursor backwards-compatible alias
    static let fourDirectionalMove: NSCursor = sleekMove

    /// Sleek horizontal resize cursor (<->)
    static let sleekResizeHorizontal: NSCursor = makeSleekCursor(angles: [0, .pi])
    static let sleekResizeLeftRight: NSCursor = sleekResizeHorizontal

    /// Sleek vertical resize cursor (^v)
    static let sleekResizeVertical: NSCursor = makeSleekCursor(angles: [.pi / 2, 3 * .pi / 2])
    static let sleekResizeUpDown: NSCursor = sleekResizeVertical

    /// Sleek diagonal NW-SE resize cursor (\)
    static let sleekResizeDiagonalNWSE: NSCursor = makeSleekCursor(angles: [-.pi * 3 / 4, .pi / 4])

    /// Sleek diagonal NE-SW resize cursor (/)
    static let sleekResizeDiagonalNESW: NSCursor = makeSleekCursor(angles: [-.pi / 4, .pi * 3 / 4])
}
