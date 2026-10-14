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
    public var strokeWidth: CGFloat

    public var rect: CGRect
    public var cornerRadius: CGFloat
    public var fillStyle: ShapeFillStyle

    public init(
        id: UUID = UUID(),
        rect: CGRect,
        cornerRadius: CGFloat = 10.0,
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
        let padding = strokeWidth / 2.0 + 8.0
        return rect.insetBy(dx: -padding, dy: -padding)
    }

    public func contains(point: CGPoint) -> Bool {
        if fillStyle == .solid || fillStyle == .striped {
            return rect.contains(point)
        }
        let outer = rect.insetBy(dx: -strokeWidth - 6, dy: -strokeWidth - 6)
        let inner = rect.insetBy(dx: strokeWidth + 6, dy: strokeWidth + 6)
        return outer.contains(point) && !inner.contains(point)
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        let handles = getHandlePoints()
        let hitRadius = max(radius, 10.0)

        // 1. Check direct circular handle points
        for (i, hp) in handles.enumerated() {
            if hypot(point.x - hp.x, point.y - hp.y) <= hitRadius {
                return i
            }
        }

        // 2. Boundary edge hit testing for freeform edge dragging
        let tolerance: CGFloat = max(radius, 6.0)
        let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
        let inner = rect.insetBy(dx: tolerance, dy: tolerance)
        if outer.contains(point) && !inner.contains(point) {
            let cornerDist = max(cornerRadius + 4.0, 16.0)
            let isNearLeft = abs(point.x - rect.minX) <= tolerance
            let isNearRight = abs(point.x - rect.maxX) <= tolerance
            let isNearTop = abs(point.y - rect.minY) <= tolerance
            let isNearBottom = abs(point.y - rect.maxY) <= tolerance

            if isNearLeft && isNearTop { return 0 }
            if isNearRight && isNearTop { return 2 }
            if isNearRight && isNearBottom { return 4 }
            if isNearLeft && isNearBottom { return 6 }

            if isNearTop && point.x >= rect.minX + cornerDist && point.x <= rect.maxX - cornerDist {
                return 1 // Top edge -> strictly vertical
            }
            if isNearBottom && point.x >= rect.minX + cornerDist && point.x <= rect.maxX - cornerDist {
                return 5 // Bottom edge -> strictly vertical
            }
            if isNearLeft && point.y >= rect.minY + cornerDist && point.y <= rect.maxY - cornerDist {
                return 7 // Left edge -> strictly horizontal
            }
            if isNearRight && point.y >= rect.minY + cornerDist && point.y <= rect.maxY - cornerDist {
                return 3 // Right edge -> strictly horizontal
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
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let strokeNSColor = NSColor(hex: color)
        let strokeCGColor = strokeNSColor.cgColor

        let effectiveRadius = max(0.0, min(cornerRadius, min(rect.width / 2.0, rect.height / 2.0)))
        let path = CGPath(roundedRect: rect, cornerWidth: effectiveRadius, cornerHeight: effectiveRadius, transform: nil)
        context.addPath(path)

        switch fillStyle {
        case .outline:
            context.setStrokeColor(strokeCGColor)
            context.setLineWidth(strokeWidth)
            context.strokePath()

        case .solid:
            context.setFillColor(strokeNSColor.withAlphaComponent(0.25).cgColor)
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
            context.setStrokeColor(strokeNSColor.withAlphaComponent(0.35).cgColor)
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
    public var strokeWidth: CGFloat

    public var rect: CGRect
    public var isPerfectCircle: Bool
    public var fillStyle: ShapeFillStyle

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
        let padding = strokeWidth / 2.0 + 8.0
        return rect.insetBy(dx: -padding, dy: -padding)
    }

    public func contains(point: CGPoint) -> Bool {
        let rx = rect.width / 2.0
        let ry = rect.height / 2.0
        guard rx > 0 && ry > 0 else { return false }
        let cx = rect.midX
        let cy = rect.midY
        let val = pow((point.x - cx) / rx, 2) + pow((point.y - cy) / ry, 2)

        if fillStyle == .solid || fillStyle == .striped {
            return val <= 1.05
        }
        let innerRx = max(0.1, rx - strokeWidth - 6)
        let innerRy = max(0.1, ry - strokeWidth - 6)
        let innerVal = pow((point.x - cx) / innerRx, 2) + pow((point.y - cy) / innerRy, 2)
        return val <= 1.15 && innerVal >= 0.85
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        let handles = getHandlePoints()
        for (i, hp) in handles.enumerated() {
            if hypot(point.x - hp.x, point.y - hp.y) <= radius {
                return i
            }
        }
        return nil
    }

    public func getHandlePoints() -> [CGPoint] {
        let minX = rect.minX, midX = rect.midX, maxX = rect.maxX
        let minY = rect.minY, midY = rect.midY, maxY = rect.maxY
        return [
            CGPoint(x: minX, y: minY),
            CGPoint(x: midX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: maxX, y: midY),
            CGPoint(x: maxX, y: maxY),
            CGPoint(x: midX, y: maxY),
            CGPoint(x: minX, y: maxY),
            CGPoint(x: minX, y: midY)
        ]
    }

    public func move(by delta: CGPoint) {
        rect.origin.x += delta.x
        rect.origin.y += delta.y
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

        var w = max(abs(maxX - minX), 4.0)
        var h = max(abs(maxY - minY), 4.0)
        if isPerfectCircle {
            let side = max(w, h)
            w = side
            h = side
        }

        rect = CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: w,
            height: h
        )
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let strokeNSColor = NSColor(hex: color)
        let strokeCGColor = strokeNSColor.cgColor

        let path = CGPath(ellipseIn: rect, transform: nil)
        context.addPath(path)

        if fillStyle == .solid {
            context.setFillColor(strokeNSColor.withAlphaComponent(0.25).cgColor)
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
    public var strokeWidth: CGFloat

    public var start: CGPoint
    public var end: CGPoint
    public var lineStyle: LineStyle

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
        let padding = strokeWidth / 2.0 + 8.0
        let minX = min(start.x, end.x) - padding
        let minY = min(start.y, end.y) - padding
        let maxX = max(start.x, end.x) + padding
        let maxY = max(start.y, end.y) + padding
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func contains(point: CGPoint) -> Bool {
        let threshold = max(strokeWidth * 1.5, 10.0)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lenSq = dx * dx + dy * dy
        if lenSq < 0.001 { return hypot(point.x - start.x, point.y - start.y) <= threshold }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lenSq))
        let proj = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - proj.x, point.y - proj.y) <= threshold
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        if hypot(point.x - start.x, point.y - start.y) <= radius { return 0 }
        if hypot(point.x - end.x, point.y - end.y) <= radius { return 1 }
        return nil
    }

    public func move(by delta: CGPoint) {
        start = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
        end = CGPoint(x: end.x + delta.x, y: end.y + delta.y)
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        if index == 0 { start = point }
        else if index == 1 { end = point }
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let strokeColor = NSColor(hex: color).cgColor
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
