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
    public var text: String
    public var fontSize: CGFloat
    public var tailTip: CGPoint // Draggable anchor for the bubble's tail
    public var isFilled: Bool

    public init(
        id: UUID = UUID(),
        frame: CGRect,
        cornerRadius: CGFloat = 8.0,
        text: String = "Callout",
        fontSize: CGFloat = 14.0,
        tailTip: CGPoint? = nil,
        isFilled: Bool = true,
        color: String = "#FF3B30",
        strokeWidth: CGFloat = 3.0,
        zIndex: Int = 0
    ) {
        self.id = id
        self.frame = frame
        self.cornerRadius = cornerRadius
        self.text = text
        self.fontSize = fontSize
        self.tailTip = tailTip ?? CGPoint(x: frame.midX, y: frame.maxY + 24.0)
        self.isFilled = isFilled
        self.color = color
        self.strokeWidth = strokeWidth
        self.zIndex = zIndex
    }

    public func getBoundingBox() -> CGRect {
        let union = frame.union(CGRect(x: tailTip.x - 4, y: tailTip.y - 4, width: 8, height: 8))
        let padding = strokeWidth + 8.0
        return union.insetBy(dx: -padding, dy: -padding)
    }

    public func contains(point: CGPoint) -> Bool {
        return frame.contains(point) || hypot(point.x - tailTip.x, point.y - tailTip.y) <= 12.0
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        // Handle 0: tailTip
        if hypot(point.x - tailTip.x, point.y - tailTip.y) <= radius {
            return 0
        }
        // Handle 1: bottom-right resizing handle
        let br = CGPoint(x: frame.maxX, y: frame.maxY)
        if hypot(point.x - br.x, point.y - br.y) <= radius {
            return 1
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
        } else if index == 1 {
            let newW = max(60.0, point.x - frame.minX)
            let newH = max(36.0, point.y - frame.minY)
            frame.size = CGSize(width: newW, height: newH)
        }
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let strokeNSColor = NSColor(hex: color)
        let strokeCGColor = strokeNSColor.cgColor

        // Draw speech bubble path with tail
        let path = CGMutablePath()
        path.addRoundedRect(in: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius)

        // Tail triangle connecting from nearest side of frame to tailTip
        let tailBaseWidth: CGFloat = 16.0
        let baseMid = CGPoint(x: frame.midX, y: tailTip.y > frame.midY ? frame.maxY : frame.minY)
        let t1 = CGPoint(x: baseMid.x - tailBaseWidth / 2.0, y: baseMid.y)
        let t2 = CGPoint(x: baseMid.x + tailBaseWidth / 2.0, y: baseMid.y)

        let tailPath = CGMutablePath()
        tailPath.move(to: t1)
        tailPath.addLine(to: tailTip)
        tailPath.addLine(to: t2)
        tailPath.closeSubpath()

        if isFilled {
            // White / opaque background with subtle shadow
            context.setFillColor(NSColor.white.cgColor)
            context.addPath(path)
            context.fillPath()
            context.addPath(tailPath)
            context.fillPath()
        }

        // Stroke bubble & tail
        context.setStrokeColor(strokeCGColor)
        context.setLineWidth(strokeWidth)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()

        context.addPath(tailPath)
        context.strokePath()

        // Draw text inside
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: isFilled ? NSColor.black : strokeNSColor,
            .paragraphStyle: paragraphStyle
        ]

        let insetRect = frame.insetBy(dx: 8, dy: 6)
        let attrString = NSAttributedString(string: text, attributes: textAttrs)
        let textSize = attrString.size()
        let textDrawRect = CGRect(
            x: insetRect.midX - textSize.width / 2.0,
            y: insetRect.midY - textSize.height / 2.0,
            width: textSize.width,
            height: textSize.height
        )

        attrString.draw(in: textDrawRect)

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
