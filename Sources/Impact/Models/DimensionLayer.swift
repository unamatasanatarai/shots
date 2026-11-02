import Foundation
import CoreGraphics
import AppKit

public final class DimensionLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .dimension
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String {
        didSet { _cachedBadge = nil }
    }
    public var strokeWidth: CGFloat {
        didSet { _cachedBoundingBox = nil }
    }

    public var start: CGPoint {
        didSet { _cachedBoundingBox = nil; _cachedBadge = nil }
    }
    public var end: CGPoint {
        didSet { _cachedBoundingBox = nil; _cachedBadge = nil }
    }

    private var _cachedBoundingBox: CGRect?

    /// The image area the label should stay inside when it sits beside a short ruler (set by the document)
    public var labelBounds: CGRect? {
        didSet { if labelBounds != oldValue { _cachedBoundingBox = nil; _cachedBadge = nil } }
    }

    /// The distance badge: its text and pill rect, built once per geometry/color change instead of every frame
    private var _cachedBadge: (text: NSAttributedString, rect: CGRect)?
    private static let badgeFont = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .bold)

    private func badge() -> (text: NSAttributedString, rect: CGRect) {
        if let cached = _cachedBadge { return cached }
        let dx = end.x - start.x, dy = end.y - start.y
        let distance = Int(round(sqrt(dx * dx + dy * dy)))
        let text = NSAttributedString(string: "\(distance) px", attributes: [.font: Self.badgeFont, .foregroundColor: NSColor.white])
        let size = text.size()
        let pill = CGSize(width: size.width + 10.0, height: size.height + 4.0)
        let rect = Self.badgeRect(pill: pill, start: start, end: end, within: labelBounds)
        _cachedBadge = (text, rect)
        return (text, rect)
    }

    /// The badge rect for tests and hit areas
    var badgeRect: CGRect { badge().rect }

    /// Centered on the ruler when the ruler is longer than the badge (plus its end ticks). Otherwise beside it:
    /// above a mostly horizontal ruler (else below, right, left), right of a mostly vertical one (else left,
    /// above, below), the first side that fits inside `bounds`, slid along that side to stay inside
    static func badgeRect(pill: CGSize, start: CGPoint, end: CGPoint, within bounds: CGRect? = nil) -> CGRect {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        let mid = CGPoint(x: (start.x + end.x) / 2.0, y: (start.y + end.y) / 2.0)
        let centered = CGRect(x: mid.x - pill.width / 2.0, y: mid.y - pill.height / 2.0, width: pill.width, height: pill.height)
        // The badge's extent along the ruler's direction, plus room to see both end ticks
        let ux = length > 0.001 ? abs(dx) / length : 1.0
        let uy = length > 0.001 ? abs(dy) / length : 0.0
        let extentAlong = ux * pill.width + uy * pill.height
        let tickRoom: CGFloat = 2.0 * 6.0
        guard length < extentAlong + tickRoom else { return centered }

        let clearance = tickHalfLength + 4.0
        let line = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(dx), height: abs(dy))
        // Canvas y grows downward
        let top = CGRect(x: centered.minX, y: line.minY - clearance - pill.height, width: pill.width, height: pill.height)
        let bottom = CGRect(x: centered.minX, y: line.maxY + clearance, width: pill.width, height: pill.height)
        let right = CGRect(x: line.maxX + clearance, y: centered.minY, width: pill.width, height: pill.height)
        let left = CGRect(x: line.minX - clearance - pill.width, y: centered.minY, width: pill.width, height: pill.height)
        let horizontal = abs(dx) >= abs(dy)
        let order: [(CGRect, Bool)] = horizontal
            ? [(top, true), (bottom, true), (right, false), (left, false)]
            : [(right, false), (left, false), (top, true), (bottom, true)]
        guard let bounds = bounds, !bounds.isEmpty else { return order[0].0 }

        // Slide along the side (x for above/below, y for left/right) to stay inside the image
        func slid(_ r: CGRect, alongX: Bool) -> CGRect {
            var r = r
            if alongX {
                r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
            } else {
                r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
            }
            return r
        }
        let candidates = order.map { slid($0.0, alongX: $0.1) }
        let epsilon: CGFloat = 0.01
        if let fit = candidates.first(where: { bounds.insetBy(dx: -epsilon, dy: -epsilon).contains($0) }) { return fit }
        // Image too small for any side: the side showing the most of the label
        func visible(_ r: CGRect) -> CGFloat { let i = r.intersection(bounds); return i.isNull ? 0 : i.width * i.height }
        return candidates.max(by: { visible($0) < visible($1) }) ?? candidates[0]
    }

    static let tickHalfLength: CGFloat = 7.0

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
        // The badge is centered on the line and can be wider than the padding (vertical rulers); +4 for its shadow
        let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).union(badge().rect.insetBy(dx: -4, dy: -4))
        _cachedBoundingBox = box
        return box
    }

    public func contains(point: CGPoint) -> Bool {
        guard getBoundingBox().contains(point) else { return false }
        if badge().rect.contains(point) { return true }
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
        nearestHandle([start, end], to: point, radius: radius)
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

        // Main measurement line (butt caps: round ones would spill past the measured span into the gap's ends)
        context.setLineCap(.butt)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Perpendicular tick markers at start and end
        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)
        let perp = angle + .pi / 2.0
        let tickHalf = Self.tickHalfLength

        let cosP = cos(perp) * tickHalf
        let sinP = sin(perp) * tickHalf

        // The ticks sit just outside the measured span: their inner edges are exactly at start and end,
        // so a 10 px measurement shows 10 px between them (a centered tick would cover half its width)
        let out = strokeWidth / 2.0
        let ox = cos(angle) * out, oy = sin(angle) * out
        let sTick = CGPoint(x: start.x - ox, y: start.y - oy)
        let eTick = CGPoint(x: end.x + ox, y: end.y + oy)
        context.setLineCap(.butt)

        let s1 = CGPoint(x: sTick.x - cosP, y: sTick.y - sinP)
        let s2 = CGPoint(x: sTick.x + cosP, y: sTick.y + sinP)
        context.move(to: s1); context.addLine(to: s2); context.strokePath()

        let e1 = CGPoint(x: eTick.x - cosP, y: eTick.y - sinP)
        let e2 = CGPoint(x: eTick.x + cosP, y: eTick.y + sinP)
        context.move(to: e1); context.addLine(to: e2); context.strokePath()

        // Display exact pixel distance badge in the center
        let (attrString, badgeRect) = badge()

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
        ).withLabelBounds(labelBounds)
    }

    private func withLabelBounds(_ bounds: CGRect?) -> DimensionLayer {
        labelBounds = bounds
        return self
    }
}
