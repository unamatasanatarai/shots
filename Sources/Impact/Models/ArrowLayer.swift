import Foundation
import CoreGraphics
import AppKit

public final class ArrowLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .arrow
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String {
        didSet { _cachedStrokeColor = nil }
    }
    public var strokeWidth: CGFloat {
        didSet { invalidateCache() }
    }

    public var start: CGPoint {
        didSet { invalidateCache() }
    }
    public var control: CGPoint { // Midpoint quadratic Bezier control point
        didSet { invalidateCache() }
    }
    public var end: CGPoint {
        didSet { invalidateCache() }
    }
    public var headType: ArrowHeadType {
        didSet { invalidateCache() }
    }

    public var relativeControl: (u: CGFloat, v: CGFloat) = (u: 0.5, v: 0.0)

    // MARK: - Fast Performance Caches
    private var _cachedBoundingBox: CGRect?
    private var _cachedPath: CGPath?
    private var _cachedStrokeColor: CGColor?

    @inline(__always)
    private func invalidateCache() {
        _cachedBoundingBox = nil
        _cachedPath = nil
    }

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
        let initialControl = control ?? CGPoint(x: (start.x + end.x) / 2.0, y: (start.y + end.y) / 2.0)
        self.control = initialControl
        self.color = color
        self.strokeWidth = strokeWidth
        self.headType = headType
        self.zIndex = zIndex
        self.updateRelativeControl()
    }

    public func updateRelativeControl() {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lenSq = dx * dx + dy * dy
        if lenSq > 0.001 {
            let u = ((control.x - start.x) * dx + (control.y - start.y) * dy) / lenSq
            let v = ((control.y - start.y) * dx - (control.x - start.x) * dy) / lenSq
            relativeControl = (u: u, v: v)
        } else {
            relativeControl = (u: 0.5, v: 0.0)
        }
    }

    // MARK: - Bounds Calculation

    public func getBoundingBox() -> CGRect {
        if let cached = _cachedBoundingBox { return cached }

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
        let box = CGRect(
            x: minX - padding,
            y: minY - padding,
            width: maxX - minX + padding * 2,
            height: maxY - minY + padding * 2
        )
        _cachedBoundingBox = box
        return box
    }

    public func contains(point: CGPoint) -> Bool {
        // Fast early rejection via cached bounding box
        guard getBoundingBox().contains(point) else { return false }

        // Distance check along sampled Bezier curve using squared distances (no sqrt/hypot)
        let steps = 30
        let threshold = max(strokeWidth * 1.5, 10.0)
        let thresholdSq = threshold * threshold

        var prev = start
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let curr = pointOnCurve(t: t)
            if distanceToSegmentSq(p: point, a: prev, b: curr) <= thresholdSq {
                return true
            }
            prev = curr
        }
        return false
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        let rSq = radius * radius
        let dx0 = point.x - start.x
        let dy0 = point.y - start.y
        if dx0 * dx0 + dy0 * dy0 <= rSq { return 0 }

        let dx1 = point.x - control.x
        let dy1 = point.y - control.y
        if dx1 * dx1 + dy1 * dy1 <= rSq { return 1 }

        let dx2 = point.x - end.x
        let dy2 = point.y - end.y
        if dx2 * dx2 + dy2 * dy2 <= rSq { return 2 }

        return nil
    }

    public func move(by delta: CGPoint) {
        start = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
        control = CGPoint(x: control.x + delta.x, y: control.y + delta.y)
        end = CGPoint(x: end.x + delta.x, y: end.y + delta.y)
        invalidateCache()
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        switch index {
        case 0:
            start = point
            let dx = end.x - start.x
            let dy = end.y - start.y
            control = CGPoint(
                x: start.x + relativeControl.u * dx - relativeControl.v * dy,
                y: start.y + relativeControl.u * dy + relativeControl.v * dx
            )
        case 1:
            control = point
            updateRelativeControl()
        case 2:
            end = point
            let dx = end.x - start.x
            let dy = end.y - start.y
            control = CGPoint(
                x: start.x + relativeControl.u * dx - relativeControl.v * dy,
                y: start.y + relativeControl.u * dy + relativeControl.v * dx
            )
        default:
            break
        }
        invalidateCache()
    }

    // MARK: - Drawing

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let strokeColor = _cachedStrokeColor ?? {
            let c = FastColor.shared.cgColor(hex: color)
            _cachedStrokeColor = c
            return c
        }()

        context.setStrokeColor(strokeColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Subtle natural shadow for depth and crispness
        context.setShadow(offset: CGSize(width: 0, height: -1.0), blur: 2.5, color: NSColor.black.withAlphaComponent(0.25).cgColor)

        let dx = end.x - start.x
        let dy = end.y - start.y
        let totalDistSq = dx * dx + dy * dy
        guard totalDistSq > 16.0 else { // > 4.0 px distance
            context.restoreGState()
            return
        }
        let totalDist = sqrt(totalDistSq)

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
        if let cached = _cachedPath { return cached }

        let dx = end.x - start.x
        let dy = end.y - start.y
        let totalDistSq = dx * dx + dy * dy
        guard totalDistSq > 16.0 else {
            let empty = CGMutablePath()
            _cachedPath = empty
            return empty
        }
        let totalDist = sqrt(totalDistSq)

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

        _cachedPath = path
        return path
    }

    // MARK: - Math Helpers

    private func pointOnCurve(t: CGFloat) -> CGPoint {
        let u = 1.0 - t
        let u2 = u * u
        let ut2 = 2.0 * u * t
        let t2 = t * t
        let x = u2 * start.x + ut2 * control.x + t2 * end.x
        let y = u2 * start.y + ut2 * control.y + t2 * end.y
        return CGPoint(x: x, y: y)
    }

    private func tangentAt(t: CGFloat) -> CGFloat {
        // Derivative: B'(t) = 2(1-t)(control - start) + 2t(end - control)
        let u = 1.0 - t
        let dx = 2 * u * (control.x - start.x) + 2 * t * (end.x - control.x)
        let dy = 2 * u * (control.y - start.y) + 2 * t * (end.y - control.y)
        return atan2(dy, dx)
    }

    @inline(__always)
    private func distanceToSegmentSq(p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq < 0.001 {
            let px = p.x - a.x
            let py = p.y - a.y
            return px * px + py * py
        }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        let dpx = p.x - projX
        let dpy = p.y - projY
        return dpx * dpx + dpy * dpy
    }

    public func clone() -> AnnotationLayer {
        let cloned = ArrowLayer(
            id: UUID(),
            start: start,
            control: control,
            end: end,
            color: color,
            strokeWidth: strokeWidth,
            headType: headType,
            zIndex: zIndex
        )
        cloned.relativeControl = relativeControl
        return cloned
    }
}
