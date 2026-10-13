import Foundation
import CoreGraphics
import AppKit

public final class DimensionLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .dimension
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String
    public var strokeWidth: CGFloat

    public var start: CGPoint
    public var end: CGPoint

    public init(
        id: UUID = UUID(),
        start: CGPoint,
        end: CGPoint,
        color: String = "#FF9500",
        strokeWidth: CGFloat = 2.0,
        zIndex: Int = 0
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.color = color
        self.strokeWidth = strokeWidth
        self.zIndex = zIndex
    }

    public func getBoundingBox() -> CGRect {
        let pad = strokeWidth + 24.0
        let minX = min(start.x, end.x) - pad
        let minY = min(start.y, end.y) - pad
        let maxX = max(start.x, end.x) + pad
        let maxY = max(start.y, end.y) + pad
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func contains(point: CGPoint) -> Bool {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lenSq = dx * dx + dy * dy
        if lenSq < 0.001 { return hypot(point.x - start.x, point.y - start.y) <= 12.0 }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lenSq))
        let proj = CGPoint(x: aX_t(t), y: aY_t(t))
        return hypot(point.x - proj.x, point.y - proj.y) <= 12.0
    }

    private func aX_t(_ t: CGFloat) -> CGFloat { start.x + t * (end.x - start.x) }
    private func aY_t(_ t: CGFloat) -> CGFloat { start.y + t * (end.y - start.y) }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        if hypot(point.x - start.x, point.y - start.y) <= radius { return 0 }
        if hypot(point.x - end.x, point.y - end.y) <= radius { return 1 }
        return nil
    }

    public func move(by delta: CGPoint) {
        start = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
        end = CGPoint(x: end.x + delta.x, y: end.y + delta.y)
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        if index == 0 { start = point }
        else if index == 1 { end = point }
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let strokeNSColor = NSColor(hex: color)
        let strokeCGColor = strokeNSColor.cgColor

        context.setStrokeColor(strokeCGColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)

        // Main measurement line
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Perpendicular tick markers at start and end
        let angle = atan2(end.y - start.y, end.x - start.x)
        let perp = angle + .pi / 2.0
        let tickHalf: CGFloat = 7.0

        let s1 = CGPoint(x: start.x - tickHalf * cos(perp), y: start.y - tickHalf * sin(perp))
        let s2 = CGPoint(x: start.x + tickHalf * cos(perp), y: start.y + tickHalf * sin(perp))
        context.move(to: s1); context.addLine(to: s2); context.strokePath()

        let e1 = CGPoint(x: end.x - tickHalf * cos(perp), y: end.y - tickHalf * sin(perp))
        let e2 = CGPoint(x: end.x + tickHalf * cos(perp), y: end.y + tickHalf * sin(perp))
        context.move(to: e1); context.addLine(to: e2); context.strokePath()

        // Display exact pixel distance badge in the center
        let distance = Int(round(hypot(end.x - start.x, end.y - start.y)))
        let text = "\(distance) px"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .bold)

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attrString = NSAttributedString(string: text, attributes: textAttrs)
        let textSize = attrString.size()

        let mid = CGPoint(x: (start.x + end.x) / 2.0, y: (start.y + end.y) / 2.0)
        let badgeRect = CGRect(
            x: mid.x - textSize.width / 2.0 - 5.0,
            y: mid.y - textSize.height / 2.0 - 2.0,
            width: textSize.width + 10.0,
            height: textSize.height + 4.0
        )

        // Badge pill background
        context.setFillColor(NSColor(hex: color).withAlphaComponent(0.90).cgColor)
        let pillPath = CGPath(roundedRect: badgeRect, cornerWidth: 4.0, cornerHeight: 4.0, transform: nil)
        context.addPath(pillPath)
        context.fillPath()

        // Text
        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsCtx
        attrString.draw(at: CGPoint(x: badgeRect.minX + 5.0, y: badgeRect.minY + 2.0))
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
    }

    public func clone() -> AnnotationLayer {
        DimensionLayer(
            id: UUID(),
            start: start,
            end: end,
            color: color,
            strokeWidth: strokeWidth,
            zIndex: zIndex
        )
    }
}
