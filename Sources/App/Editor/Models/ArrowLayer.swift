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
        context.setFillColor(strokeColor)
        context.setStrokeColor(strokeColor)

        let totalDist = hypot(end.x - start.x, end.y - start.y)
        guard totalDist > 4.0 else {
            context.restoreGState()
            return
        }

        // Tapered arrow geometry matching reference image:
        // Flat perpendicular start cap, natural widening towards arrowhead (capped at 70px)
        let baseStartWidth = max(5.0, min(32.0, strokeWidth * 4.2 + totalDist * 0.015))
        let targetEndWidth = max(10.0, min(70.0, baseStartWidth * 1.35 + totalDist * 0.02))

        let headLength = min(max(24.0, targetEndWidth * 2.45), totalDist * 0.65)
        let wingSpan = targetEndWidth * 2.95
        let wingHalfSpan = wingSpan / 2.0
        let recessDepth = headLength * 0.38
        let cornerRadius = min(7.0, max(4.0, targetEndWidth * 0.18))

        // Find tHead along curve
        let tHead = max(0.2, min(0.92, 1.0 - (headLength - recessDepth) / totalDist))
        let endTangent = tangentAt(t: 1.0)
        let forward = CGPoint(x: cos(endTangent), y: sin(endTangent))
        let backward = CGPoint(x: -forward.x, y: -forward.y)
        let perp = CGPoint(x: -sin(endTangent), y: cos(endTangent))

        // Sampling shaft
        let steps = 36
        var leftPoints: [CGPoint] = []
        var rightPoints: [CGPoint] = []

        for i in 0...steps {
            let t = (CGFloat(i) / CGFloat(steps)) * tHead
            let pt = pointOnCurve(t: t)
            let tang = tangentAt(t: t)
            let pPerp = CGPoint(x: -sin(tang), y: cos(tang))

            let currentHalfWidth = (baseStartWidth + (targetEndWidth - baseStartWidth) * (t / tHead)) / 2.0
            leftPoints.append(CGPoint(x: pt.x + currentHalfWidth * pPerp.x, y: pt.y + currentHalfWidth * pPerp.y))
            rightPoints.append(CGPoint(x: pt.x - currentHalfWidth * pPerp.x, y: pt.y - currentHalfWidth * pPerp.y))
        }

        // Arrowhead key points
        let wingBase = CGPoint(
            x: end.x + backward.x * headLength,
            y: end.y + backward.y * headLength
        )
        let leftWingApex = CGPoint(
            x: wingBase.x + perp.x * wingHalfSpan,
            y: wingBase.y + perp.y * wingHalfSpan
        )
        let rightWingApex = CGPoint(
            x: wingBase.x - perp.x * wingHalfSpan,
            y: wingBase.y - perp.y * wingHalfSpan
        )

        let notchBase = CGPoint(
            x: end.x + backward.x * (headLength - recessDepth),
            y: end.y + backward.y * (headLength - recessDepth)
        )
        let leftNotch = CGPoint(
            x: notchBase.x + perp.x * (targetEndWidth / 2.0),
            y: notchBase.y + perp.y * (targetEndWidth / 2.0)
        )
        let rightNotch = CGPoint(
            x: notchBase.x - perp.x * (targetEndWidth / 2.0),
            y: notchBase.y - perp.y * (targetEndWidth / 2.0)
        )

        // Build unified continuous arrow path
        let path = CGMutablePath()

        // 1. Tip
        path.move(to: end)

        // 2. Leading edge to left wing with rounded corner
        path.addArc(tangent1End: leftWingApex, tangent2End: leftNotch, radius: cornerRadius)

        // 3. Notch to shaft left side
        path.addLine(to: leftNotch)

        // 4. Trace down left side of shaft to tail
        for pt in leftPoints.reversed() {
            path.addLine(to: pt)
        }

        // 5. Flat perpendicular tail cap
        if let firstRight = rightPoints.first {
            path.addLine(to: firstRight)
        }

        // 6. Trace up right side of shaft to right notch
        for pt in rightPoints.dropFirst() {
            path.addLine(to: pt)
        }

        // 7. Right notch to right wing with rounded corner
        path.addLine(to: rightNotch)
        path.addArc(tangent1End: rightWingApex, tangent2End: end, radius: cornerRadius)

        // 8. Close back to tip
        path.closeSubpath()

        context.addPath(path)
        context.fillPath()

        // If bidirectional, draw Arrowhead at 'start' pointing backwards
        if headType == .biDirectional {
            let startTangent = tangentAt(t: 0.0) + .pi
            drawHead(at: start, angle: startTangent, width: baseStartWidth, in: context)
        }

        context.restoreGState()
    }

    private func drawHead(at point: CGPoint, angle: CGFloat, width: CGFloat, in context: CGContext) {
        let headLength = width * 2.45
        let wingSpan = width * 2.95
        let wingHalfSpan = wingSpan / 2.0
        let recessDepth = headLength * 0.38
        let cornerRadius = min(7.0, max(4.0, width * 0.18))

        let forward = CGPoint(x: cos(angle), y: sin(angle))
        let backward = CGPoint(x: -forward.x, y: -forward.y)
        let perp = CGPoint(x: -sin(angle), y: cos(angle))

        let wingBase = CGPoint(x: point.x + backward.x * headLength, y: point.y + backward.y * headLength)
        let leftWingApex = CGPoint(x: wingBase.x + perp.x * wingHalfSpan, y: wingBase.y + perp.y * wingHalfSpan)
        let rightWingApex = CGPoint(x: wingBase.x - perp.x * wingHalfSpan, y: wingBase.y - perp.y * wingHalfSpan)
        let notchBase = CGPoint(x: point.x + backward.x * (headLength - recessDepth), y: point.y + backward.y * (headLength - recessDepth))

        let path = CGMutablePath()
        path.move(to: point)
        path.addArc(tangent1End: leftWingApex, tangent2End: notchBase, radius: cornerRadius)
        path.addLine(to: notchBase)
        path.addArc(tangent1End: rightWingApex, tangent2End: point, radius: cornerRadius)
        path.closeSubpath()

        context.addPath(path)
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
