import Foundation
import CoreGraphics
import AppKit

/// A standalone text annotation layer without backgrounds or bubbles.
/// Text grows symmetrically in both directions around its center anchor,
/// and is rendered with the default Impact drop shadow.
public final class TextLayer: AnnotationLayer, TextEditableLayer {
    public let id: UUID
    public let type: LayerType = .text
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String
    public var strokeWidth: CGFloat = 1.0

    public var text: String {
        didSet {
            _cachedBodySize = nil
            _cachedBoundingBox = nil
        }
    }

    /// Center anchor point where the user placed/dragged the text
    public var center: CGPoint {
        didSet {
            _cachedBoundingBox = nil
        }
    }

    /// True while the in-place editor draws the text
    public var isTextHidden: Bool = false

    private var _cachedBodySize: CGSize?
    private var _cachedBoundingBox: CGRect?

    public init(
        id: UUID = UUID(),
        text: String = "",
        center: CGPoint,
        color: String = "#FF3B30",
        strokeWidth: CGFloat = 1.0,
        zIndex: Int = 0
    ) {
        self.id = id
        self.text = text
        self.center = center
        self.color = color
        self.strokeWidth = strokeWidth
        self.zIndex = zIndex
    }

    public static func bodySize(for text: String) -> CGSize {
        let textSize = CalloutTextLayout.textSize(for: text)
        let textHeight = text.isEmpty ? CalloutTextLayout.textSize(for: " ").height : textSize.height
        let pad = CalloutTextLayout.padding
        return CGSize(
            width: ceil(max(textSize.width, CalloutTextLayout.minTextWidth) + pad.left + pad.right),
            height: ceil(textHeight + pad.top + pad.bottom)
        )
    }

    public var bodyRect: CGRect {
        let size = _cachedBodySize ?? {
            let s = Self.bodySize(for: text)
            _cachedBodySize = s
            return s
        }()
        return CGRect(
            x: center.x - size.width / 2.0,
            y: center.y - size.height / 2.0,
            width: size.width,
            height: size.height
        )
    }

    public var origin: CGPoint {
        bodyRect.origin
    }

    /// Text color follows the selected swatch color
    public var textColor: NSColor {
        FastColor.shared.nsColor(hex: color)
    }

    public func contains(point: CGPoint) -> Bool {
        guard isVisible else { return false }
        return bodyRect.contains(point)
    }

    public func getBoundingBox() -> CGRect {
        if let cached = _cachedBoundingBox { return cached }
        let box = bodyRect.insetBy(dx: -4.0, dy: -4.0)
        _cachedBoundingBox = box
        return box
    }

    public func move(by delta: CGPoint) {
        center.x += delta.x
        center.y += delta.y
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        return nil
    }

    public func updateHandle(index: Int, to point: CGPoint) {}

    public func draw(in context: CGContext, scale: CGFloat) {
        guard isVisible, !isTextHidden, !text.isEmpty else { return }
        context.saveGState()

        // Default drop shadow matching Impact visual styling
        context.setShadow(
            offset: CGSize(width: 0, height: -1.0),
            blur: 2.5,
            color: NSColor.black.withAlphaComponent(0.25).cgColor
        )

        let pad = CalloutTextLayout.padding
        let frame = bodyRect
        CalloutTextLayout.draw(text, color: textColor, at: CGPoint(x: frame.minX + pad.left, y: frame.minY + pad.top), in: context)

        context.restoreGState()
    }

    public func clone(withID newID: UUID) -> AnnotationLayer {
        let copy = TextLayer(
            id: newID,
            text: text,
            center: center,
            color: color,
            strokeWidth: strokeWidth,
            zIndex: zIndex
        )
        copy.isVisible = isVisible
        return copy
    }
}
