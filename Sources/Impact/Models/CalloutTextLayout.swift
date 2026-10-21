import Foundation
import CoreGraphics
import AppKit

/// Single TextKit 1 configuration shared by callout measuring, drawing and the in-place editor,
/// so text never shifts between editing and rendering.
public enum CalloutTextLayout {
    public static let font = NSFont.systemFont(ofSize: 16, weight: .bold)
    public static let padding = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
    public static let cornerRadius: CGFloat = 5
    /// Keeps " " and "\n" callouts visible and wide enough for the full default beak
    public static let minTextWidth: CGFloat = 14

    // Unbounded, non-wrapping container: lines only break at Return
    private static let unboundedSize = CGSize(width: 10_000_000, height: 10_000_000)

    private static let textStorage = NSTextStorage()
    private static let layoutManager: NSLayoutManager = {
        let manager = NSLayoutManager()
        textStorage.addLayoutManager(manager)
        manager.addTextContainer(textContainer)
        return manager
    }()
    private static let textContainer: NSTextContainer = {
        let container = NSTextContainer(size: unboundedSize)
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        return container
    }()

    private static func layOut(_ text: String, color: NSColor) -> NSRange {
        textStorage.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color
        ]))
        layoutManager.ensureLayout(for: textContainer)
        return layoutManager.glyphRange(for: textContainer)
    }

    /// Text size as the layout manager lays it out: widest line fragment (trailing spaces included),
    /// used-rect height (including the extra line after a trailing "\n").
    public static func textSize(for text: String) -> CGSize {
        let glyphRange = layOut(text, color: .white)
        var width: CGFloat = 0
        // usedRect.width becomes the container width after a trailing "\n", so measure per fragment
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            width = max(width, usedRect.width)
        }
        let height = layoutManager.usedRect(for: textContainer).height
        return CGSize(width: width, height: height)
    }

    /// Draws text with its first line fragment's top-left at `origin`, in a flipped canvas context
    public static func draw(_ text: String, color: NSColor, at origin: CGPoint, in ctx: CGContext) {
        guard !text.isEmpty else { return }
        let glyphRange = layOut(text, color: color)

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Applies the same font, zero fragment padding, padding inset and unbounded container to an editor.
    /// The editor's frame is owned by the caller (it tracks the callout body), so the view never self-resizes:
    /// with an unbounded container, self-sizing would stretch it to the container width after a trailing "\n".
    public static func configure(_ textView: NSTextView) {
        textView.font = font
        textView.textContainerInset = NSSize(width: padding.left, height: padding.top)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        if let container = textView.textContainer {
            container.lineFragmentPadding = 0
            container.widthTracksTextView = false
            container.heightTracksTextView = false
            container.containerSize = unboundedSize
        }
    }
}
