import Foundation
import CoreGraphics
import AppKit

public final class MagnifierLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .magnifier
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String
    public var strokeWidth: CGFloat

    public var sourceCenter: CGPoint
    public var targetCenter: CGPoint
    public var radius: CGFloat
    public var zoomFactor: CGFloat

    public init(
        id: UUID = UUID(),
        sourceCenter: CGPoint,
        targetCenter: CGPoint? = nil,
        radius: CGFloat = 48.0,
        zoomFactor: CGFloat = 2.0,
        color: String = "#007AFF",
        strokeWidth: CGFloat = 3.0,
        zIndex: Int = 10
    ) {
        self.id = id
        self.sourceCenter = sourceCenter
        self.targetCenter = targetCenter ?? CGPoint(x: sourceCenter.x + 80.0, y: sourceCenter.y - 80.0)
        self.radius = radius
        self.zoomFactor = zoomFactor
        self.color = color
        self.strokeWidth = strokeWidth
        self.zIndex = zIndex
    }

    public func getBoundingBox() -> CGRect {
        let pad = radius + strokeWidth + 12.0
        let minX = min(sourceCenter.x, targetCenter.x) - pad
        let minY = min(sourceCenter.y, targetCenter.y) - pad
        let maxX = max(sourceCenter.x, targetCenter.x) + pad
        let maxY = max(sourceCenter.y, targetCenter.y) + pad
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func contains(point: CGPoint) -> Bool {
        return hypot(point.x - targetCenter.x, point.y - targetCenter.y) <= radius ||
               hypot(point.x - sourceCenter.x, point.y - sourceCenter.y) <= 18.0
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 16.0) -> Int? {
        // Handle 0: Source sampling ring (small circle)
        if hypot(point.x - sourceCenter.x, point.y - sourceCenter.y) <= max(radius, 18.0) { return 0 }
        // Handle 1: Target magnification lens center (big circle)
        if hypot(point.x - targetCenter.x, point.y - targetCenter.y) <= self.radius { return 1 }
        return nil
    }

    public func move(by delta: CGPoint) {
        sourceCenter.x += delta.x
        sourceCenter.y += delta.y
        targetCenter.x += delta.x
        targetCenter.y += delta.y
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        if index == 0 {
            sourceCenter = point
        } else if index == 1 {
            targetCenter = point
        }
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        // Standard vector preview (leader line & rings)
        context.saveGState()

        let strokeColor = NSColor(hex: color).cgColor
        context.setStrokeColor(strokeColor)
        context.setLineWidth(strokeWidth)

        // 1. Leader line connecting source and target centers
        context.move(to: sourceCenter)
        context.addLine(to: targetCenter)
        context.strokePath()

        // 2. Source sampling ring
        let sourceRect = CGRect(x: sourceCenter.x - 10, y: sourceCenter.y - 10, width: 20, height: 20)
        context.strokeEllipse(in: sourceRect)

        // 3. Destination lens ring
        let lensRect = CGRect(x: targetCenter.x - radius, y: targetCenter.y - radius, width: radius * 2, height: radius * 2)
        context.setLineWidth(strokeWidth + 2.0)
        context.strokeEllipse(in: lensRect)

        // Subtle drop shadow around destination lens
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(1.0)
        context.strokeEllipse(in: lensRect.insetBy(dx: -1.0, dy: -1.0))

        context.restoreGState()
    }

    /// Lens magnification rendering using backing bitmap (Section 6)
    public func renderMagnifiedLens(from originalImage: CGImage, in context: CGContext) {
        context.saveGState()

        let sampleRadius = radius / zoomFactor
        let sourceRect = CGRect(
            x: sourceCenter.x - sampleRadius,
            y: sourceCenter.y - sampleRadius,
            width: sampleRadius * 2,
            height: sampleRadius * 2
        )

        let lensRect = CGRect(
            x: targetCenter.x - radius,
            y: targetCenter.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        // 1. Circular clip path at target coordinate
        let clipPath = CGPath(ellipseIn: lensRect, transform: nil)
        context.addPath(clipPath)
        context.clip()

        // 2. Sample from originalImage directly matching canvas coordinates
        let imageCropRect = sourceRect

        if let cropped = originalImage.cropping(to: imageCropRect) {
            context.saveGState()
            context.translateBy(x: lensRect.origin.x, y: lensRect.origin.y + lensRect.height)
            context.scaleBy(x: 1.0, y: -1.0)
            context.interpolationQuality = .high
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: lensRect.width, height: lensRect.height))
            context.restoreGState()
        }

        context.restoreGState()
    }

    public func clone() -> AnnotationLayer {
        MagnifierLayer(
            id: UUID(),
            sourceCenter: sourceCenter,
            targetCenter: targetCenter,
            radius: radius,
            zoomFactor: zoomFactor,
            color: color,
            strokeWidth: strokeWidth,
            zIndex: zIndex
        )
    }
}
