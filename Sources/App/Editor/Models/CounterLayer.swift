import Foundation
import CoreGraphics
import AppKit

public final class CounterLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .counter
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String
    public var strokeWidth: CGFloat

    public var center: CGPoint
    public var radius: CGFloat
    public var value: Int
    public var pointerAngle: CGFloat // Radians for the teardrop peak
    public var tailDistance: CGFloat

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
        self.pointerAngle = pointerAngle ?? (-.pi / 4.0)
        self.tailDistance = tailDistance ?? (radius * 1.68)
        self.color = color
        self.strokeWidth = strokeWidth
        self.zIndex = zIndex
    }

    public func getPeakPoint() -> CGPoint {
        let angle = pointerAngle
        let dist = max(radius * 1.45, tailDistance)
        return CGPoint(x: center.x + dist * cos(angle), y: center.y + dist * sin(angle))
    }

    public func pathForTeardrop() -> CGPath {
        let angle = pointerAngle
        let dist = max(radius * 1.45, tailDistance)
        let peak = CGPoint(x: center.x + dist * cos(angle), y: center.y + dist * sin(angle))

        let cosBeta = min(1.0, max(-1.0, radius / dist))
        let beta = acos(cosBeta)

        let t2Angle = angle + beta

        let path = CGMutablePath()

        // Circular back arc from t2Angle to t1Angle passing through angle + .pi
        let steps = 36
        let arcSpan = 2 * .pi - 2 * beta
        for i in 0...steps {
            let frac = CGFloat(i) / CGFloat(steps)
            let a = t2Angle + frac * arcSpan
            let pt = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }

        // Tangent towards peak with rounded tip, then back to t2
        let t2 = CGPoint(x: center.x + radius * cos(t2Angle), y: center.y + radius * sin(t2Angle))
        path.addArc(tangent1End: peak, tangent2End: t2, radius: 3.5)
        path.addLine(to: t2)
        path.closeSubpath()

        return path
    }

    public func getBoundingBox() -> CGRect {
        let peak = getPeakPoint()
        let circleBox = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let peakBox = CGRect(x: peak.x - 4, y: peak.y - 4, width: 8, height: 8)
        return circleBox.union(peakBox).insetBy(dx: -6.0, dy: -6.0)
    }

    public func contains(point: CGPoint) -> Bool {
        let path = pathForTeardrop()
        return path.contains(point) || hypot(point.x - center.x, point.y - center.y) <= radius + 4.0
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        let peak = getPeakPoint()
        if hypot(point.x - peak.x, point.y - peak.y) <= max(radius, 10.0) {
            return 0
        }
        return nil
    }

    public func move(by delta: CGPoint) {
        center.x += delta.x
        center.y += delta.y
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        if index == 0 {
            let dx = point.x - center.x
            let dy = point.y - center.y
            pointerAngle = atan2(dy, dx)
            // Fixed tip distance locked at constant radial distance
            tailDistance = radius * 1.68
        }
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let badgeColor = NSColor(hex: color).cgColor
        context.setFillColor(badgeColor)

        // Draw solid teardrop / waterdrop shape
        let path = pathForTeardrop()
        context.addPath(path)
        context.fillPath()

        // Draw number text in pure white, bold and centered in the circular body
        let text = "\(value)"
        let fontSize = max(11.0, radius * 1.1)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attrString = NSAttributedString(string: text, attributes: textAttrs)
        let textSize = attrString.size()
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
