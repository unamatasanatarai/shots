import Foundation

/// App-wide, in-memory clipboard for annotations (⌘C / ⌘X / ⌘V), shared by every editor window.
/// It never touches the macOS pasteboard and nothing in it outlives the app.
public final class AnnotationClipboard {
    public static let shared = AnnotationClipboard()

    /// Snapshots of the copied layers in stacking order (their ids are replaced on every paste)
    public private(set) var layers: [AnnotationLayer] = []
    /// Pastes made since the last copy or cut; each one lands another offset step further
    public private(set) var pasteCount: Int = 0

    public init() {}

    public var isEmpty: Bool { layers.isEmpty }

    /// Replaces the contents and starts the paste cascade over
    public func store(_ source: [AnnotationLayer]) {
        layers = source.map { $0.clone() }
        pasteCount = 0
    }

    /// The stored layers and their cascade step (1 for the first paste), or nil when nothing was copied
    public func nextPaste() -> (layers: [AnnotationLayer], step: Int)? {
        guard !layers.isEmpty else { return nil }
        pasteCount += 1
        return (layers, pasteCount)
    }
}
