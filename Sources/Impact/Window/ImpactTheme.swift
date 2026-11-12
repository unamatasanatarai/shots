import AppKit

/// Impact's UI colors for light and dark mode. Text/tint colors adapt by themselves; layer colors (CGColor)
/// are resolved once, so views re-apply them via `resolvedCGColor` in `viewDidChangeEffectiveAppearance`.
public enum ImpactTheme {
    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { isDark($0) ? dark : light }
    }

    // MARK: Toolbar
    /// Idle icons and labels
    static let toolbarForeground = dynamic(light: NSColor(white: 0.24, alpha: 1.0), dark: NSColor(white: 0.82, alpha: 1.0))
    /// Hovered/pressed icons and labels
    static let toolbarForegroundStrong = dynamic(light: NSColor(white: 0.05, alpha: 1.0), dark: .white)
    static let hoverFill = dynamic(light: NSColor(white: 0.0, alpha: 0.07), dark: NSColor(white: 1.0, alpha: 0.14))
    static let pressedFill = dynamic(light: NSColor(white: 0.0, alpha: 0.13), dark: NSColor(white: 1.0, alpha: 0.22))
    static let hoverBorder = dynamic(light: NSColor(white: 0.0, alpha: 0.08), dark: NSColor(white: 1.0, alpha: 0.12))
    static let activeBorder = dynamic(light: NSColor(white: 0.0, alpha: 0.10), dark: NSColor(white: 1.0, alpha: 0.20))
    static let separator = dynamic(light: NSColor(white: 0.0, alpha: 0.13), dark: NSColor(white: 1.0, alpha: 0.13))
    static let popoverBackground = dynamic(light: NSColor(white: 0.97, alpha: 0.98), dark: NSColor(white: 0.16, alpha: 0.98))
    /// Outline around color swatches so light/dark swatches stay visible on the toolbar
    static let swatchBorder = dynamic(light: NSColor(white: 0.0, alpha: 0.18), dark: NSColor(white: 1.0, alpha: 0.20))
    static let swatchHoverRing = dynamic(light: NSColor(white: 0.0, alpha: 0.25), dark: NSColor(white: 1.0, alpha: 0.40))
    static let whiteSwatchActiveRing = dynamic(light: NSColor(white: 0.55, alpha: 0.95), dark: NSColor(white: 0.85, alpha: 0.95))

    // MARK: Window
    static let windowBackground = dynamic(light: NSColor(white: 0.93, alpha: 0.98), dark: NSColor(white: 0.14, alpha: 0.98))
    /// Area around the image
    static let canvasSurround = dynamic(light: NSColor(white: 0.86, alpha: 1.0), dark: NSColor(white: 0.10, alpha: 1.0))

    // MARK: Welcome / empty state
    static let welcomeIcon = dynamic(light: NSColor(white: 0.30, alpha: 1.0), dark: NSColor(white: 0.80, alpha: 1.0))
    static let welcomeIconHover = dynamic(light: NSColor(white: 0.08, alpha: 1.0), dark: .white)
    static let welcomeTitle = dynamic(light: NSColor(white: 0.10, alpha: 1.0), dark: .white)
    static let welcomeSubtitle = dynamic(light: NSColor(white: 0.38, alpha: 1.0), dark: NSColor(white: 0.65, alpha: 1.0))
    static let welcomeFootnote = dynamic(light: NSColor(white: 0.52, alpha: 1.0), dark: NSColor(white: 0.42, alpha: 1.0))
    static let dropZoneFill = dynamic(light: NSColor(white: 1.0, alpha: 0.55), dark: NSColor(white: 0.13, alpha: 0.70))
    static let dropZoneFillHover = dynamic(light: NSColor(white: 1.0, alpha: 0.85), dark: NSColor(white: 0.15, alpha: 0.85))
    static let dropZoneStroke = dynamic(light: NSColor(white: 0.0, alpha: 0.20), dark: NSColor(white: 0.25, alpha: 0.70))
    static let dropZoneStrokeHover = dynamic(light: NSColor(white: 0.0, alpha: 0.35), dark: NSColor(white: 0.40, alpha: 0.85))
    static let pillFill = dynamic(light: .white, dark: NSColor(white: 0.22, alpha: 0.90))
    static let pillBorder = dynamic(light: NSColor(white: 0.0, alpha: 0.14), dark: NSColor(white: 1.0, alpha: 0.15))
    static let pillForeground = dynamic(light: NSColor(white: 0.12, alpha: 1.0), dark: NSColor(white: 0.90, alpha: 1.0))

    // MARK: Toast / HUD Popout
    static let toastBackground = dynamic(light: NSColor(white: 0.98, alpha: 0.92), dark: NSColor(white: 0.16, alpha: 0.88))
    static let toastBorder = dynamic(light: NSColor(white: 0.0, alpha: 0.14), dark: NSColor(white: 1.0, alpha: 0.18))
    static let toastForeground = dynamic(light: NSColor(white: 0.10, alpha: 1.0), dark: NSColor(white: 0.96, alpha: 1.0))
}

extension NSView {
    /// `color` as a CGColor for this view's current appearance (light or dark)
    func resolvedCGColor(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }
}

extension NSVisualEffectView {
    /// Styles a HUD pill (toast, ⌘Q prompt). The blur material is clipped to the rounded shape via
    /// `maskImage` + `masksToBounds`; without both, AppKit draws the material as a full rectangle behind the pill.
    func applyToastPillStyle(cornerRadius: CGFloat = 16) {
        material = .hudWindow
        state = .active
        blendingMode = .withinWindow
        wantsLayer = true
        maskImage = NSVisualEffectView.roundedMask(cornerRadius: cornerRadius)
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1.0
        refreshToastPillColors()
    }

    /// Re-resolves the dynamic layer colors; call from `viewDidChangeEffectiveAppearance`.
    func refreshToastPillColors() {
        layer?.backgroundColor = resolvedCGColor(ImpactTheme.toastBackground)
        layer?.borderColor = resolvedCGColor(ImpactTheme.toastBorder)
    }

    private static func roundedMask(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}

/// A plain layer-backed view (separator, capsule, background) whose fill/border follow light and dark mode
final class ThemedLayerView: NSView {
    var fillColor: NSColor? { didSet { applyColors() } }
    var borderColor: NSColor? { didSet { applyColors() } }

    init(fill: NSColor? = nil, border: NSColor? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        fillColor = fill
        borderColor = border
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        layer?.backgroundColor = fillColor.map { resolvedCGColor($0) }
        layer?.borderColor = borderColor.map { resolvedCGColor($0) }
    }
}
