import AppKit
import CoreGraphics

// MARK: - Pixel Sampling

/// The pixels around one image pixel, read in sRGB so the hex matches what the screenshot showed
public struct PixelSample: Equatable {
    /// `columns` x `rows` pixels centered on the sampled pixel; areas outside the image are transparent
    public let patch: CGImage
    /// "#RRGGBB" of the center pixel, or nil when it lies outside the image or is fully transparent
    public let hex: String?

    public static func == (lhs: PixelSample, rhs: PixelSample) -> Bool {
        lhs.hex == rhs.hex && lhs.patch === rhs.patch
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Samples `image` around pixel (`x`, `y`) (top-left origin). Only the small neighborhood is cropped and
    /// color-converted, so this stays cheap on every mouse move even for very large images.
    public static func sample(_ image: CGImage, x: Int, y: Int, columns: Int, rows: Int) -> PixelSample? {
        guard columns > 0, rows > 0 else { return nil }
        let bytesPerRow = columns * 4
        guard let ctx = CGContext(
            data: nil,
            width: columns,
            height: rows,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .none
        ctx.clear(CGRect(x: 0, y: 0, width: columns, height: rows))

        // Region in image pixels (top-left origin, like CGImage.cropping)
        let region = CGRect(x: x - columns / 2, y: y - rows / 2, width: columns, height: rows)
        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let visible = region.intersection(imageRect)
        if !visible.isNull, !visible.isEmpty, let crop = image.cropping(to: visible) {
            // The bitmap context has a bottom-left origin
            let localX = visible.minX - region.minX
            let localTop = visible.minY - region.minY
            let drawY = CGFloat(rows) - localTop - visible.height
            ctx.draw(crop, in: CGRect(x: localX, y: drawY, width: visible.width, height: visible.height))
        }
        guard let patch = ctx.makeImage() else { return nil }

        var hex: String?
        let centerInside = x >= 0 && y >= 0 && x < image.width && y < image.height
        if centerInside, let data = ctx.data {
            // Bitmap memory starts with the top row
            let offset = (rows / 2) * bytesPerRow + (columns / 2) * 4
            let px = data.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
            let a = Int(px[3])
            if a > 0 {
                func unpremultiply(_ c: UInt8) -> Int { a == 255 ? Int(c) : min(255, (Int(c) * 255 + a / 2) / a) }
                hex = String(format: "#%02X%02X%02X", unpremultiply(px[0]), unpremultiply(px[1]), unpremultiply(px[2]))
            }
        }
        return PixelSample(patch: patch, hex: hex)
    }
}

// MARK: - Pixel Loupe

/// Magnified, unsmoothed view of the pixels under the pointer with the picked pixel outlined
final class PixelLoupeView: NSView {
    let columns: Int
    let rows: Int
    let cellSize: CGFloat

    var patch: CGImage? {
        didSet { if patch !== oldValue { needsDisplay = true } }
    }

    init(columns: Int, rows: Int, cellSize: CGFloat) {
        self.columns = columns
        self.rows = rows
        self.cellSize = cellSize
        super.init(frame: NSRect(x: 0, y: 0, width: CGFloat(columns) * cellSize, height: CGFloat(rows) * cellSize))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: CGFloat(columns) * cellSize),
            heightAnchor.constraint(equalToConstant: CGFloat(rows) * cellSize)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.clip()

        // Outside the image: the canvas surround color
        ctx.setFillColor(resolvedCGColor(ImpactTheme.canvasSurround))
        ctx.fill(rect)

        if let patch = patch {
            ctx.interpolationQuality = .none
            ctx.draw(patch, in: rect)
        }

        // Faint pixel grid
        ctx.setStrokeColor(NSColor(white: 0.0, alpha: 0.12).cgColor)
        ctx.setLineWidth(0.5)
        for c in 1..<columns {
            let x = CGFloat(c) * cellSize
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: rect.height))
        }
        for r in 1..<rows {
            let y = CGFloat(r) * cellSize
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: rect.width, y: y))
        }
        ctx.strokePath()

        // The picked pixel: black outside, white inside, visible on any color
        let center = CGRect(x: CGFloat(columns / 2) * cellSize, y: CGFloat(rows / 2) * cellSize, width: cellSize, height: cellSize)
        ctx.setLineWidth(1.0)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        ctx.stroke(center.insetBy(dx: -0.5, dy: -0.5))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.stroke(center.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()

        // Hairline border so the loupe stays visible on the toolbar
        ctx.setStrokeColor(resolvedCGColor(ImpactTheme.swatchBorder))
        ctx.setLineWidth(1.0)
        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 4.5, cornerHeight: 4.5, transform: nil))
        ctx.strokePath()
    }
}

// MARK: - Color Picker Readout (in Toolbar)

/// Always-on color picker: a loupe of the image under the pointer, the picked color's swatch, its hex and
/// a "tab to copy" hint. Tab on the canvas or a click on the readout copies the hex.
public final class ColorPickerReadoutView: NSView {
    public static let columns = 5
    public static let rows = 5
    public static let cellSize: CGFloat = 6.0
    static let labelColumnWidth: CGFloat = 56.0

    /// Hex of the pixel under the pointer; nil until the pointer has been over the image
    public private(set) var hex: String?
    public var onCopyRequested: (() -> Void)?

    let loupeView = PixelLoupeView(columns: ColorPickerReadoutView.columns, rows: ColorPickerReadoutView.rows, cellSize: ColorPickerReadoutView.cellSize)
    private let swatchView = NSView()
    let hexLabel = NSTextField(labelWithString: "—")
    let hintLabel = NSTextField(labelWithString: "tab to copy")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { updateVisuals() } }

    public static var preferredWidth: CGFloat {
        CGFloat(columns) * cellSize + 8 + 18 + 6 + labelColumnWidth + 4
    }
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6.0
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = "Color under the pointer. Press Tab or click to copy its hex."

        addSubview(loupeView)

        swatchView.wantsLayer = true
        swatchView.layer?.cornerRadius = 5.0
        swatchView.layer?.masksToBounds = true
        swatchView.layer?.borderWidth = 1.0
        swatchView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swatchView)

        hexLabel.font = NSFont.monospacedSystemFont(ofSize: 11.0, weight: .semibold)
        hexLabel.textColor = ImpactTheme.toolbarForegroundStrong
        hexLabel.lineBreakMode = .byClipping
        hexLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hexLabel)

        hintLabel.font = NSFont.systemFont(ofSize: 9.0, weight: .medium)
        hintLabel.textColor = ImpactTheme.toolbarForeground
        hintLabel.lineBreakMode = .byClipping
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.preferredWidth),
            heightAnchor.constraint(equalToConstant: 30),

            loupeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            loupeView.centerYAnchor.constraint(equalTo: centerYAnchor),

            swatchView.leadingAnchor.constraint(equalTo: loupeView.trailingAnchor, constant: 8),
            swatchView.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatchView.widthAnchor.constraint(equalToConstant: 18),
            swatchView.heightAnchor.constraint(equalToConstant: 18),

            hexLabel.leadingAnchor.constraint(equalTo: swatchView.trailingAnchor, constant: 6),
            hexLabel.widthAnchor.constraint(equalToConstant: Self.labelColumnWidth),
            hexLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),

            hintLabel.leadingAnchor.constraint(equalTo: hexLabel.leadingAnchor),
            hintLabel.widthAnchor.constraint(equalToConstant: Self.labelColumnWidth),
            hintLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 0)
        ])
        updateVisuals()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows the pixels of `image` around image pixel (`x`, `y`)
    public func showSample(of image: CGImage, x: Int, y: Int) {
        guard let sample = PixelSample.sample(image, x: x, y: y, columns: Self.columns, rows: Self.rows) else { return }
        loupeView.patch = sample.patch
        if sample.hex != hex {
            hex = sample.hex
            updateVisuals()
        }
    }

    private func updateVisuals() {
        hexLabel.stringValue = hex ?? "—"
        hintLabel.alphaValue = hex == nil ? 0.45 : 1.0
        swatchView.layer?.backgroundColor = hex.map { NSColor(hex: $0).cgColor } ?? NSColor.clear.cgColor
        swatchView.layer?.borderColor = resolvedCGColor(ImpactTheme.swatchBorder)
        layer?.backgroundColor = isHovered && hex != nil ? resolvedCGColor(ImpactTheme.hoverFill) : NSColor.clear.cgColor
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateVisuals()
    }

    override public var mouseDownCanMoveWindow: Bool { false }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) { isHovered = true }
    override public func mouseExited(with event: NSEvent) { isHovered = false }
    override public func mouseDown(with event: NSEvent) {}

    override public func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onCopyRequested?()
    }
}
