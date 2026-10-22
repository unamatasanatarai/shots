import Foundation
import CoreGraphics
import AppKit

// MARK: - Pen Layer (Freehand)

public final class PenLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .pen
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String {
        didSet { _cachedStrokeColor = nil }
    }
    public var strokeWidth: CGFloat {
        didSet { invalidateCache() }
    }

    public var points: [CGPoint] {
        didSet { invalidateCache() }
    }

    private var _cachedBoundingBox: CGRect?
    private var _cachedStrokeColor: CGColor?
    private var _cachedPath: CGPath?
    private var _cachedHoverPath: CGPath?

    @inline(__always)
    private func invalidateCache() {
        _cachedBoundingBox = nil
        _cachedPath = nil
        _cachedHoverPath = nil
    }

    public func pathForStroke() -> CGPath {
        if let cached = _cachedPath { return cached }
        let path = CGMutablePath()
        guard !points.isEmpty else {
            _cachedPath = path
            return path
        }
        if points.count == 1 {
            let p = points[0]
            path.addEllipse(in: CGRect(x: p.x - strokeWidth / 2.0, y: p.y - strokeWidth / 2.0, width: strokeWidth, height: strokeWidth))
            _cachedPath = path
            return path
        }
        path.move(to: points[0])
        if points.count == 2 {
            path.addLine(to: points[1])
        } else {
            for i in 1..<points.count {
                let mid = CGPoint(
                    x: (points[i - 1].x + points[i].x) / 2.0,
                    y: (points[i - 1].y + points[i].y) / 2.0
                )
                path.addQuadCurve(to: mid, control: points[i - 1])
            }
            path.addLine(to: points.last!)
        }
        _cachedPath = path
        return path
    }

    public func hoverOutlinePath() -> CGPath? {
        if let cached = _cachedHoverPath { return cached }
        guard !points.isEmpty else { return nil }
        if points.count == 1 {
            let p = points[0]
            let path = CGPath(ellipseIn: CGRect(x: p.x - strokeWidth / 2.0, y: p.y - strokeWidth / 2.0, width: strokeWidth, height: strokeWidth), transform: nil)
            _cachedHoverPath = path
            return path
        }
        let strokePath = pathForStroke()
        let stroked = strokePath.copy(strokingWithWidth: strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
        _cachedHoverPath = stroked
        return stroked
    }

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
        if let cached = _cachedBoundingBox { return cached }
        guard !points.isEmpty else { return .zero }
        var minX = points[0].x, maxX = points[0].x
        var minY = points[0].y, maxY = points[0].y
        for p in points {
            if p.x < minX { minX = p.x }
            else if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            else if p.y > maxY { maxY = p.y }
        }
        let pad = strokeWidth + 6.0
        let box = CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + pad * 2, height: maxY - minY + pad * 2)
        _cachedBoundingBox = box
        return box
    }

    public func contains(point: CGPoint) -> Bool {
        guard !points.isEmpty else { return false }
        guard getBoundingBox().contains(point) else { return false }

        let threshold = max(strokeWidth / 2.0 + 4.0, 10.0)
        let thresholdSq = threshold * threshold

        if points.count == 1 {
            let px = point.x - points[0].x
            let py = point.y - points[0].y
            return px * px + py * py <= thresholdSq
        }

        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lenSq = dx * dx + dy * dy
            if lenSq < 0.001 {
                let px = point.x - a.x
                let py = point.y - a.y
                if px * px + py * py <= thresholdSq { return true }
                continue
            }
            let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq))
            let projX = a.x + t * dx
            let projY = a.y + t * dy
            let px = point.x - projX
            let py = point.y - projY
            if px * px + py * py <= thresholdSq { return true }
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
        if var box = _cachedBoundingBox {
            box.origin.x += delta.x
            box.origin.y += delta.y
            _cachedBoundingBox = box
        }
        var transform = CGAffineTransform(translationX: delta.x, y: delta.y)
        if let path = _cachedPath {
            _cachedPath = path.copy(using: &transform)
        }
        if let hover = _cachedHoverPath {
            _cachedHoverPath = hover.copy(using: &transform)
        }
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        if index >= 0 && index < points.count {
            points[index] = point
            invalidateCache()
        }
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        guard !points.isEmpty else { return }
        context.saveGState()

        // Subtle natural shadow for depth and crispness
        context.setShadow(offset: CGSize(width: 0, height: -1.0), blur: 2.5, color: NSColor.black.withAlphaComponent(0.25).cgColor)

        let strokeColor = _cachedStrokeColor ?? {
            let c = FastColor.shared.cgColor(hex: color)
            _cachedStrokeColor = c
            return c
        }()

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

        let path = pathForStroke()
        context.addPath(path)
        context.strokePath()

        context.restoreGState()
    }

    public func clone(withID newID: UUID) -> AnnotationLayer {
        PenLayer(
            id: newID,
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
    public var color: String {
        didSet {
            _cachedStrokeColor = nil
            _cachedIsWhite = nil
        }
    }
    public var strokeWidth: CGFloat {
        didSet { invalidateCache() }
    }

    public var points: [CGPoint] {
        didSet { invalidateCache() }
    }

    private var _cachedBoundingBox: CGRect?
    private var _cachedPath: CGPath?
    private var _cachedHoverPath: CGPath?
    private var _cachedStrokeColor: CGColor?
    private var _cachedIsWhite: Bool?

    @inline(__always)
    private func invalidateCache() {
        _cachedBoundingBox = nil
        _cachedPath = nil
        _cachedHoverPath = nil
    }

    public func pathForStroke() -> CGPath {
        if let cached = _cachedPath { return cached }
        let path = CGMutablePath()
        guard !points.isEmpty else {
            _cachedPath = path
            return path
        }
        if points.count == 1 {
            let p = points[0]
            path.addEllipse(in: CGRect(x: p.x - strokeWidth / 2.0, y: p.y - strokeWidth / 2.0, width: strokeWidth, height: strokeWidth))
            _cachedPath = path
            return path
        }
        path.move(to: points[0])
        if points.count == 2 {
            path.addLine(to: points[1])
        } else {
            for i in 1..<points.count {
                let mid = CGPoint(
                    x: (points[i - 1].x + points[i].x) / 2.0,
                    y: (points[i - 1].y + points[i].y) / 2.0
                )
                path.addQuadCurve(to: mid, control: points[i - 1])
            }
            path.addLine(to: points.last!)
        }
        _cachedPath = path
        return path
    }

    public func hoverOutlinePath() -> CGPath? {
        if let cached = _cachedHoverPath { return cached }
        guard !points.isEmpty else { return nil }
        if points.count == 1 {
            let p = points[0]
            let path = CGPath(ellipseIn: CGRect(x: p.x - strokeWidth / 2.0, y: p.y - strokeWidth / 2.0, width: strokeWidth, height: strokeWidth), transform: nil)
            _cachedHoverPath = path
            return path
        }
        let strokePath = pathForStroke()
        let stroked = strokePath.copy(strokingWithWidth: strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
        _cachedHoverPath = stroked
        return stroked
    }

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
        if let cached = _cachedBoundingBox { return cached }
        guard !points.isEmpty else { return .zero }
        var minX = points[0].x, maxX = points[0].x
        var minY = points[0].y, maxY = points[0].y
        for p in points {
            if p.x < minX { minX = p.x }
            else if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            else if p.y > maxY { maxY = p.y }
        }
        let pad = strokeWidth / 2.0 + 4.0
        let box = CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + pad * 2, height: maxY - minY + pad * 2)
        _cachedBoundingBox = box
        return box
    }

    public func contains(point: CGPoint) -> Bool {
        guard !points.isEmpty else { return false }
        guard getBoundingBox().contains(point) else { return false }

        let threshold = strokeWidth / 2.0 + 4.0
        let thresholdSq = threshold * threshold

        if points.count == 1 {
            let px = point.x - points[0].x
            let py = point.y - points[0].y
            return px * px + py * py <= thresholdSq
        }

        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lenSq = dx * dx + dy * dy
            if lenSq < 0.001 {
                let px = point.x - a.x
                let py = point.y - a.y
                if px * px + py * py <= thresholdSq { return true }
                continue
            }
            let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq))
            let projX = a.x + t * dx
            let projY = a.y + t * dy
            let px = point.x - projX
            let py = point.y - projY
            if px * px + py * py <= thresholdSq { return true }
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
        if var box = _cachedBoundingBox {
            box.origin.x += delta.x
            box.origin.y += delta.y
            _cachedBoundingBox = box
        }
        var transform = CGAffineTransform(translationX: delta.x, y: delta.y)
        if let path = _cachedPath {
            _cachedPath = path.copy(using: &transform)
        }
        if let hover = _cachedHoverPath {
            _cachedHoverPath = hover.copy(using: &transform)
        }
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        if index >= 0 && index < points.count {
            points[index] = point
            invalidateCache()
        }
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        guard !points.isEmpty else { return }
        context.saveGState()

        let isWhite: Bool
        let strokeColor: CGColor
        if let cachedColor = _cachedStrokeColor, let cachedWhite = _cachedIsWhite {
            isWhite = cachedWhite
            strokeColor = cachedColor
        } else {
            let (r, g, b) = FastColor.parseRGB(from: color)
            let white = (r > 0.90 && g > 0.90 && b > 0.90)
            isWhite = white
            _cachedIsWhite = white
            if white {
                strokeColor = CGColor(srgbRed: r, green: g, blue: b, alpha: 0.55)
            } else {
                strokeColor = CGColor(srgbRed: r, green: g, blue: b, alpha: 0.40)
            }
            _cachedStrokeColor = strokeColor
        }

        if isWhite {
            context.setBlendMode(.normal)
        } else {
            context.setBlendMode(.multiply)
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

        let path = pathForStroke()
        context.addPath(path)
        context.strokePath()

        context.restoreGState()
    }

    public func clone(withID newID: UUID) -> AnnotationLayer {
        HighlighterLayer(
            id: newID,
            points: points,
            color: color,
            strokeWidth: strokeWidth,
            zIndex: zIndex
        )
    }
}
