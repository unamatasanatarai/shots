import Foundation
import AppKit

/// The owner of an in-place callout editing session (implemented by EditorCanvasView)
protocol CalloutEditingSession: AnyObject {
    func endCalloutEditing()
    func revertCalloutSession()
}

/// Transparent text view laid exactly over a callout body while its text is edited.
/// Uses the shared CalloutTextLayout configuration so text never shifts when editing ends.
final class CalloutTextView: NSTextView {
    weak var session: CalloutEditingSession?

    // A manually built TextKit 1 stack is not owned by the view, so keep the storage alive here
    private let calloutTextStorage: NSTextStorage

    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: .zero)
        layoutManager.addTextContainer(container)
        calloutTextStorage = storage
        super.init(frame: .zero, textContainer: container)

        CalloutTextLayout.configure(self)
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = false
        usesFontPanel = false
        usesRuler = false
        usesFindBar = false
        focusRingType = .none
        smartInsertDeleteEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        calloutTextStorage = container?.layoutManager?.textStorage ?? NSTextStorage()
        super.init(frame: frameRect, textContainer: container)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Text, caret and selection follow the callout's text color (white, or dark on the white swatch)
    func apply(textColor color: NSColor) {
        textColor = color
        insertionPointColor = color
        selectedTextAttributes = [.backgroundColor: color.withAlphaComponent(0.35)]
        typingAttributes = [.font: CalloutTextLayout.font, .foregroundColor: color]
    }

    // The app has no Edit menu, so standard editing shortcuts are mapped here
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Key equivalents are offered to every view in the window; only the focused editor acts on them
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else {
            return super.performKeyEquivalent(with: event)
        }
        let key = (event.charactersIgnoringModifiers ?? "").lowercased()
        let isShift = flags.contains(.shift)

        switch key {
        case "c" where !isShift:
            copy(nil)
            return true
        case "x" where !isShift:
            cut(nil)
            return true
        case "v" where !isShift:
            pasteAsPlainText(nil)
            return true
        case "a" where !isShift:
            selectAll(nil)
            return true
        case "z":
            // No keystroke undo: ⌘Z takes back the whole session, ⇧⌘Z has nothing to redo
            if !isShift {
                session?.revertCalloutSession()
            }
            return true
        case "=", "+", "-", "_", "0", "1", "o":
            // Zoom and open keep working while typing
            if let panel = window as? EditorPanel {
                panel.keyDown(with: event)
                return true
            }
            return super.performKeyEquivalent(with: event)
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}
