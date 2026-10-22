import Foundation
import CoreGraphics
import AppKit

public final class CalloutLayer: AnnotationLayer {
    public let id: UUID
    public let type: LayerType = .callout
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String {
        didSet { _cachedFillColor = nil }
    }
    public var strokeWidth: CGFloat // Protocol requirement, unused

    /// May be whitespace-only; the body size always follows the text, re-anchored so the beak stays put
    public var text: String {
        didSet {
            guard text != oldValue else { return }
            let oldFrame = CGRect(origin: origin, size: _cachedBodySize ?? CalloutLayer.bodySize(for: oldValue))
            _cachedBodySize = nil
            invalidateGeometry()
            reanchorBody(from: oldFrame)
        }
    }
    /// Body top-left corner in canvas coordinates
    public var origin: CGPoint {
        didSet { invalidateGeometry() }
    }
    /// Beak tip: the single draggable handle (index 0)
    public var tailTip: CGPoint {
        didSet { invalidateGeometry() }
    }
    /// True while the in-place editor draws the text
    public var isTextHidden: Bool = false

    // Beak geometry constants (compact style)
    static let minBeakLength: CGFloat = 8.0
    static let minBaseWidth: CGFloat = 16.0
    static let defaultBaseWidth: CGFloat = 18.0 // fixed beak base; never derived from the body size
    static let baseGrowth: CGFloat = 0.2 // k: base widening per point of beak length beyond the default gap
    static let cornerClearance: CGFloat = 2.0
    static let maxFillet: CGFloat = 6.0
    static let tipCapRadius: CGFloat = 1.5
    static let defaultTipGap: CGFloat = 9.0
    private static let darkTextColor = NSColor(srgbRed: 0x1E / 255.0, green: 0x27 / 255.0, blue: 0x2E / 255.0, alpha: 1.0)

    private var _cachedBodySize: CGSize?
    private var _cachedPath: CGPath?
    private var _cachedHitPath: CGPath?
    private var _cachedBoundingBox: CGRect?
    private var _cachedFillColor: CGColor?

    @inline(__always)
    private func invalidateGeometry() {
        _cachedPath = nil
        _cachedHitPath = nil
        _cachedBoundingBox = nil
    }

    public init(
        id: UUID = UUID(),
        text: String,
        origin: CGPoint,
        tailTip: CGPoint,
        color: String = "#FF3B30",
        strokeWidth: CGFloat = 2.0,
        zIndex: Int = 0
    ) {
        self.id = id
        self.text = text
        self.origin = origin
        self.tailTip = tailTip
        self.color = color
        self.strokeWidth = strokeWidth
        self.zIndex = zIndex
    }

    /// Places the body centered above `tip` with a short default beak hanging from the bottom edge
    public convenience init(tip: CGPoint, color: String = "#FF3B30", text: String = "") {
        let size = CalloutLayer.bodySize(for: text)
        let origin = CGPoint(x: tip.x - size.width / 2.0, y: tip.y - CalloutLayer.defaultTipGap - size.height)
        self.init(text: text, origin: origin, tailTip: tip, color: color)
    }

    /// Empty text measures one line tall, so a new callout already has its final single-line height
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
            let s = CalloutLayer.bodySize(for: text)
            _cachedBodySize = s
            return s
        }()
        return CGRect(origin: origin, size: size)
    }

    /// White, except dark on the white swatch where white text would vanish
    public var textColor: NSColor {
        color.uppercased() == "#FFFFFF" ? CalloutLayer.darkTextColor : .white
    }

    // MARK: - Body + Beak Outline

    private enum Edge: Int {
        case top = 0, right, bottom, left
    }

    private struct BeakGeometry {
        let edge: Edge
        let corners: [CGPoint]
        let edgeOrigin: CGPoint
        let edgeDir: CGPoint
        let edgeNormal: CGPoint
        let edgeLength: CGFloat
        let radius: CGFloat
        let tipU: CGFloat
        let tipV: CGFloat
        let base: CGFloat
        let centerU: CGFloat

        /// Beak base center in canvas coordinates
        var baseCenter: CGPoint {
            CGPoint(x: edgeOrigin.x + edgeDir.x * centerU, y: edgeOrigin.y + edgeDir.y * centerU)
        }
    }

    /// Where the beak attaches to `frame`: the edge facing the tip and the clamped base along it
    private func beakGeometry(in frame: CGRect) -> BeakGeometry {
        let radius = max(0.0, min(CalloutTextLayout.cornerRadius, min(frame.width / 2.0, frame.height / 2.0)))
        let dx = tailTip.x - frame.midX
        let dy = tailTip.y - frame.midY

        // Edge snapping: the side facing the tip
        let edge: Edge
        if abs(dx) * frame.height > abs(dy) * frame.width {
            edge = dx > 0 ? .right : .left
        } else {
            edge = dy > 0 ? .bottom : .top
        }

        // Clockwise corners (y-down): each edge runs from corners[i] to corners[i + 1]
        let corners = [
            CGPoint(x: frame.minX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.maxY),
            CGPoint(x: frame.minX, y: frame.maxY)
        ]
        let edgeOrigin = corners[edge.rawValue]
        let edgeEnd = corners[(edge.rawValue + 1) % 4]
        let edgeLength = hypot(edgeEnd.x - edgeOrigin.x, edgeEnd.y - edgeOrigin.y)
        let edgeDir = CGPoint(x: (edgeEnd.x - edgeOrigin.x) / edgeLength, y: (edgeEnd.y - edgeOrigin.y) / edgeLength)
        // Outward normal of a clockwise y-down contour
        let edgeNormal = CGPoint(x: edgeDir.y, y: -edgeDir.x)

        let relTip = CGPoint(x: tailTip.x - edgeOrigin.x, y: tailTip.y - edgeOrigin.y)
        let tipU = relTip.x * edgeDir.x + relTip.y * edgeDir.y
        let tipV = max(CalloutLayer.minBeakLength, relTip.x * edgeNormal.x + relTip.y * edgeNormal.y)

        // Corner exclusion: the beak never touches a rounded corner
        let inset = radius + CalloutLayer.cornerClearance
        let flatLength = max(4.0, edgeLength - 2.0 * inset)
        // Same beak at any body size: only dragging the tip further out widens it
        let growth = CalloutLayer.baseGrowth * max(0.0, tipV - CalloutLayer.defaultTipGap)
        let base = min(flatLength, max(CalloutLayer.minBaseWidth, CalloutLayer.defaultBaseWidth + growth))
        let halfBase = base / 2.0
        let centerU = min(max(tipU, inset + halfBase), edgeLength - inset - halfBase)
        return BeakGeometry(
            edge: edge, corners: corners, edgeOrigin: edgeOrigin, edgeDir: edgeDir, edgeNormal: edgeNormal,
            edgeLength: edgeLength, radius: radius, tipU: tipU, tipV: tipV, base: base, centerU: centerU
        )
    }

    /// After a text change, keeps the beak's edge at its outer position and the beak base at the same
    /// fraction along that edge on the same canvas point; the body grows away from the tip, which never moves.
    private func reanchorBody(from oldFrame: CGRect) {
        let size = bodyRect.size
        let anchor = beakGeometry(in: oldFrame)
        let center = anchor.baseCenter
        var newOrigin = origin
        switch anchor.edge {
        case .top, .bottom:
            let t = (center.x - oldFrame.minX) / oldFrame.width
            newOrigin.x = center.x - t * size.width
            newOrigin.y = anchor.edge == .bottom ? oldFrame.maxY - size.height : oldFrame.minY
        case .left, .right:
            let t = (center.y - oldFrame.minY) / oldFrame.height
            newOrigin.y = center.y - t * size.height
            newOrigin.x = anchor.edge == .right ? oldFrame.maxX - size.width : oldFrame.minX
        }
        if newOrigin != origin {
            origin = newOrigin
        }
    }

    /// One closed contour: rounded body with the beak spliced into the edge facing the tip,
    /// so fills, hover strokes and selection outlines never show a seam.
    public func pathForCallout() -> CGPath {
        if let cached = _cachedPath { return cached }

        let frame = bodyRect
        let g = beakGeometry(in: frame)
        let edge = g.edge, corners = g.corners, edgeOrigin = g.edgeOrigin, edgeDir = g.edgeDir, edgeNormal = g.edgeNormal
        let edgeLength = g.edgeLength, radius = g.radius, tipU = g.tipU, tipV = g.tipV
        let base = g.base, halfBase = base / 2.0, centerU = g.centerU

        // Edge-local frame: u along the edge, v outward
        func toCanvas(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(
                x: edgeOrigin.x + edgeDir.x * u + edgeNormal.x * v,
                y: edgeOrigin.y + edgeDir.y * u + edgeNormal.y * v
            )
        }

        let b1 = centerU - halfBase
        let b2 = centerU + halfBase
        // Concave shoulders, kept off the corner arcs
        let fillet = max(0.0, min(CalloutLayer.maxFillet, 0.25 * base, b1 - radius, edgeLength - radius - b2))
        let s1 = b1 - fillet
        let s2 = b2 + fillet

        // Round tip cap perpendicular to the beak axis (base center → tip)
        let axisU = tipU - centerU
        let axisLen = max(0.001, hypot(axisU, tipV))
        let axis = CGPoint(x: axisU / axisLen, y: tipV / axisLen)
        let capPerp = CGPoint(x: -axis.y, y: axis.x) // points toward decreasing u (the b1 side)
        let capR = CalloutLayer.tipCapRadius
        let t1 = CGPoint(x: tipU + capPerp.x * capR, y: tipV + capPerp.y * capR)
        let t2 = CGPoint(x: tipU - capPerp.x * capR, y: tipV - capPerp.y * capR)

        // Shoulder control points hug the edge (tangent-continuous fillet); the side trailing the tip
        // hugs longer so long tails sweep out of the body. Three cases: tip ahead of, behind, or within the base.
        let lead1: CGFloat
        let lead2: CGFloat
        if tipU > b2 {
            lead1 = fillet + min(base, 0.22 * (tipU - b1))
            lead2 = fillet
        } else if tipU < b1 {
            lead1 = fillet
            lead2 = fillet + min(base, 0.22 * (b2 - tipU))
        } else {
            lead1 = fillet + 0.25 * (tipU - b1)
            lead2 = fillet + 0.25 * (b2 - tipU)
        }
        // Tip-side control points sit on the base-to-tip chords, keeping the taper straight near the tip
        let chordPull: CGFloat = 0.4
        let c1 = CGPoint(x: s1 + lead1, y: 0)
        let c2 = CGPoint(x: t1.x + (b1 - t1.x) * chordPull, y: t1.y - t1.y * chordPull)
        let c3 = CGPoint(x: t2.x + (b2 - t2.x) * chordPull, y: t2.y - t2.y * chordPull)
        let c4 = CGPoint(x: s2 - lead2, y: 0)

        let path = CGMutablePath()
        path.move(to: toCanvas(radius, 0))
        path.addLine(to: toCanvas(s1, 0))
        path.addCurve(to: toCanvas(t1.x, t1.y), control1: toCanvas(c1.x, c1.y), control2: toCanvas(c2.x, c2.y))
        let capSteps = 8
        for i in 1...capSteps {
            let a = CGFloat(i) / CGFloat(capSteps) * .pi
            let pu = tipU + capR * (cos(a) * capPerp.x + sin(a) * axis.x)
            let pv = tipV + capR * (cos(a) * capPerp.y + sin(a) * axis.y)
            path.addLine(to: toCanvas(pu, pv))
        }
        path.addCurve(to: toCanvas(s2, 0), control1: toCanvas(c3.x, c3.y), control2: toCanvas(c4.x, c4.y))
        // Remaining body outline: four rounded corners back to the start
        for i in 1...4 {
            path.addArc(tangent1End: corners[(edge.rawValue + i) % 4], tangent2End: corners[(edge.rawValue + i + 1) % 4], radius: radius)
        }
        path.closeSubpath()

        _cachedPath = path
        return path
    }

    // MARK: - AnnotationLayer

    public func getBoundingBox() -> CGRect {
        if let cached = _cachedBoundingBox { return cached }
        // Shadow margin around the outline
        let box = pathForCallout().boundingBoxOfPath.insetBy(dx: -4.0, dy: -4.0)
        _cachedBoundingBox = box
        return box
    }

    public func contains(point: CGPoint) -> Bool {
        if bodyRect.contains(point) { return true }
        guard getBoundingBox().insetBy(dx: -4.0, dy: -4.0).contains(point) else { return false }
        // A few points of tolerance so thin tails stay grabbable
        let hitPath = _cachedHitPath ?? {
            let p = pathForCallout().copy(strokingWithWidth: 8.0, lineCap: .round, lineJoin: .round, miterLimit: 10.0)
            _cachedHitPath = p
            return p
        }()
        return pathForCallout().contains(point) || hitPath.contains(point)
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        let hitRadius = max(radius, 10.0)
        let dx = point.x - tailTip.x
        let dy = point.y - tailTip.y
        if dx * dx + dy * dy <= hitRadius * hitRadius {
            return 0
        }
        return nil
    }

    public func move(by delta: CGPoint) {
        origin.x += delta.x
        origin.y += delta.y
        tailTip.x += delta.x
        tailTip.y += delta.y
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        guard index == 0 else { return }
        let frame = bodyRect
        guard frame.contains(point) else {
            tailTip = point
            return
        }
        // A tip inside the body is pushed out past the nearest edge
        let gap = CalloutLayer.minBeakLength
        let toLeft = point.x - frame.minX
        let toRight = frame.maxX - point.x
        let toTop = point.y - frame.minY
        let toBottom = frame.maxY - point.y
        let nearest = min(toLeft, toRight, toTop, toBottom)
        if nearest == toBottom {
            tailTip = CGPoint(x: point.x, y: frame.maxY + gap)
        } else if nearest == toTop {
            tailTip = CGPoint(x: point.x, y: frame.minY - gap)
        } else if nearest == toLeft {
            tailTip = CGPoint(x: frame.minX - gap, y: point.y)
        } else {
            tailTip = CGPoint(x: frame.maxX + gap, y: point.y)
        }
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        let fillColor = _cachedFillColor ?? {
            let c = FastColor.shared.cgColor(hex: color)
            _cachedFillColor = c
            return c
        }()
        context.setFillColor(fillColor)
        context.setShadow(offset: CGSize(width: 0, height: -1.0), blur: 2.5, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        context.addPath(pathForCallout())
        context.fillPath()

        // Remove shadow before drawing text so it stays crisp
        context.setShadow(offset: .zero, blur: 0, color: nil)

        if !isTextHidden {
            let pad = CalloutTextLayout.padding
            let frame = bodyRect
            CalloutTextLayout.draw(text, color: textColor, at: CGPoint(x: frame.minX + pad.left, y: frame.minY + pad.top), in: context)
        }

        context.restoreGState()
    }

    public func clone(withID newID: UUID) -> AnnotationLayer {
        let copy = CalloutLayer(
            id: newID,
            text: text,
            origin: origin,
            tailTip: tailTip,
            color: color,
            strokeWidth: strokeWidth,
            zIndex: zIndex
        )
        copy.isVisible = isVisible
        return copy
    }
}
