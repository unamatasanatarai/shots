import Foundation
import CoreGraphics
import AppKit

public final class TextLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .text
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String
    public var strokeWidth: CGFloat // Unused directly for text, but protocol requirement

    public var origin: CGPoint
    public var text: String
    public var fontSize: CGFloat
    public var hasBackgroundPill: Bool
    public var pillColor: String

    public init(
        id: UUID = UUID(),
        origin: CGPoint,
        text: String = "Text",
        fontSize: CGFloat = 16.0,
        hasBackgroundPill: Bool = true,
        color: String = "#FFFFFF",
        pillColor: String = "#1E1E1E",
        zIndex: Int = 0
    ) {
        self.id = id
        self.origin = origin
        self.text = text
        self.fontSize = fontSize
        self.hasBackgroundPill = hasBackgroundPill
        self.color = color
        self.pillColor = pillColor
        self.strokeWidth = 2.0
        self.zIndex = zIndex
    }

    private func measure() -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attrs)
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    public func getBoundingBox() -> CGRect {
        let size = measure()
        let hPad: CGFloat = hasBackgroundPill ? 10.0 : 4.0
        let vPad: CGFloat = hasBackgroundPill ? 6.0 : 4.0
        return CGRect(
            x: origin.x - hPad,
            y: origin.y - vPad,
            width: size.width + hPad * 2,
            height: size.height + vPad * 2
        )
    }

    public func contains(point: CGPoint) -> Bool {
        return getBoundingBox().contains(point)
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        let box = getBoundingBox()
        let br = CGPoint(x: box.maxX, y: box.maxY)
        if hypot(point.x - br.x, point.y - br.y) <= radius {
            return 0
        }
        return nil
    }

    public func move(by delta: CGPoint) {
        origin.x += delta.x
        origin.y += delta.y
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        // Dragging handle scales font size
        let box = getBoundingBox()
        let newH = max(12.0, point.y - box.minY)
        fontSize = max(10.0, min(72.0, newH * 0.75))
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let box = getBoundingBox()

        if hasBackgroundPill {
            context.setFillColor(NSColor(hex: pillColor).withAlphaComponent(0.85).cgColor)
            let path = CGPath(roundedRect: box, cornerWidth: 6.0, cornerHeight: 6.0, transform: nil)
            context.addPath(path)
            context.fillPath()

            context.setStrokeColor(NSColor.white.withAlphaComponent(0.2).cgColor)
            context.setLineWidth(1.0)
            context.addPath(path)
            context.strokePath()
        }

        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(hex: color)
        ]

        let attrString = NSAttributedString(string: text, attributes: textAttrs)
        attrString.draw(at: origin)

        context.restoreGState()
    }

    public func clone() -> AnnotationLayer {
        TextLayer(
            id: UUID(),
            origin: origin,
            text: text,
            fontSize: fontSize,
            hasBackgroundPill: hasBackgroundPill,
            color: color,
            pillColor: pillColor,
            zIndex: zIndex
        )
    }
}
