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

        let padding = strokeWidth * 3.5 + 12.0
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
        context.setFillColor(strokeColor)
        context.setStrokeColor(strokeColor)

        let totalDist = hypot(end.x - start.x, end.y - start.y)
        guard totalDist > 4.0 else {
            context.restoreGState()
            return
        }

        // Tapered arrow geometry:
        // Width starts small (e.g. 3.0 to 6.0) and grows wider as distance grows, capped at max 70px.
        let baseStartWidth = max(2.5, min(8.0, strokeWidth * 0.75))
        let targetEndWidth = min(70.0, max(8.0, totalDist * 0.16 + strokeWidth))
        let headLength = min(max(16.0, targetEndWidth * 1.35), totalDist * 0.5)

        // Find cut-off parameter tHead where arrowhead begins
        // Approximate distance from end along curve
        let tHead = max(0.2, min(0.92, 1.0 - (headLength / totalDist)))
        let headBasePoint = pointOnCurve(t: tHead)
        let headTangent = tangentAt(t: 1.0)

        // Sample along curve from t = 0 to tHead to create tapered polygon outline
        let steps = 24
        var leftPoints: [CGPoint] = []
        var rightPoints: [CGPoint] = []

        for i in 0...steps {
            let t = (CGFloat(i) / CGFloat(steps)) * tHead
            let pt = pointOnCurve(t: t)
            let tangent = tangentAt(t: t)
            let perp = tangent + .pi / 2.0

            // Linearly interpolate width from start to tHead
            let currentHalfWidth = ((baseStartWidth + (targetEndWidth - baseStartWidth) * (t / tHead))) / 2.0

            let pLeft = CGPoint(
                x: pt.x + currentHalfWidth * cos(perp),
                y: pt.y + currentHalfWidth * sin(perp)
            )
            let pRight = CGPoint(
                x: pt.x - currentHalfWidth * cos(perp),
                y: pt.y - currentHalfWidth * sin(perp)
            )

            leftPoints.append(pLeft)
            rightPoints.append(pRight)
        }

        // Build continuous tapered shaft path
        let path = CGMutablePath()
        if let first = leftPoints.first {
            path.move(to: first)
            for p in leftPoints.dropFirst() {
                path.addLine(to: p)
            }
            for p in rightPoints.reversed() {
                path.addLine(to: p)
            }
            path.closeSubpath()
        }

        context.addPath(path)
        context.fillPath()

        // Draw rounded start cap
        let startCapRect = CGRect(
            x: start.x - baseStartWidth / 2.0,
            y: start.y - baseStartWidth / 2.0,
            width: baseStartWidth,
            height: baseStartWidth
        )
        context.fillEllipse(in: startCapRect)

        // Draw Arrowhead at 'end'
        let headAngle: CGFloat = .pi / 6.0 // 30 degrees
        let flareWidth = targetEndWidth * 1.5

        let leftWing = CGPoint(
            x: end.x - headLength * cos(headTangent - headAngle) - (flareWidth * 0.25 * cos(headTangent + .pi / 2.0)),
            y: end.y - headLength * sin(headTangent - headAngle) - (flareWidth * 0.25 * sin(headTangent + .pi / 2.0))
        )
        let rightWing = CGPoint(
            x: end.x - headLength * cos(headTangent + headAngle) + (flareWidth * 0.25 * cos(headTangent + .pi / 2.0)),
            y: end.y - headLength * sin(headTangent + headAngle) + (flareWidth * 0.25 * sin(headTangent + .pi / 2.0))
        )

        let headPath = CGMutablePath()
        headPath.move(to: end)
        headPath.addLine(to: leftWing)
        headPath.addLine(to: headBasePoint)
        headPath.addLine(to: rightWing)
        headPath.closeSubpath()

        context.addPath(headPath)
        context.fillPath()

        // If bidirectional, draw Arrowhead at 'start' pointing backwards
        if headType == .biDirectional {
            let startTangent = tangentAt(t: 0.0) + .pi
            drawHead(at: start, angle: startTangent, in: context)
        }

        context.restoreGState()
    }

    private func drawHead(at point: CGPoint, angle: CGFloat, in context: CGContext) {
        let headLength = max(14.0, strokeWidth * 3.2)
        let headAngle: CGFloat = .pi / 6.0

        let left = CGPoint(
            x: point.x - headLength * cos(angle - headAngle),
            y: point.y - headLength * sin(angle - headAngle)
        )
        let right = CGPoint(
            x: point.x - headLength * cos(angle + headAngle),
            y: point.y - headLength * sin(angle + headAngle)
        )

        context.beginPath()
        context.move(to: point)
        context.addLine(to: left)
        context.addLine(to: right)
        context.closePath()
        context.fillPath()
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
