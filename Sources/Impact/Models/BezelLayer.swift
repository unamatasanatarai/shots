import Foundation
import CoreGraphics
import AppKit

public enum BezelStyle: String, Codable {
    case macWindow
    case shadowOnly
    case wallpaperGradient
}

// MARK: - Bezel Layer

public final class BezelLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .bezel
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String = "#000000"
    public var strokeWidth: CGFloat = 1.0

    public var style: BezelStyle
    public var title: String
    public var targetBounds: CGRect

    public init(
        id: UUID = UUID(),
        targetBounds: CGRect,
        style: BezelStyle = .macWindow,
        title: String = "Screenshot",
        zIndex: Int = -20
    ) {
        self.id = id
        self.targetBounds = targetBounds
        self.style = style
        self.title = title
        self.zIndex = zIndex
    }

    public func getBoundingBox() -> CGRect {
        let titleBarHeight: CGFloat = style == .macWindow ? 32.0 : 0.0
        let shadowPad: CGFloat = 32.0
        return CGRect(
            x: targetBounds.minX - shadowPad,
            y: targetBounds.minY - titleBarHeight - shadowPad,
            width: targetBounds.width + shadowPad * 2,
            height: targetBounds.height + titleBarHeight + shadowPad * 2
        )
    }

    public func contains(point: CGPoint) -> Bool {
        return getBoundingBox().contains(point)
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? { nil }

    public func move(by delta: CGPoint) {
        targetBounds.origin.x += delta.x
        targetBounds.origin.y += delta.y
    }

    public func updateHandle(index: Int, to point: CGPoint) {}

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let titleBarHeight: CGFloat = style == .macWindow ? 32.0 : 0.0
        let frameRect = CGRect(
            x: targetBounds.minX,
            y: targetBounds.minY - titleBarHeight,
            width: targetBounds.width,
            height: targetBounds.height + titleBarHeight
        )

        // Drop shadow
        context.setShadow(
            offset: CGSize(width: 0, height: -12),
            blur: 24,
            color: NSColor.black.withAlphaComponent(0.35).cgColor
        )

        let cornerRadius: CGFloat = 10.0
        let framePath = CGPath(roundedRect: frameRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.setFillColor(NSColor(white: 0.15, alpha: 1.0).cgColor)
        context.addPath(framePath)
        context.fillPath()

        // Clear shadow for interior details
        context.setShadow(offset: .zero, blur: 0, color: nil)

        if style == .macWindow {
            // Title bar background
            let titleBarRect = CGRect(x: frameRect.minX, y: frameRect.minY, width: frameRect.width, height: 32.0)
            context.setFillColor(NSColor(white: 0.22, alpha: 1.0).cgColor)
            context.fill(titleBarRect)

            // Window traffic lights (Red, Yellow, Green)
            let circleRadius: CGFloat = 6.0
            let startX = titleBarRect.minX + 16.0
            let centerY = titleBarRect.midY

            let colors: [NSColor] = [
                NSColor(srgbRed: 1.0, green: 0.38, blue: 0.35, alpha: 1.0),
                NSColor(srgbRed: 1.0, green: 0.74, blue: 0.22, alpha: 1.0),
                NSColor(srgbRed: 0.16, green: 0.80, blue: 0.25, alpha: 1.0)
            ]

            for (i, col) in colors.enumerated() {
                let x = startX + CGFloat(i) * 20.0
                context.setFillColor(col.cgColor)
                context.fillEllipse(in: CGRect(x: x - circleRadius, y: centerY - circleRadius, width: circleRadius * 2, height: circleRadius * 2))
            }
        }

        context.restoreGState()
    }

    public func clone() -> AnnotationLayer {
        BezelLayer(
            id: UUID(),
            targetBounds: targetBounds,
            style: style,
            title: title,
            zIndex: zIndex
        )
    }
}

// MARK: - Image Overlay Layer

public final class ImageOverlayLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .imageOverlay
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String = "#FFFFFF"
    public var strokeWidth: CGFloat = 0.0

    public var rect: CGRect
    public var image: CGImage?
    public var opacity: CGFloat = 1.0

    public init(
        id: UUID = UUID(),
        rect: CGRect,
        image: CGImage? = nil,
        opacity: CGFloat = 1.0,
        zIndex: Int = 5
    ) {
        self.id = id
        self.rect = rect
        self.image = image
        self.opacity = opacity
        self.zIndex = zIndex
    }

    public func getBoundingBox() -> CGRect {
        return rect.insetBy(dx: -4, dy: -4)
    }

    public func contains(point: CGPoint) -> Bool {
        return rect.contains(point)
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        let br = CGPoint(x: rect.maxX, y: rect.maxY)
        if hypot(point.x - br.x, point.y - br.y) <= radius { return 0 }
        return nil
    }

    public func move(by delta: CGPoint) {
        rect.origin.x += delta.x
        rect.origin.y += delta.y
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        let newW = max(24.0, point.x - rect.minX)
        let newH = max(24.0, point.y - rect.minY)
        rect.size = CGSize(width: newW, height: newH)
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        guard let img = image else { return }
        context.saveGState()
        context.setAlpha(opacity)
        context.draw(img, in: rect)
        context.restoreGState()
    }

    public func clone() -> AnnotationLayer {
        ImageOverlayLayer(
            id: UUID(),
            rect: rect,
            image: image,
            opacity: opacity,
            zIndex: zIndex
        )
    }
}
