import Foundation
import CoreGraphics
import AppKit

public final class DimensionLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .dimension
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String
    public var strokeWidth: CGFloat {
        didSet { _cachedBoundingBox = nil }
    }

    public var start: CGPoint {
        didSet { _cachedBoundingBox = nil }
    }
    public var end: CGPoint {
        didSet { _cachedBoundingBox = nil }
    }

    private var _cachedBoundingBox: CGRect?

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
        if let cached = _cachedBoundingBox { return cached }
        let pad = strokeWidth + 24.0
        let minX = min(start.x, end.x) - pad
        let minY = min(start.y, end.y) - pad
        let maxX = max(start.x, end.x) + pad
        let maxY = max(start.y, end.y) + pad
        let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        _cachedBoundingBox = box
        return box
    }

    public func contains(point: CGPoint) -> Bool {
        guard getBoundingBox().contains(point) else { return false }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lenSq = dx * dx + dy * dy
        if lenSq < 0.001 {
            let px = point.x - start.x
            let py = point.y - start.y
            return px * px + py * py <= 144.0
        }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lenSq))
        let projX = aX_t(t)
        let projY = aY_t(t)
        let px = point.x - projX
        let py = point.y - projY
        return px * px + py * py <= 144.0
    }

    private func aX_t(_ t: CGFloat) -> CGFloat { start.x + t * (end.x - start.x) }
    private func aY_t(_ t: CGFloat) -> CGFloat { start.y + t * (end.y - start.y) }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        let rSq = radius * radius
        let dx0 = point.x - start.x
        let dy0 = point.y - start.y
        if dx0 * dx0 + dy0 * dy0 <= rSq { return 0 }

        let dx1 = point.x - end.x
        let dy1 = point.y - end.y
        if dx1 * dx1 + dy1 * dy1 <= rSq { return 1 }
        return nil
    }

    public func move(by delta: CGPoint) {
        start = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
        end = CGPoint(x: end.x + delta.x, y: end.y + delta.y)
        _cachedBoundingBox = nil
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        if index == 0 { start = point }
        else if index == 1 { end = point }
        _cachedBoundingBox = nil
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        // Subtle natural shadow for depth and crispness
        context.setShadow(
            offset: CGSize(width: 0, height: -1.0),
            blur: 2.5,
            color: NSColor.black.withAlphaComponent(0.25).cgColor
        )

        let strokeCGColor = FastColor.shared.cgColor(hex: color)
        context.setStrokeColor(strokeCGColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)

        // Main measurement line
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Perpendicular tick markers at start and end
        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)
        let perp = angle + .pi / 2.0
        let tickHalf: CGFloat = 7.0

        let cosP = cos(perp) * tickHalf
        let sinP = sin(perp) * tickHalf

        let s1 = CGPoint(x: start.x - cosP, y: start.y - sinP)
        let s2 = CGPoint(x: start.x + cosP, y: start.y + sinP)
        context.move(to: s1); context.addLine(to: s2); context.strokePath()

        let e1 = CGPoint(x: end.x - cosP, y: end.y - sinP)
        let e2 = CGPoint(x: end.x + cosP, y: end.y + sinP)
        context.move(to: e1); context.addLine(to: e2); context.strokePath()

        // Display exact pixel distance badge in the center
        let distance = Int(round(sqrt(dx * dx + dy * dy)))
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
        context.setFillColor(FastColor.shared.cgColor(hex: color, alpha: 0.90))
        let pillPath = CGPath(roundedRect: badgeRect, cornerWidth: 4.0, cornerHeight: 4.0, transform: nil)
        context.addPath(pillPath)
        context.fillPath()

        // Clear shadow before drawing text for crispness
        context.setShadow(offset: .zero, blur: 0, color: nil)

        // Text
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        attrString.draw(at: CGPoint(x: badgeRect.minX + 5.0, y: badgeRect.minY + 2.0))
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
    }

    public func clone(withID newID: UUID) -> AnnotationLayer {
        DimensionLayer(
            id: newID,
            start: start,
            end: end,
            color: color,
            strokeWidth: strokeWidth,
            zIndex: zIndex
        )
    }
}
