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

        let path = pathForArrow()
        let bounds = path.boundingBoxOfPath

        let padding = max(strokeWidth * 2.0 + 8.0, 16.0)
        let box: CGRect
        if bounds.isNull || bounds.isEmpty || bounds.isInfinite {
            let minX = min(start.x, end.x, control.x)
            let minY = min(start.y, end.y, control.y)
            let maxX = max(start.x, end.x, control.x)
            let maxY = max(start.y, end.y, control.y)
            box = CGRect(
                x: minX - padding,
                y: minY - padding,
                width: max(padding * 2, maxX - minX + padding * 2),
                height: max(padding * 2, maxY - minY + padding * 2)
            )
        } else {
            var b = bounds.insetBy(dx: -padding, dy: -padding)
            b = b.union(CGRect(x: start.x - padding, y: start.y - padding, width: padding * 2, height: padding * 2))
            b = b.union(CGRect(x: end.x - padding, y: end.y - padding, width: padding * 2, height: padding * 2))
            b = b.union(CGRect(x: control.x - padding, y: control.y - padding, width: padding * 2, height: padding * 2))
            box = b
        }
        _cachedBoundingBox = box
        return box
    }

    public func contains(point: CGPoint) -> Bool {
        guard getBoundingBox().contains(point) else { return false }
        let path = pathForArrow()
        if path.contains(point) { return true }
        let tolerance = max(strokeWidth, 8.0)
        let stroked = path.copy(strokingWithWidth: tolerance * 2.0, lineCap: .round, lineJoin: .round, miterLimit: 10.0)
        return stroked.contains(point)
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
        let dx = end.x - start.x
        let dy = end.y - start.y
        let totalDistSq = dx * dx + dy * dy
        guard totalDistSq > 16.0 else { return }

        let path = pathForArrow()
        guard !path.isEmpty else { return }

        context.saveGState()

        let strokeColor = _cachedStrokeColor ?? {
            let c = FastColor.shared.cgColor(hex: color)
            _cachedStrokeColor = c
            return c
        }()

        context.setFillColor(strokeColor)
        context.setStrokeColor(strokeColor)
        context.setLineWidth(1.8)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        // Subtle natural shadow for depth and crispness
        context.setShadow(offset: CGSize(width: 0, height: -1.0), blur: 2.5, color: NSColor.black.withAlphaComponent(0.25).cgColor)

        context.addPath(path)
        context.drawPath(using: .fillStroke)

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

        // 1. Calculate approximate arc length along quadratic Bezier curve
        let sampleSteps = 32
        var arcLength: CGFloat = 0.0
        var prevPt = start
        for i in 1...sampleSteps {
            let t = CGFloat(i) / CGFloat(sampleSteps)
            let pt = pointOnCurve(t: t)
            arcLength += hypot(pt.x - prevPt.x, pt.y - prevPt.y)
            prevPt = pt
        }

        guard arcLength > 4.0 else {
            let empty = CGMutablePath()
            _cachedPath = empty
            return empty
        }

        let scale = max(0.5, strokeWidth / 4.0)
        let maxHeadLength: CGFloat = 43.0 * scale

        // Head length smoothly scales with arrow length up to maxHeadLength
        let targetHeadLength = min(
            maxHeadLength,
            max(8.0 * scale, maxHeadLength * (1.0 - exp(-pow(arcLength / (90.0 * scale), 0.7))))
        )
        let isBiDirectional = (headType == .biDirectional)
        let maxHeadRatio: CGFloat = isBiDirectional ? 0.35 : 0.38
        let headLength = min(arcLength * maxHeadRatio, targetHeadLength)
        // Equilateral triangle arrowhead (apex angle ≈ 60 degrees, base ≈ 1.16 * L)
        let headWidth = headLength * 1.16

        // Shaft end width at arrowhead base
        let shaftEndWidth = max(3.0 * scale, headLength * 0.38)
        // Shaft start width at tail (gentle taper for short arrows, reaching ~53% on long arrows)
        let taperFactor = min(0.85, max(0.53, 0.85 - 0.32 * min(1.0, arcLength / 350.0)))
        let shaftStartWidth = isBiDirectional ? shaftEndWidth : max(2.5 * scale, shaftEndWidth * taperFactor)

        // Tangent and normal at end (t = 1.0)
        let endTanAngle = tangentAt(t: 1.0)
        let txEnd = cos(endTanAngle)
        let tyEnd = sin(endTanAngle)
        let nxEnd = -tyEnd
        let nyEnd = txEnd

        // Arrowhead base center at end:
        let headBaseCenter = CGPoint(
            x: end.x - txEnd * headLength,
            y: end.y - tyEnd * headLength
        )

        let halfHeadW = headWidth / 2.0
        let leftBarb = CGPoint(x: headBaseCenter.x + nxEnd * halfHeadW, y: headBaseCenter.y + nyEnd * halfHeadW)
        let rightBarb = CGPoint(x: headBaseCenter.x - nxEnd * halfHeadW, y: headBaseCenter.y - nyEnd * halfHeadW)

        let halfEndW = shaftEndWidth / 2.0
        let shaftRightEnd = CGPoint(x: headBaseCenter.x - nxEnd * halfEndW, y: headBaseCenter.y - nyEnd * halfEndW)
        let shaftLeftEnd = CGPoint(x: headBaseCenter.x + nxEnd * halfEndW, y: headBaseCenter.y + nyEnd * halfEndW)

        // Tangent and normal at start (t = 0.0)
        let startTanAngle = tangentAt(t: 0.0)
        let txStart = cos(startTanAngle)
        let tyStart = sin(startTanAngle)
        let nxStart = -tyStart
        let nyStart = txStart

        let path = CGMutablePath()

        if isBiDirectional {
            // Bidirectional: Arrowhead at start and arrowhead at end
            let startHeadBaseCenter = CGPoint(
                x: start.x + txStart * headLength,
                y: start.y + tyStart * headLength
            )
            let startLeftBarb = CGPoint(x: startHeadBaseCenter.x + nxStart * halfHeadW, y: startHeadBaseCenter.y + nyStart * halfHeadW)
            let startRightBarb = CGPoint(x: startHeadBaseCenter.x - nxStart * halfHeadW, y: startHeadBaseCenter.y - nyStart * halfHeadW)
            let shaftLeftStart = CGPoint(x: startHeadBaseCenter.x + nxStart * halfEndW, y: startHeadBaseCenter.y + nyStart * halfEndW)
            let shaftRightStart = CGPoint(x: startHeadBaseCenter.x - nxStart * halfEndW, y: startHeadBaseCenter.y - nyStart * halfEndW)

            let tHeadStart = min(0.40, headLength / arcLength)
            let tHeadEnd = max(tHeadStart + 0.05, 1.0 - (headLength / arcLength))

            let shaftSteps = 24
            var rightShaftPts: [CGPoint] = [shaftRightStart]
            var leftShaftPts: [CGPoint] = [shaftLeftStart]
            rightShaftPts.reserveCapacity(shaftSteps + 1)
            leftShaftPts.reserveCapacity(shaftSteps + 1)

            for i in 1..<shaftSteps {
                let frac = CGFloat(i) / CGFloat(shaftSteps)
                let t = tHeadStart + (tHeadEnd - tHeadStart) * frac
                let pt = pointOnCurve(t: t)
                let tan = tangentAt(t: t)
                let nx = -sin(tan)
                let ny = cos(tan)

                let u = abs(frac - 0.5) * 2.0
                let w = shaftStartWidth * 0.7 + (shaftEndWidth - shaftStartWidth * 0.7) * u
                let h = w / 2.0
                rightShaftPts.append(CGPoint(x: pt.x - nx * h, y: pt.y - ny * h))
                leftShaftPts.append(CGPoint(x: pt.x + nx * h, y: pt.y + ny * h))
            }
            rightShaftPts.append(shaftRightEnd)
            leftShaftPts.append(shaftLeftEnd)

            path.move(to: rightBarb)
            path.addLine(to: end)
            path.addLine(to: leftBarb)
            path.addLine(to: shaftLeftEnd)
            for pt in leftShaftPts.dropLast().reversed() {
                path.addLine(to: pt)
            }
            path.addLine(to: shaftLeftStart)
            path.addLine(to: startLeftBarb)
            path.addLine(to: start)
            path.addLine(to: startRightBarb)
            path.addLine(to: shaftRightStart)
            for pt in rightShaftPts.dropFirst() {
                path.addLine(to: pt)
            }
            path.addLine(to: shaftRightEnd)
            path.closeSubpath()
        } else {
            // Standard/Filled: Flat tail at start, arrowhead at end
            let halfStartW = shaftStartWidth / 2.0
            let shaftRightStart = CGPoint(x: start.x - nxStart * halfStartW, y: start.y - nyStart * halfStartW)
            let shaftLeftStart = CGPoint(x: start.x + nxStart * halfStartW, y: start.y + nyStart * halfStartW)

            let tEnd = max(0.05, 1.0 - (headLength / arcLength))
            let shaftSteps = 24
            var rightShaftPts: [CGPoint] = [shaftRightStart]
            var leftShaftPts: [CGPoint] = [shaftLeftStart]
            rightShaftPts.reserveCapacity(shaftSteps + 1)
            leftShaftPts.reserveCapacity(shaftSteps + 1)

            for i in 1..<shaftSteps {
                let frac = CGFloat(i) / CGFloat(shaftSteps)
                let t = frac * tEnd
                let pt = pointOnCurve(t: t)
                let tan = tangentAt(t: t)
                let nx = -sin(tan)
                let ny = cos(tan)

                let w = shaftStartWidth + (shaftEndWidth - shaftStartWidth) * frac
                let h = w / 2.0
                rightShaftPts.append(CGPoint(x: pt.x - nx * h, y: pt.y - ny * h))
                leftShaftPts.append(CGPoint(x: pt.x + nx * h, y: pt.y + ny * h))
            }
            rightShaftPts.append(shaftRightEnd)
            leftShaftPts.append(shaftLeftEnd)

            path.move(to: shaftRightStart)
            for pt in rightShaftPts.dropFirst() {
                path.addLine(to: pt)
            }
            path.addLine(to: rightBarb)
            path.addLine(to: end)
            path.addLine(to: leftBarb)
            path.addLine(to: shaftLeftEnd)
            for pt in leftShaftPts.dropLast().reversed() {
                path.addLine(to: pt)
            }
            // Flat butt cap at tail connects shaftLeftStart back to shaftRightStart
            path.closeSubpath()
        }

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
        if dx * dx + dy * dy < 0.000001 {
            return atan2(end.y - start.y, end.x - start.x)
        }
        return atan2(dy, dx)
    }

    public func clone() -> AnnotationLayer {
        let cloned = ArrowLayer(
            id: id,
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
