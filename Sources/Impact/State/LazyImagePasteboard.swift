import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Puts an image on the pasteboard as promised PNG and TIFF data: nothing is rendered or encoded
/// until an app actually pastes, and the uncompressed TIFF never lands in the pasteboard unless asked for.
public final class LazyImagePasteboard: NSObject, NSPasteboardItemDataProvider {
    /// The provider backing the current pasteboard contents (kept alive until the pasteboard lets go of it)
    private static var current: LazyImagePasteboard?
    // Recursive: clearing the pasteboard can call back into pasteboardFinishedWithDataProvider
    private static let lock = NSRecursiveLock()

    private let lock = NSLock()
    private let makeImage: () -> CGImage?
    private var image: CGImage?
    private var pngData: Data?
    private var changeCount = 0

    private init(makeImage: @escaping () -> CGImage?, pngData: Data?) {
        self.makeImage = makeImage
        self.pngData = pngData
    }

    /// Writes the promise to the general pasteboard. `makeImage` runs at most once, on the first paste;
    /// already encoded PNG data is put on the pasteboard as is.
    public static func write(pngData: Data? = nil, makeImage: @escaping () -> CGImage?) {
        let provider = LazyImagePasteboard(makeImage: makeImage, pngData: pngData)
        let item = NSPasteboardItem()
        if let data = pngData {
            item.setData(data, forType: .png)
            item.setDataProvider(provider, forTypes: [.tiff])
        } else {
            item.setDataProvider(provider, forTypes: [.png, .tiff])
        }

        let pb = NSPasteboard.general
        lock.lock()
        defer { lock.unlock() }
        pb.clearContents()
        pb.writeObjects([item])
        provider.changeCount = pb.changeCount
        current = provider
    }

    public static func write(image: CGImage, pngData: Data? = nil) {
        write(pngData: pngData) { image }
    }

    /// Fulfils the outstanding promise before the app quits, while the pasteboard still holds it
    public static func resolveBeforeTermination() {
        lock.lock()
        let provider = current
        current = nil
        lock.unlock()
        guard let provider = provider, NSPasteboard.general.changeCount == provider.changeCount,
              let png = provider.data(for: .png) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
    }

    private func data(for type: NSPasteboard.PasteboardType) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if type == .png, let png = pngData { return png }
        if image == nil { image = makeImage() }
        guard let image = image else { return nil }
        if type == .png {
            pngData = Self.encode(image, as: .png)
            return pngData
        }
        return Self.encode(image, as: .tiff)
    }

    private static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: - NSPasteboardItemDataProvider

    public func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if let data = data(for: type) {
            item.setData(data, forType: type)
        }
    }

    public func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        Self.lock.lock()
        if Self.current === self { Self.current = nil }
        Self.lock.unlock()
    }
}
