import Foundation
import CoreGraphics
import AppKit

public final class ArrowLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .arrow
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String
    public var strokeWidth: CGFloat

    public var start: CGPoint
    public var control: CGPoint // Midpoint quadratic Bezier control point
    public var end: CGPoint
    public var headType: ArrowHeadType

    public init(
        id: UUID = UUID(),
        start: CGPoint,
        control: CGPoint? = nil,
        end: CGPoint,
        color: String = "#FF3B30",
        strokeWidth: CGFloat = 4.0,
        headType: ArrowHeadType = .filled,
        zIndex: Int = 0
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.control = control ?? CGPoint(x: (start.x + end.x) / 2.0, y: (start.y + end.y) / 2.0)
        self.color = color
        self.strokeWidth = strokeWidth
        self.headType = headType
        self.zIndex = zIndex
    }

    // MARK: - Bounds Calculation

    public func getBoundingBox() -> CGRect {
        // Sample points along the quadratic curve: B(t) = (1-t)^2*P0 + 2(1-t)t*P1 + t^2*P2
        var minX = min(start.x, end.x, control.x)
        var minY = min(start.y, end.y, control.y)
        var maxX = max(start.x, end.x, control.x)
        var maxY = max(start.y, end.y, control.y)

        // For precise quadratic extrema
        let denomX = start.x - 2 * control.x + end.x
        if abs(denomX) > 0.001 {
            let tx = (start.x - control.x) / denomX
            if tx > 0 && tx < 1 {
                let x = (1 - tx) * (1 - tx) * start.x + 2 * (1 - tx) * tx * control.x + tx * tx * end.x
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        let denomY = start.y - 2 * control.y + end.y
        if abs(denomY) > 0.001 {
            let ty = (start.y - control.y) / denomY
            if ty > 0 && ty < 1 {
                let y = (1 - ty) * (1 - ty) * start.y + 2 * (1 - ty) * ty * control.y + ty * ty * end.y
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }

        let padding = max(strokeWidth * 4.0 + 16.0, 48.0)
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: maxX - minX + padding * 2,
            height: maxY - minY + padding * 2
        )
    }

    public func contains(point: CGPoint) -> Bool {
        // Distance check along sampled Bezier curve
        let steps = 30
        let threshold = max(strokeWidth * 1.5, 10.0)
        var prev = start
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let curr = pointOnCurve(t: t)
            if distanceToSegment(p: point, a: prev, b: curr) <= threshold {
                return true
            }
            prev = curr
        }
        return false
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        if hypot(point.x - start.x, point.y - start.y) <= radius { return 0 }
        if hypot(point.x - control.x, point.y - control.y) <= radius { return 1 }
        if hypot(point.x - end.x, point.y - end.y) <= radius { return 2 }
        return nil
    }

    public func move(by delta: CGPoint) {
        start = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
        control = CGPoint(x: control.x + delta.x, y: control.y + delta.y)
        end = CGPoint(x: end.x + delta.x, y: end.y + delta.y)
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        switch index {
        case 0: start = point
        case 1: control = point
        case 2: end = point
        default: break
        }
    }

    // MARK: - Drawing

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let strokeColor = NSColor(hex: color).cgColor
        context.setStrokeColor(strokeColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Subtle natural shadow for depth and crispness
        context.setShadow(offset: CGSize(width: 0, height: -1.0), blur: 2.5, color: NSColor.black.withAlphaComponent(0.25).cgColor)

        let totalDist = hypot(end.x - start.x, end.y - start.y)
        guard totalDist > 4.0 else {
            context.restoreGState()
            return
        }

        // Maximum width scale: stroke scales slightly with arrow length, but strictly capped at a maximum width
        let lengthFactor = min(1.0, max(0.0, (totalDist - 20.0) / 350.0))
        let effectiveStroke = min(5.5, max(2.5, strokeWidth * (0.8 + 0.35 * lengthFactor)))
        context.setLineWidth(effectiveStroke)

        let path = pathForArrow()
        context.addPath(path)
        context.strokePath()

        // If bidirectional, draw open-chevron arrowhead at 'start' pointing backwards
        if headType == .biDirectional {
            let startTangent = tangentAt(t: 0.0) + .pi
            let headLength = min(28.0, max(9.0, totalDist * 0.065 + 10.0))
            let barbAngle: CGFloat = 32.0 * .pi / 180.0

            let leftAngle = startTangent + .pi - barbAngle
            let rightAngle = startTangent + .pi + barbAngle

            let leftBarb = CGPoint(x: start.x + cos(leftAngle) * headLength, y: start.y + sin(leftAngle) * headLength)
            let rightBarb = CGPoint(x: start.x + cos(rightAngle) * headLength, y: start.y + sin(rightAngle) * headLength)

            let headPath = CGMutablePath()
            headPath.move(to: leftBarb)
            headPath.addLine(to: start)
            headPath.addLine(to: rightBarb)

            context.addPath(headPath)
            context.strokePath()
        }

        context.restoreGState()
    }

    public func pathForArrow() -> CGPath {
        let totalDist = hypot(end.x - start.x, end.y - start.y)
        guard totalDist > 4.0 else {
            return CGMutablePath()
        }

        let path = CGMutablePath()

        // 1. Shaft: Quadratic Bezier from start to end
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)

        // 2. Head: Handdrawn open chevron wings anchored at end
        let endTangent = tangentAt(t: 1.0)
        let headLength = min(28.0, max(9.0, totalDist * 0.065 + 10.0))
        let barbAngle: CGFloat = 32.0 * .pi / 180.0

        let leftAngle = endTangent + .pi - barbAngle
        let rightAngle = endTangent + .pi + barbAngle

        let leftBarb = CGPoint(x: end.x + cos(leftAngle) * headLength, y: end.y + sin(leftAngle) * headLength)
        let rightBarb = CGPoint(x: end.x + cos(rightAngle) * headLength, y: end.y + sin(rightAngle) * headLength)

        path.move(to: leftBarb)
        path.addLine(to: end)
        path.addLine(to: rightBarb)

        return path
    }

    // MARK: - Math Helpers

    private func pointOnCurve(t: CGFloat) -> CGPoint {
        let u = 1.0 - t
        let x = u * u * start.x + 2 * u * t * control.x + t * t * end.x
        let y = u * u * start.y + 2 * u * t * control.y + t * t * end.y
        return CGPoint(x: x, y: y)
    }

    private func tangentAt(t: CGFloat) -> CGFloat {
        // Derivative: B'(t) = 2(1-t)(control - start) + 2t(end - control)
        let u = 1.0 - t
        let dx = 2 * u * (control.x - start.x) + 2 * t * (end.x - control.x)
        let dy = 2 * u * (control.y - start.y) + 2 * t * (end.y - control.y)
        return atan2(dy, dx)
    }

    private func distanceToSegment(p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq < 0.001 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }

    public func clone() -> AnnotationLayer {
        ArrowLayer(
            id: UUID(),
            start: start,
            control: control,
            end: end,
            color: color,
            strokeWidth: strokeWidth,
            headType: headType,
            zIndex: zIndex
        )
    }
}
