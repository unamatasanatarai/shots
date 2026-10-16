import Foundation
import CoreGraphics
import AppKit

public final class CounterLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .counter
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String {
        didSet { _cachedBadgeColor = nil }
    }
    public var strokeWidth: CGFloat

    public var center: CGPoint {
        didSet { invalidateCache() }
    }
    public var radius: CGFloat {
        didSet { invalidateCache() }
    }
    public var value: Int {
        didSet {
            _cachedAttributedString = nil
            _cachedTextSize = nil
        }
    }
    public var pointerAngle: CGFloat { // Radians for the teardrop peak
        didSet { invalidateCache() }
    }
    public var tailDistance: CGFloat {
        didSet { invalidateCache() }
    }

    private var _cachedPath: CGPath?
    private var _cachedBoundingBox: CGRect?
    private var _cachedPeak: CGPoint?
    private var _cachedAttributedString: NSAttributedString?
    private var _cachedTextSize: CGSize?
    private var _cachedBadgeColor: CGColor?

    @inline(__always)
    private func invalidateCache() {
        _cachedPath = nil
        _cachedBoundingBox = nil
        _cachedPeak = nil
        _cachedAttributedString = nil
        _cachedTextSize = nil
        _cachedBadgeColor = nil
    }

    public init(
        id: UUID = UUID(),
        center: CGPoint,
        radius: CGFloat = 16.0,
        value: Int = 1,
        pointerAngle: CGFloat? = nil,
        tailDistance: CGFloat? = nil,
        color: String = "#FF3B30",
        strokeWidth: CGFloat = 2.0,
        zIndex: Int = 0
    ) {
        self.id = id
        self.center = center
        self.radius = radius
        self.value = value
        // Default peak direction is 7:30pm (bottom-left, 135 degrees = 3*pi/4 radians in flipped canvas coordinates)
        self.pointerAngle = pointerAngle ?? (3.0 * .pi / 4.0)
        self.tailDistance = tailDistance ?? (radius * 1.68)
        self.color = color
        self.strokeWidth = strokeWidth
        self.zIndex = zIndex
    }

    /// Convenience initializer positioning the counter such that its pointer tip is exactly at `tip`
    public convenience init(
        tip: CGPoint,
        radius: CGFloat = 16.0,
        value: Int = 1,
        pointerAngle: CGFloat? = nil,
        tailDistance: CGFloat? = nil,
        color: String = "#FF3B30",
        strokeWidth: CGFloat = 2.0,
        zIndex: Int = 0
    ) {
        let angle: CGFloat = pointerAngle ?? (3.0 * .pi / 4.0)
        let tDist: CGFloat = tailDistance ?? (radius * 1.68)
        let dist = max(radius * 1.35, tDist)
        let computedCenter = CGPoint(
            x: tip.x - dist * cos(angle),
            y: tip.y - dist * sin(angle)
        )
        self.init(
            center: computedCenter,
            radius: radius,
            value: value,
            pointerAngle: angle,
            tailDistance: tDist,
            color: color,
            strokeWidth: strokeWidth,
            zIndex: zIndex
        )
    }

    public func getPeakPoint() -> CGPoint {
        if let cached = _cachedPeak { return cached }
        let angle = pointerAngle
        let dist = max(radius * 1.35, tailDistance)
        let peak = CGPoint(x: center.x + dist * cos(angle), y: center.y + dist * sin(angle))
        _cachedPeak = peak
        return peak
    }

    public func pathForTeardrop() -> CGPath {
        if let cached = _cachedPath { return cached }

        let angle = pointerAngle
        let dist = max(radius * 1.35, tailDistance)
        let peak = getPeakPoint()

        // Departure angle beta from peak axis to flank base on circle (~48 deg = 0.84 rad)
        let beta: CGFloat = 0.84
        let t1Angle = angle - beta
        let t2Angle = angle + beta

        let p1 = CGPoint(x: center.x + radius * cos(t1Angle), y: center.y + radius * sin(t1Angle))
        let p2 = CGPoint(x: center.x + radius * cos(t2Angle), y: center.y + radius * sin(t2Angle))

        let tipR = max(1.5, radius * 0.055)
        let perpAngle = angle + .pi / 2.0
        let tip1 = CGPoint(x: peak.x - tipR * cos(perpAngle), y: peak.y - tipR * sin(perpAngle))
        let tip2 = CGPoint(x: peak.x + tipR * cos(perpAngle), y: peak.y + tipR * sin(perpAngle))

        let handleLen = (dist - radius) * 0.55
        let c1P1 = CGPoint(
            x: p1.x + handleLen * cos(t1Angle + .pi / 2.0),
            y: p1.y + handleLen * sin(t1Angle + .pi / 2.0)
        )
        let c2Tip1 = CGPoint(
            x: tip1.x - handleLen * 0.7 * cos(angle - 0.15),
            y: tip1.y - handleLen * 0.7 * sin(angle - 0.15)
        )

        let c1P2 = CGPoint(
            x: p2.x + handleLen * cos(t2Angle - .pi / 2.0),
            y: p2.y + handleLen * sin(t2Angle - .pi / 2.0)
        )
        let c2Tip2 = CGPoint(
            x: tip2.x - handleLen * 0.7 * cos(angle + 0.15),
            y: tip2.y - handleLen * 0.7 * sin(angle + 0.15)
        )

        let path = CGMutablePath()

        // 1. Hardware-accelerated circular back arc along the body from t2Angle around to t1Angle
        let arcSpan = 2.0 * .pi - 2.0 * beta
        path.move(to: p2)
        path.addArc(center: center, radius: radius, startAngle: t2Angle, endAngle: t2Angle + arcSpan, clockwise: false)

        // 2. Smooth bezier flank from p1 to tip1
        path.addCurve(to: tip1, control1: c1P1, control2: c2Tip1)

        // 3. Rounded peak cap
        let capSteps = 8
        for i in 1...capSteps {
            let a = perpAngle - .pi + (CGFloat(i) / CGFloat(capSteps)) * .pi
            let pt = CGPoint(x: peak.x + tipR * cos(a), y: peak.y + tipR * sin(a))
            path.addLine(to: pt)
        }

        // 4. Smooth bezier flank from tip2 back to p2
        path.addCurve(to: p2, control1: c2Tip2, control2: c1P2)
        path.closeSubpath()

        _cachedPath = path
        return path
    }

    public func getBoundingBox() -> CGRect {
        if let cached = _cachedBoundingBox { return cached }
        let peak = getPeakPoint()
        let circleBox = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let peakBox = CGRect(x: peak.x - 4, y: peak.y - 4, width: 8, height: 8)
        let box = circleBox.union(peakBox).insetBy(dx: -6.0, dy: -6.0)
        _cachedBoundingBox = box
        return box
    }

    public func contains(point: CGPoint) -> Bool {
        guard getBoundingBox().contains(point) else { return false }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let rCheck = radius + 4.0
        if dx * dx + dy * dy <= rCheck * rCheck {
            return true
        }
        return pathForTeardrop().contains(point)
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        let peak = getPeakPoint()
        let hitRadius = max(radius, 10.0)
        let dx = point.x - peak.x
        let dy = point.y - peak.y
        if dx * dx + dy * dy <= hitRadius * hitRadius {
            return 0
        }
        return nil
    }

    public func move(by delta: CGPoint) {
        center.x += delta.x
        center.y += delta.y
        invalidateCache()
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        if index == 0 {
            let dx = point.x - center.x
            let dy = point.y - center.y
            pointerAngle = atan2(dy, dx)
            // Fixed tip distance locked at constant radial distance
            tailDistance = radius * 1.68
            invalidateCache()
        }
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let badgeColor = _cachedBadgeColor ?? {
            let c = FastColor.shared.cgColor(hex: color)
            _cachedBadgeColor = c
            return c
        }()
        context.setFillColor(badgeColor)

        // Subtle natural shadow for depth and crispness on badge body
        context.setShadow(offset: CGSize(width: 0, height: -1.0), blur: 2.5, color: NSColor.black.withAlphaComponent(0.25).cgColor)

        // Draw solid teardrop / waterdrop shape
        let path = pathForTeardrop()
        context.addPath(path)
        context.fillPath()

        // Remove shadow before drawing text so number stays crisp
        context.setShadow(offset: .zero, blur: 0, color: nil)

        // Draw number text in pure white, bold and centered in the circular body
        let attrString: NSAttributedString
        let textSize: CGSize
        if let cachedStr = _cachedAttributedString, let cachedSz = _cachedTextSize {
            attrString = cachedStr
            textSize = cachedSz
        } else {
            let text = "\(value)"
            let fontSize = max(11.0, radius * 1.1)
            let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white
            ]
            let str = NSAttributedString(string: text, attributes: textAttrs)
            let sz = str.size()
            _cachedAttributedString = str
            _cachedTextSize = sz
            attrString = str
            textSize = sz
        }

        let textOrigin = CGPoint(
            x: center.x - textSize.width / 2.0,
            y: center.y - textSize.height / 2.0
        )

        let nsCtx = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        attrString.draw(at: textOrigin)
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
    }

    public func clone() -> AnnotationLayer {
        CounterLayer(
            id: UUID(),
            center: center,
            radius: radius,
            value: value,
            pointerAngle: pointerAngle,
            tailDistance: tailDistance,
            color: color,
            strokeWidth: strokeWidth,
            zIndex: zIndex
        )
    }
}
