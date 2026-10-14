import Foundation
import CoreGraphics
import AppKit

public final class CalloutLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .callout
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String
    public var strokeWidth: CGFloat

    public var frame: CGRect
    public var cornerRadius: CGFloat
    public var text: String {
        didSet {
            updateFrameForText()
        }
    }
    public var fontSize: CGFloat {
        didSet {
            updateFrameForText()
        }
    }
    public var tailTip: CGPoint // Draggable anchor for the bubble's tail
    public var isFilled: Bool

    public init(
        id: UUID = UUID(),
        frame: CGRect? = nil,
        origin: CGPoint? = nil,
        cornerRadius: CGFloat = 8.0,
        text: String = "Callout",
        fontSize: CGFloat = 14.0,
        tailTip: CGPoint? = nil,
        isFilled: Bool = true,
        color: String = "#FF3B30",
        strokeWidth: CGFloat = 2.0,
        zIndex: Int = 0
    ) {
        self.id = id
        self.cornerRadius = cornerRadius
        self.text = text
        self.fontSize = fontSize
        self.isFilled = isFilled
        self.color = color
        self.strokeWidth = strokeWidth
        self.zIndex = zIndex

        let calculatedSize = CalloutLayer.calculateSize(for: text, fontSize: fontSize)
        if let f = frame {
            self.frame = CGRect(origin: f.origin, size: calculatedSize)
        } else if let o = origin {
            self.frame = CGRect(origin: o, size: calculatedSize)
        } else {
            self.frame = CGRect(origin: .zero, size: calculatedSize)
        }

        self.tailTip = tailTip ?? CGPoint(x: self.frame.midX, y: self.frame.maxY + 24.0)
    }

    public static func calculateSize(for text: String, fontSize: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        let attrString = NSAttributedString(string: text.isEmpty ? " " : text, attributes: textAttrs)
        let naturalSize = attrString.size()

        let horizontalPadding: CGFloat = 24.0
        let verticalPadding: CGFloat = 16.0
        let w = max(54.0, ceil(naturalSize.width) + horizontalPadding)
        let h = max(34.0, ceil(naturalSize.height) + verticalPadding)
        return CGSize(width: w, height: h)
    }

    public func updateFrameForText() {
        let newSize = CalloutLayer.calculateSize(for: text, fontSize: fontSize)
        frame.size = newSize
    }

    public func getBoundingBox() -> CGRect {
        let union = frame.union(CGRect(x: tailTip.x - 4, y: tailTip.y - 4, width: 8, height: 8))
        let padding = strokeWidth + 8.0
        return union.insetBy(dx: -padding, dy: -padding)
    }

    public func contains(point: CGPoint) -> Bool {
        return frame.contains(point) || hypot(point.x - tailTip.x, point.y - tailTip.y) <= 12.0
    }

    // Exactly one draggable handle: the tail tip
    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        if hypot(point.x - tailTip.x, point.y - tailTip.y) <= max(radius, 10.0) {
            return 0
        }
        return nil
    }

    public func move(by delta: CGPoint) {
        frame.origin.x += delta.x
        frame.origin.y += delta.y
        tailTip.x += delta.x
        tailTip.y += delta.y
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        if index == 0 {
            tailTip = point
        }
    }

    // MARK: - Geometric Edge Snapping & Corner Exclusion

    private enum Edge {
        case top, bottom, left, right
    }

    public func pathForCallout() -> CGPath {
        let dx = tailTip.x - frame.midX
        let dy = tailTip.y - frame.midY

        // Strict Edge Snapping: determine closest edge based on slope and relative direction
        let edge: Edge
        if abs(dx) * frame.height > abs(dy) * frame.width {
            edge = dx > 0 ? .right : .left
        } else {
            edge = dy > 0 ? .bottom : .top
        }

        // Corner exclusion: clamp tail attachment base away from rounded corners
        let cornerMargin = cornerRadius + 6.0
        let tailBaseWidth: CGFloat = min(28.0, edge == .top || edge == .bottom ? max(16.0, frame.width * 0.28) : max(16.0, frame.height * 0.28))
        let halfBase = tailBaseWidth / 2.0

        let path = CGMutablePath()
        path.addRoundedRect(in: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius)

        let b1: CGPoint
        let b2: CGPoint

        switch edge {
        case .bottom:
            let clampedCenter = min(frame.maxX - cornerMargin - halfBase, max(frame.minX + cornerMargin + halfBase, tailTip.x))
            b1 = CGPoint(x: clampedCenter - halfBase, y: frame.maxY)
            b2 = CGPoint(x: clampedCenter + halfBase, y: frame.maxY)
        case .top:
            let clampedCenter = min(frame.maxX - cornerMargin - halfBase, max(frame.minX + cornerMargin + halfBase, tailTip.x))
            b1 = CGPoint(x: clampedCenter - halfBase, y: frame.minY)
            b2 = CGPoint(x: clampedCenter + halfBase, y: frame.minY)
        case .left:
            let clampedCenter = min(frame.maxY - cornerMargin - halfBase, max(frame.minY + cornerMargin + halfBase, tailTip.y))
            b1 = CGPoint(x: frame.minX, y: clampedCenter - halfBase)
            b2 = CGPoint(x: frame.minX, y: clampedCenter + halfBase)
        case .right:
            let clampedCenter = min(frame.maxY - cornerMargin - halfBase, max(frame.minY + cornerMargin + halfBase, tailTip.y))
            b1 = CGPoint(x: frame.maxX, y: clampedCenter - halfBase)
            b2 = CGPoint(x: frame.maxX, y: clampedCenter + halfBase)
        }

        // Swooping smoothed tail path using Bezier curves
        let tailPath = CGMutablePath()
        tailPath.move(to: b1)
        let ctrl1 = CGPoint(x: (b1.x + tailTip.x) / 2.0, y: (b1.y + tailTip.y) / 2.0)
        tailPath.addQuadCurve(to: tailTip, control: ctrl1)
        let ctrl2 = CGPoint(x: (b2.x + tailTip.x) / 2.0, y: (b2.y + tailTip.y) / 2.0)
        tailPath.addQuadCurve(to: b2, control: ctrl2)
        tailPath.closeSubpath()

        path.addPath(tailPath)
        return path
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let badgeColor = NSColor(hex: color).cgColor
        context.setFillColor(badgeColor)

        // Draw solid rounded rectangle with swooping attached tail
        let path = pathForCallout()
        context.addPath(path)
        context.fillPath()

        // Text attributes: bold white text centered in the bubble
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]

        let insetRect = frame.insetBy(dx: 10, dy: 6)
        let attrString = NSAttributedString(string: text, attributes: textAttrs)
        let textSize = attrString.size()
        let textDrawRect = CGRect(
            x: insetRect.midX - textSize.width / 2.0,
            y: insetRect.midY - textSize.height / 2.0,
            width: textSize.width,
            height: textSize.height
        )

        let nsCtx = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        attrString.draw(in: textDrawRect)
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
    }

    public func clone() -> AnnotationLayer {
        CalloutLayer(
            id: UUID(),
            frame: frame,
            cornerRadius: cornerRadius,
            text: text,
            fontSize: fontSize,
            tailTip: tailTip,
            isFilled: isFilled,
            color: color,
            strokeWidth: strokeWidth,
            zIndex: zIndex
        )
    }
}
