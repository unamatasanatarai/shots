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
        let path = pathForCallout()
        let padding = strokeWidth + 8.0
        return path.boundingBox.insetBy(dx: -padding, dy: -padding)
    }

    public func contains(point: CGPoint) -> Bool {
        return pathForCallout().contains(point) || hypot(point.x - tailTip.x, point.y - tailTip.y) <= 12.0
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

        // Strict Edge Snapping: determine closest flat edge
        let edge: Edge
        if abs(dx) * frame.height > abs(dy) * frame.width {
            edge = dx > 0 ? .right : .left
        } else {
            edge = dy > 0 ? .bottom : .top
        }

        // Corner exclusion: clamp tail attachment base away from rounded corners
        let cornerMargin = cornerRadius + 6.0

        let pTL = CGPoint(x: frame.minX, y: frame.minY)
        let pTR = CGPoint(x: frame.maxX, y: frame.minY)
        let pBR = CGPoint(x: frame.maxX, y: frame.maxY)
        let pBL = CGPoint(x: frame.minX, y: frame.maxY)

        let edgeOrigin: CGPoint
        let edgeDir: CGPoint
        let edgeNormal: CGPoint
        let edgeLength: CGFloat

        switch edge {
        case .top:
            // Traversal TL -> TR: dir = (1, 0), normal = (0, -1) (upwards in flipped coords)
            edgeOrigin = pTL
            edgeDir = CGPoint(x: 1, y: 0)
            edgeNormal = CGPoint(x: 0, y: -1)
            edgeLength = frame.width
        case .right:
            // Traversal TR -> BR: dir = (0, 1), normal = (1, 0) (rightwards)
            edgeOrigin = pTR
            edgeDir = CGPoint(x: 0, y: 1)
            edgeNormal = CGPoint(x: 1, y: 0)
            edgeLength = frame.height
        case .bottom:
            // Traversal BR -> BL: dir = (-1, 0), normal = (0, 1) (downwards)
            edgeOrigin = pBR
            edgeDir = CGPoint(x: -1, y: 0)
            edgeNormal = CGPoint(x: 0, y: 1)
            edgeLength = frame.width
        case .left:
            // Traversal BL -> TL: dir = (0, -1), normal = (-1, 0) (leftwards)
            edgeOrigin = pBL
            edgeDir = CGPoint(x: 0, y: -1)
            edgeNormal = CGPoint(x: -1, y: 0)
            edgeLength = frame.height
        }

        func toCanvas(u: CGFloat, v: CGFloat) -> CGPoint {
            CGPoint(
                x: edgeOrigin.x + edgeDir.x * u + edgeNormal.x * v,
                y: edgeOrigin.y + edgeDir.y * u + edgeNormal.y * v
            )
        }

        func toLocal(_ pt: CGPoint) -> (u: CGFloat, v: CGFloat) {
            let rel = CGPoint(x: pt.x - edgeOrigin.x, y: pt.y - edgeOrigin.y)
            let u = rel.x * edgeDir.x + rel.y * edgeDir.y
            let v = rel.x * edgeNormal.x + rel.y * edgeNormal.y
            return (u, v)
        }

        let (tipU, rawTipV) = toLocal(tailTip)
        let tipV = max(5.0, rawTipV)

        let uMin = cornerMargin
        let uMax = edgeLength - cornerMargin
        let flatLen = max(10.0, uMax - uMin)

        let dist = hypot(tailTip.x - frame.midX, tailTip.y - frame.midY)
        // Adaptive base width: wider for distant pointers, sleek for short nubs
        let baseWidth = min(flatLen * 0.90, max(24.0, 18.0 + 0.18 * dist))
        let halfBase = baseWidth / 2.0

        let b1U: CGFloat
        let b2U: CGFloat

        if tipU > uMax {
            b2U = uMax
            b1U = max(uMin, uMax - baseWidth)
        } else if tipU < uMin {
            b1U = uMin
            b2U = min(uMax, uMin + baseWidth)
        } else {
            let centerU = min(uMax - halfBase, max(uMin + halfBase, tipU))
            b1U = centerU - halfBase
            b2U = centerU + halfBase
        }

        let pB1 = toCanvas(u: b1U, v: 0)
        let pB2 = toCanvas(u: b2U, v: 0)
        let pTip = toCanvas(u: tipU, v: tipV)

        // Organic fillet and swooping Bezier control points
        let actualBase = b2U - b1U
        let fillet = min(12.0, actualBase * 0.28)

        let c1_local: CGPoint
        let c2_local: CGPoint
        let c3_local: CGPoint
        let c4_local: CGPoint

        if tipU > b2U {
            // Forward pull (tip ahead of base in traversal dir, e.g. tail length)
            let span1 = tipU - b1U
            c1_local = CGPoint(x: b1U + span1 * 0.22, y: tipV * 0.16)
            c2_local = CGPoint(x: tipU - span1 * 0.28, y: tipV * 0.82)

            let span2 = tipU - b2U
            c3_local = CGPoint(x: tipU - span2 * 0.28 + 6.0, y: tipV * 0.86)
            c4_local = CGPoint(x: b2U + fillet * 1.6, y: min(fillet, tipV * 0.25))
        } else if tipU < b1U {
            // Backward pull (tip behind base in traversal dir, e.g. tail orientation top)
            let span1 = b1U - tipU
            c1_local = CGPoint(x: b1U - fillet * 1.6, y: min(fillet, tipV * 0.25))
            c2_local = CGPoint(x: tipU + span1 * 0.28 - 6.0, y: tipV * 0.86)

            let span2 = b2U - tipU
            c3_local = CGPoint(x: tipU + span2 * 0.28, y: tipV * 0.82)
            c4_local = CGPoint(x: b2U - span2 * 0.22, y: tipV * 0.16)
        } else {
            // Centered tip (e.g. one line, multiline)
            let leftSpan = max(2.0, tipU - b1U)
            let rightSpan = max(2.0, b2U - tipU)

            c1_local = CGPoint(x: b1U + leftSpan * 0.25, y: min(tipV * 0.35, fillet * 1.2))
            c2_local = CGPoint(x: tipU - leftSpan * 0.20, y: tipV * 0.82)

            c3_local = CGPoint(x: tipU + rightSpan * 0.20, y: tipV * 0.82)
            c4_local = CGPoint(x: b2U - rightSpan * 0.25, y: min(tipV * 0.35, fillet * 1.2))
        }

        let c1 = toCanvas(u: c1_local.x, v: c1_local.y)
        let c2 = toCanvas(u: c2_local.x, v: c2_local.y)
        let c3 = toCanvas(u: c3_local.x, v: c3_local.y)
        let c4 = toCanvas(u: c4_local.x, v: c4_local.y)

        let path = CGMutablePath()
        path.addRoundedRect(in: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius)

        let tailPath = CGMutablePath()
        tailPath.move(to: pB1)
        tailPath.addCurve(to: pTip, control1: c1, control2: c2)
        tailPath.addCurve(to: pB2, control1: c3, control2: c4)
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
