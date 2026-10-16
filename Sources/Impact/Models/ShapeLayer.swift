import Foundation
import CoreGraphics
import AppKit

public enum ShapeFillStyle: String, Codable {
    case outline
    case solid
    case striped
}

public enum LineStyle: String, Codable {
    case solid
    case dashed
    case dotted
}

// MARK: - Rectangle Layer

public final class RectangleLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .rectangle
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String
    public var strokeWidth: CGFloat {
        didSet { _cachedBoundingBox = nil }
    }

    public var rect: CGRect {
        didSet { _cachedBoundingBox = nil }
    }
    public var cornerRadius: CGFloat {
        didSet { _cachedBoundingBox = nil }
    }
    public var fillStyle: ShapeFillStyle

    private var _cachedBoundingBox: CGRect?

    public init(
        id: UUID = UUID(),
        rect: CGRect,
        cornerRadius: CGFloat = 6.0,
        color: String = "#FF3B30",
        strokeWidth: CGFloat = 4.0,
        fillStyle: ShapeFillStyle = .outline,
        zIndex: Int = 0
    ) {
        self.id = id
        self.rect = rect
        self.cornerRadius = cornerRadius
        self.color = color
        self.strokeWidth = strokeWidth
        self.fillStyle = fillStyle
        self.zIndex = zIndex
    }

    public func getBoundingBox() -> CGRect {
        if let cached = _cachedBoundingBox { return cached }
        let padding = strokeWidth / 2.0 + 8.0
        let box = rect.insetBy(dx: -padding, dy: -padding)
        _cachedBoundingBox = box
        return box
    }

    public func contains(point: CGPoint) -> Bool {
        guard getBoundingBox().contains(point) else { return false }
        if fillStyle == .solid || fillStyle == .striped {
            return rect.standardized.contains(point)
        }
        let catchment: CGFloat = max(10.0, strokeWidth + 6.0)
        let outer = rect.standardized.insetBy(dx: -catchment, dy: -catchment)
        let inner = rect.standardized.insetBy(dx: catchment, dy: catchment)
        if inner.width <= 0 || inner.height <= 0 {
            return outer.contains(point)
        }
        return outer.contains(point) && !inner.contains(point)
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        guard getBoundingBox().insetBy(dx: -12, dy: -12).contains(point) else { return nil }
        let handles = getHandlePoints()
        let hitRadius = max(radius, 10.0)
        let hitRadiusSq = hitRadius * hitRadius

        // Resize only by grabbing the white dots (circular handle points)
        for (i, hp) in handles.enumerated() {
            let dx = point.x - hp.x
            let dy = point.y - hp.y
            if dx * dx + dy * dy <= hitRadiusSq {
                return i
            }
        }
        return nil
    }

    public func getHandlePoints() -> [CGPoint] {
        let minX = rect.minX, midX = rect.midX, maxX = rect.maxX
        let minY = rect.minY, midY = rect.midY, maxY = rect.maxY
        return [
            CGPoint(x: minX, y: minY), // 0: Top-Left (or BL in flipped)
            CGPoint(x: midX, y: minY), // 1: Top-Center
            CGPoint(x: maxX, y: minY), // 2: Top-Right
            CGPoint(x: maxX, y: midY), // 3: Mid-Right
            CGPoint(x: maxX, y: maxY), // 4: Bottom-Right
            CGPoint(x: midX, y: maxY), // 5: Bottom-Center
            CGPoint(x: minX, y: maxY), // 6: Bottom-Left
            CGPoint(x: minX, y: midY)  // 7: Mid-Left
        ]
    }

    public func move(by delta: CGPoint) {
        rect.origin.x += delta.x
        rect.origin.y += delta.y
        _cachedBoundingBox = nil
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch index {
        case 0: minX = point.x; minY = point.y
        case 1: minY = point.y
        case 2: maxX = point.x; minY = point.y
        case 3: maxX = point.x
        case 4: maxX = point.x; maxY = point.y
        case 5: maxY = point.y
        case 6: minX = point.x; maxY = point.y
        case 7: minX = point.x
        default: break
        }

        rect = CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: max(abs(maxX - minX), 4.0),
            height: max(abs(maxY - minY), 4.0)
        )
        _cachedBoundingBox = nil
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let strokeCGColor = FastColor.shared.cgColor(hex: color)

        let effectiveRadius = max(0.0, min(cornerRadius, min(rect.width / 2.0, rect.height / 2.0)))
        let path = CGPath(roundedRect: rect, cornerWidth: effectiveRadius, cornerHeight: effectiveRadius, transform: nil)
        context.addPath(path)

        switch fillStyle {
        case .outline:
            context.setStrokeColor(strokeCGColor)
            context.setLineWidth(strokeWidth)
            context.strokePath()

        case .solid:
            context.setFillColor(FastColor.shared.cgColor(hex: color, alpha: 0.25))
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(strokeCGColor)
            context.setLineWidth(strokeWidth)
            context.strokePath()

        case .striped:
            context.saveGState()
            context.addPath(path)
            context.clip()

            // Draw diagonal stripes
            context.setStrokeColor(FastColor.shared.cgColor(hex: color, alpha: 0.35))
            context.setLineWidth(max(2.0, strokeWidth * 0.75))
            let spacing: CGFloat = 12.0
            let start = rect.minX - rect.height
            let end = rect.maxX + rect.height
            var x = start
            while x < end {
                context.move(to: CGPoint(x: x, y: rect.minY))
                context.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
                x += spacing
            }
            context.strokePath()
            context.restoreGState()

            // Outer border
            context.addPath(path)
            context.setStrokeColor(strokeCGColor)
            context.setLineWidth(strokeWidth)
            context.strokePath()
        }

        context.restoreGState()
    }

    public func clone() -> AnnotationLayer {
        RectangleLayer(
            id: UUID(),
            rect: rect,
            cornerRadius: cornerRadius,
            color: color,
            strokeWidth: strokeWidth,
            fillStyle: fillStyle,
            zIndex: zIndex
        )
    }
}

// MARK: - Ellipse Layer

public final class EllipseLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .ellipse
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String
    public var strokeWidth: CGFloat {
        didSet { _cachedBoundingBox = nil }
    }

    public var rect: CGRect {
        didSet { _cachedBoundingBox = nil }
    }
    public var isPerfectCircle: Bool
    public var fillStyle: ShapeFillStyle

    private var _cachedBoundingBox: CGRect?

    public init(
        id: UUID = UUID(),
        rect: CGRect,
        isPerfectCircle: Bool = false,
        color: String = "#FF3B30",
        strokeWidth: CGFloat = 4.0,
        fillStyle: ShapeFillStyle = .outline,
        zIndex: Int = 0
    ) {
        self.id = id
        self.rect = rect
        self.isPerfectCircle = isPerfectCircle
        self.color = color
        self.strokeWidth = strokeWidth
        self.fillStyle = fillStyle
        self.zIndex = zIndex
    }

    public func getBoundingBox() -> CGRect {
        if let cached = _cachedBoundingBox { return cached }
        let padding = strokeWidth / 2.0 + 8.0
        let box = rect.insetBy(dx: -padding, dy: -padding)
        _cachedBoundingBox = box
        return box
    }

    public func contains(point: CGPoint) -> Bool {
        guard getBoundingBox().contains(point) else { return false }
        let stdRect = rect.standardized
        guard stdRect.width > 0 && stdRect.height > 0 else { return false }
        let cx = stdRect.midX
        let cy = stdRect.midY
        let dx = point.x - cx
        let dy = point.y - cy

        if fillStyle == .solid || fillStyle == .striped {
            let rx = stdRect.width / 2.0
            let ry = stdRect.height / 2.0
            let nx = dx / rx
            let ny = dy / ry
            return (nx * nx + ny * ny) <= 1.0
        }

        // Outline oval: drag only from edge plus margin (catchment), never from the middle
        let catchment: CGFloat = max(10.0, strokeWidth + 6.0)
        let rxOuter = stdRect.width / 2.0 + catchment
        let ryOuter = stdRect.height / 2.0 + catchment
        let rxInner = stdRect.width / 2.0 - catchment
        let ryInner = stdRect.height / 2.0 - catchment

        let nxOuter = dx / rxOuter
        let nyOuter = dy / ryOuter
        let valOuter = nxOuter * nxOuter + nyOuter * nyOuter
        if rxInner <= 0 || ryInner <= 0 {
            return valOuter <= 1.0
        }
        let nxInner = dx / rxInner
        let nyInner = dy / ryInner
        let valInner = nxInner * nxInner + nyInner * nyInner
        return valOuter <= 1.0 && valInner > 1.0
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        guard getBoundingBox().insetBy(dx: -12, dy: -12).contains(point) else { return nil }
        let handles = getHandlePoints()
        let hitRadius = max(radius, 10.0)
        let hitRadiusSq = hitRadius * hitRadius
        for (i, hp) in handles.enumerated() {
            let dx = point.x - hp.x
            let dy = point.y - hp.y
            if dx * dx + dy * dy <= hitRadiusSq {
                return i
            }
        }
        return nil
    }

    public func getHandlePoints() -> [CGPoint] {
        let minX = rect.minX, midX = rect.midX, maxX = rect.maxX
        let minY = rect.minY, midY = rect.midY, maxY = rect.maxY
        return [
            CGPoint(x: midX, y: minY), // 0: Top-Center (vertical resize)
            CGPoint(x: maxX, y: midY), // 1: Right-Center (horizontal resize)
            CGPoint(x: midX, y: maxY), // 2: Bottom-Center (vertical resize)
            CGPoint(x: minX, y: midY)  // 3: Left-Center (horizontal resize)
        ]
    }

    public func move(by delta: CGPoint) {
        rect.origin.x += delta.x
        rect.origin.y += delta.y
        _cachedBoundingBox = nil
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch index {
        case 0: // 0: Top-Center: vertical
            minY = point.y
            if isPerfectCircle {
                let h = abs(maxY - minY)
                let cx = (minX + maxX) / 2.0
                minX = cx - h / 2.0
                maxX = cx + h / 2.0
            }
        case 1: // 1: Right-Center: horizontal
            maxX = point.x
            if isPerfectCircle {
                let w = abs(maxX - minX)
                let cy = (minY + maxY) / 2.0
                minY = cy - w / 2.0
                maxY = cy + w / 2.0
            }
        case 2: // 2: Bottom-Center: vertical
            maxY = point.y
            if isPerfectCircle {
                let h = abs(maxY - minY)
                let cx = (minX + maxX) / 2.0
                minX = cx - h / 2.0
                maxX = cx + h / 2.0
            }
        case 3: // 3: Left-Center: horizontal
            minX = point.x
            if isPerfectCircle {
                let w = abs(maxX - minX)
                let cy = (minY + maxY) / 2.0
                minY = cy - w / 2.0
                maxY = cy + w / 2.0
            }
        default:
            break
        }

        rect = CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: max(abs(maxX - minX), 4.0),
            height: max(abs(maxY - minY), 4.0)
        )
        _cachedBoundingBox = nil
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let strokeCGColor = FastColor.shared.cgColor(hex: color)

        let path = CGPath(ellipseIn: rect, transform: nil)
        context.addPath(path)

        if fillStyle == .solid {
            context.setFillColor(FastColor.shared.cgColor(hex: color, alpha: 0.25))
            context.fillPath()
            context.addPath(path)
        }

        context.setStrokeColor(strokeCGColor)
        context.setLineWidth(strokeWidth)
        context.strokePath()

        context.restoreGState()
    }

    public func clone() -> AnnotationLayer {
        EllipseLayer(
            id: UUID(),
            rect: rect,
            isPerfectCircle: isPerfectCircle,
            color: color,
            strokeWidth: strokeWidth,
            fillStyle: fillStyle,
            zIndex: zIndex
        )
    }
}

// MARK: - Line Layer

public final class LineLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .line
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
    public var lineStyle: LineStyle

    private var _cachedBoundingBox: CGRect?

    public init(
        id: UUID = UUID(),
        start: CGPoint,
        end: CGPoint,
        color: String = "#FF3B30",
        strokeWidth: CGFloat = 4.0,
        lineStyle: LineStyle = .solid,
        zIndex: Int = 0
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.color = color
        self.strokeWidth = strokeWidth
        self.lineStyle = lineStyle
        self.zIndex = zIndex
    }

    public func getBoundingBox() -> CGRect {
        if let cached = _cachedBoundingBox { return cached }
        let padding = strokeWidth / 2.0 + 8.0
        let minX = min(start.x, end.x) - padding
        let minY = min(start.y, end.y) - padding
        let maxX = max(start.x, end.x) + padding
        let maxY = max(start.y, end.y) + padding
        let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        _cachedBoundingBox = box
        return box
    }

    public func contains(point: CGPoint) -> Bool {
        guard getBoundingBox().contains(point) else { return false }
        let threshold = max(strokeWidth * 1.5, 10.0)
        let thresholdSq = threshold * threshold
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lenSq = dx * dx + dy * dy
        if lenSq < 0.001 {
            let px = point.x - start.x
            let py = point.y - start.y
            return px * px + py * py <= thresholdSq
        }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lenSq))
        let projX = start.x + t * dx
        let projY = start.y + t * dy
        let px = point.x - projX
        let py = point.y - projY
        return px * px + py * py <= thresholdSq
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        let hitRadius = max(radius, 10.0)
        let hitRadiusSq = hitRadius * hitRadius
        let dx0 = point.x - start.x
        let dy0 = point.y - start.y
        if dx0 * dx0 + dy0 * dy0 <= hitRadiusSq { return 0 }

        let dx1 = point.x - end.x
        let dy1 = point.y - end.y
        if dx1 * dx1 + dy1 * dy1 <= hitRadiusSq { return 1 }
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

        let strokeColor = FastColor.shared.cgColor(hex: color)
        context.setStrokeColor(strokeColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)

        switch lineStyle {
        case .solid:
            context.setLineDash(phase: 0, lengths: [])
        case .dashed:
            context.setLineDash(phase: 0, lengths: [strokeWidth * 3, strokeWidth * 2])
        case .dotted:
            context.setLineDash(phase: 0, lengths: [1, strokeWidth * 2])
            context.setLineCap(.round)
        }

        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        context.restoreGState()
    }

    public func clone() -> AnnotationLayer {
        LineLayer(
            id: UUID(),
            start: start,
            end: end,
            color: color,
            strokeWidth: strokeWidth,
            lineStyle: lineStyle,
            zIndex: zIndex
        )
    }
}
