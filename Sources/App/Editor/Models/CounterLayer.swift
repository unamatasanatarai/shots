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
    public var pointerAngle: CGFloat? // Optional pointer tip angle in radians

    public init(
        id: UUID = UUID(),
        center: CGPoint,
        radius: CGFloat = 14.0,
        value: Int = 1,
        pointerAngle: CGFloat? = nil,
        color: String = "#007AFF",
        strokeWidth: CGFloat = 2.0,
        zIndex: Int = 0
    ) {
        self.id = id
        self.center = center
        self.radius = radius
        self.value = value
        self.pointerAngle = pointerAngle
        self.color = color
        self.strokeWidth = strokeWidth
        self.zIndex = zIndex
    }

    public func getBoundingBox() -> CGRect {
        let pad = radius * 1.6 + 6.0
        return CGRect(
            x: center.x - pad,
            y: center.y - pad,
            width: pad * 2,
            height: pad * 2
        )
    }

    public func contains(point: CGPoint) -> Bool {
        return hypot(point.x - center.x, point.y - center.y) <= radius + 6.0
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        if let angle = pointerAngle {
            let pointerTip = CGPoint(
                x: center.x + (self.radius + 12.0) * cos(angle),
                y: center.y + (self.radius + 12.0) * sin(angle)
            )
            if hypot(point.x - pointerTip.x, point.y - pointerTip.y) <= radius {
                return 0
            }
        }
        return nil
    }

    public func move(by delta: CGPoint) {
        center.x += delta.x
        center.y += delta.y
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        if index == 0 {
            pointerAngle = atan2(point.y - center.y, point.x - center.x)
        }
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let badgeNSColor = NSColor(hex: color)
        let badgeCGColor = badgeNSColor.cgColor

        // Draw pointer if angle is set
        if let angle = pointerAngle {
            let tipDistance = radius + 12.0
            let tip = CGPoint(x: center.x + tipDistance * cos(angle), y: center.y + tipDistance * sin(angle))
            let p1 = CGPoint(x: center.x + radius * cos(angle - .pi / 5.0), y: center.y + radius * sin(angle - .pi / 5.0))
            let p2 = CGPoint(x: center.x + radius * cos(angle + .pi / 5.0), y: center.y + radius * sin(angle + .pi / 5.0))

            let pointerPath = CGMutablePath()
            pointerPath.move(to: p1)
            pointerPath.addLine(to: tip)
            pointerPath.addLine(to: p2)
            pointerPath.closeSubpath()

            context.setFillColor(badgeCGColor)
            context.addPath(pointerPath)
            context.fillPath()
        }

        // Draw circular badge
        let circleRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.setFillColor(badgeCGColor)
        context.fillEllipse(in: circleRect)

        // White border
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(strokeWidth)
        context.strokeEllipse(in: circleRect)

        // Draw number text in pure white
        let text = "\(value)"
        let fontSize = max(10.0, radius * 1.1)
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
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

        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: false)
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
            color: color,
            strokeWidth: strokeWidth,
            zIndex: zIndex
        )
    }
}
