import Foundation
import CoreGraphics
import AppKit

// MARK: - Pen Layer (Freehand)

public final class PenLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .pen
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String
    public var strokeWidth: CGFloat

    public var points: [CGPoint]

    public init(
        id: UUID = UUID(),
        points: [CGPoint] = [],
        color: String = "#FF3B30",
        strokeWidth: CGFloat = 4.0,
        zIndex: Int = 0
    ) {
        self.id = id
        self.points = points
        self.color = color
        self.strokeWidth = strokeWidth
        self.zIndex = zIndex
    }

    public func getBoundingBox() -> CGRect {
        guard !points.isEmpty else { return .zero }
        var minX = points[0].x, maxX = points[0].x
        var minY = points[0].y, maxY = points[0].y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let pad = strokeWidth + 6.0
        return CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + pad * 2, height: maxY - minY + pad * 2)
    }

    public func contains(point: CGPoint) -> Bool {
        guard !points.isEmpty else { return false }
        let threshold = max(strokeWidth / 2.0 + 4.0, 10.0)
        if points.count == 1 {
            return hypot(point.x - points[0].x, point.y - points[0].y) <= threshold
        }
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lenSq = dx * dx + dy * dy
            if lenSq < 0.001 {
                if hypot(point.x - a.x, point.y - a.y) <= threshold { return true }
                continue
            }
            let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq))
            let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
            if hypot(point.x - proj.x, point.y - proj.y) <= threshold { return true }
        }
        return false
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        // Freehand pen strokes cannot be scaled, only moved (following highlighter rules).
        return nil
    }

    public func move(by delta: CGPoint) {
        for i in 0..<points.count {
            points[i].x += delta.x
            points[i].y += delta.y
        }
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        if index >= 0 && index < points.count {
            points[index] = point
        }
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        guard !points.isEmpty else { return }
        context.saveGState()

        let strokeColor = NSColor(hex: color).cgColor
        context.setStrokeColor(strokeColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if points.count == 1 {
            let p = points[0]
            context.setFillColor(strokeColor)
            context.fillEllipse(in: CGRect(x: p.x - strokeWidth / 2.0, y: p.y - strokeWidth / 2.0, width: strokeWidth, height: strokeWidth))
            context.restoreGState()
            return
        }

        context.beginPath()
        context.move(to: points[0])

        if points.count == 2 {
            context.addLine(to: points[1])
        } else {
            // Quadratic smoothing between midpoints (following highlighter rules)
            for i in 1..<points.count {
                let mid = CGPoint(
                    x: (points[i - 1].x + points[i].x) / 2.0,
                    y: (points[i - 1].y + points[i].y) / 2.0
                )
                context.addQuadCurve(to: mid, control: points[i - 1])
            }
            context.addLine(to: points.last!)
        }
        context.strokePath()

        context.restoreGState()
    }

    public func clone() -> AnnotationLayer {
        PenLayer(
            id: UUID(),
            points: points,
            color: color,
            strokeWidth: strokeWidth,
            zIndex: zIndex
        )
    }
}

// MARK: - Highlighter Layer

public final class HighlighterLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .highlighter
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String
    public var strokeWidth: CGFloat

    public var points: [CGPoint]

    public init(
        id: UUID = UUID(),
        points: [CGPoint] = [],
        color: String = "#FFCC00",
        strokeWidth: CGFloat = 20.0,
        zIndex: Int = 0
    ) {
        self.id = id
        self.points = points
        self.color = color
        self.strokeWidth = strokeWidth
        self.zIndex = zIndex
    }

    public func getBoundingBox() -> CGRect {
        guard !points.isEmpty else { return .zero }
        var minX = points[0].x, maxX = points[0].x
        var minY = points[0].y, maxY = points[0].y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let pad = strokeWidth / 2.0 + 4.0
        return CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + pad * 2, height: maxY - minY + pad * 2)
    }

    public func contains(point: CGPoint) -> Bool {
        guard !points.isEmpty else { return false }
        let threshold = strokeWidth / 2.0 + 4.0
        if points.count == 1 {
            return hypot(point.x - points[0].x, point.y - points[0].y) <= threshold
        }
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lenSq = dx * dx + dy * dy
            if lenSq < 0.001 {
                if hypot(point.x - a.x, point.y - a.y) <= threshold { return true }
                continue
            }
            let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq))
            let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
            if hypot(point.x - proj.x, point.y - proj.y) <= threshold { return true }
        }
        return false
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        // Highlighting cannot be scaled, only moved. No control handles.
        return nil
    }

    public func move(by delta: CGPoint) {
        for i in 0..<points.count {
            points[i].x += delta.x
            points[i].y += delta.y
        }
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        if index >= 0 && index < points.count {
            points[index] = point
        }
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        guard !points.isEmpty else { return }
        context.saveGState()

        let baseColor = NSColor(hex: color)
        let rgbColor = baseColor.usingColorSpace(.sRGB) ?? baseColor
        let r = rgbColor.redComponent
        let g = rgbColor.greenComponent
        let b = rgbColor.blueComponent
        // White or near-white cannot use .multiply because 1.0 * background = background (invisible)
        let isWhite = (r > 0.90 && g > 0.90 && b > 0.90)

        let strokeColor: CGColor
        if isWhite {
            context.setBlendMode(.normal)
            strokeColor = rgbColor.withAlphaComponent(0.55).cgColor
        } else {
            context.setBlendMode(.multiply)
            strokeColor = rgbColor.withAlphaComponent(0.40).cgColor
        }

        if points.count == 1 {
            let p = points[0]
            context.setFillColor(strokeColor)
            context.fillEllipse(in: CGRect(x: p.x - strokeWidth / 2.0, y: p.y - strokeWidth / 2.0, width: strokeWidth, height: strokeWidth))
            context.restoreGState()
            return
        }

        context.setStrokeColor(strokeColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.beginPath()
        context.move(to: points[0])

        if points.count == 2 {
            context.addLine(to: points[1])
        } else {
            // Quadratic Bezier smoothing between midpoints
            for i in 1..<points.count {
                let mid = CGPoint(
                    x: (points[i - 1].x + points[i].x) / 2.0,
                    y: (points[i - 1].y + points[i].y) / 2.0
                )
                context.addQuadCurve(to: mid, control: points[i - 1])
            }
            context.addLine(to: points.last!)
        }
        context.strokePath()

        context.restoreGState()
    }

    public func clone() -> AnnotationLayer {
        HighlighterLayer(
            id: UUID(),
            points: points,
            color: color,
            strokeWidth: strokeWidth,
            zIndex: zIndex
        )
    }
}
