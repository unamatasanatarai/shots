import Cocoa
import CoreGraphics

public enum ImageFormat: String, CaseIterable, Identifiable {
    case png = "png"
    case jpg = "jpg"

    public var id: String { rawValue }

    public var fileExtension: String {
        return self.rawValue
    }

    public var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpg: return "JPG"
        }
    }
}

public final class SaveService {
    public static let shared = SaveService()

    private let lock = NSLock()
    private var reservedPaths = Set<String>()
    private var _latestSavedURL: URL?

    public var latestSavedURL: URL? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _latestSavedURL
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _latestSavedURL = newValue
        }
    }

    public init() {}

    // MARK: - Image Output Pipeline: Encoding

    /// Encodes a CGImage into lossless PNG data.
    public func encodePNG(image: CGImage) -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    /// Generic image encoder supporting configured formats (PNG, JPG).
    public func encodeImage(_ image: CGImage, format: ImageFormat = .png, quality: Double = 0.8) -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        switch format {
        case .png:
            return bitmapRep.representation(using: .png, properties: [:])
        case .jpg:
            let clampedQuality = max(0.01, min(1.0, quality))
            return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: clampedQuality])
        }
    }

    // MARK: - Filename Generation & Collision Handling

    /// Generates timestamp filename: shot_YYYYMMDD_HHMMSS.{png|jpg}
    public static func generateFilename(date: Date = Date(), format: ImageFormat = .png) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = formatter.string(from: date)
        return "shot_\(dateString).\(format.fileExtension)"
    }

    /// Resolves unique destination URL in directory, handling same-second collisions with _1, _2 suffix.
    public func resolveUniqueDestinationURL(in directoryURL: URL, date: Date = Date(), format: ImageFormat = .png) -> URL {
        lock.lock()
        defer { lock.unlock() }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = formatter.string(from: date)
        let base = "shot_\(dateString)"
        let ext = format.fileExtension

        var destinationURL = directoryURL.appendingPathComponent("\(base).\(ext)")
        var collisionIndex = 1
        while FileManager.default.fileExists(atPath: destinationURL.path) || reservedPaths.contains(destinationURL.path) {
            destinationURL = directoryURL.appendingPathComponent("\(base)_\(collisionIndex).\(ext)")
            collisionIndex += 1
        }
        reservedPaths.insert(destinationURL.path)
        return destinationURL
    }

    // MARK: - Saving Pipeline

    /// Persists encoded image data to the target directory with the given filename.
    @discardableResult
    public func saveImageData(_ data: Data, to directoryURL: URL, filename: String) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        let destinationURL = directoryURL.appendingPathComponent(filename)
        do {
            try data.write(to: destinationURL, options: .atomic)
            lock.lock()
            reservedPaths.remove(destinationURL.path)
            _latestSavedURL = destinationURL
            lock.unlock()
            return destinationURL
        } catch {
            lock.lock()
            reservedPaths.remove(destinationURL.path)
            lock.unlock()
            throw error
        }
    }

    /// Encodes a CGImage into JPEG data at the specified quality factor (0.01 - 1.0).
    public func encodeJPG(image: CGImage, quality: Double = 0.8) -> Data? {
        let clampedQuality = max(0.01, min(1.0, quality))
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: clampedQuality])
    }

    /// Persists a CGImage as JPEG to the target directory.
    @discardableResult
    public func saveJPG(_ image: CGImage, to directoryURL: URL, filename: String, quality: Double = 0.8) throws -> URL {
        guard let data = encodeJPG(image: image, quality: quality) else {
            throw NSError(
                domain: "SaveService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode image to JPG"]
            )
        }
        return try saveImageData(data, to: directoryURL, filename: filename)
    }

    // MARK: - Pasteboard Operations

    /// Copies a CGImage and optional raw PNG data to the general system pasteboard.
    public func copyToPasteboard(image: CGImage, pngData: Data? = nil, fileURL: URL? = nil) {
        lock.lock()
        defer { lock.unlock() }

        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let pb = NSPasteboard.general
        pb.clearContents()

        var objects: [NSPasteboardWriting] = [nsImage]
        if let fileURL = fileURL {
            objects.append(fileURL as NSURL)
        }
        pb.writeObjects(objects)

        if let data = pngData ?? encodePNG(image: image) {
            pb.setData(data, forType: .png)
        }
    }

    // MARK: - Reveal & Latest File Resolution

    /// Resolves the latest screenshot file URL, either from in-memory tracking or by inspecting the target directory.
    public func resolveLatestScreenshotURL(directoryURL: URL? = nil) -> URL? {
        if let latest = latestSavedURL, FileManager.default.fileExists(atPath: latest.path) {
            return latest
        }

        let targetDir = directoryURL ?? AppSettings.shared.resolvedSaveDirectoryURL
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: targetDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let screenshotFiles = files.filter { url in
            let ext = url.pathExtension.lowercased()
            let filename = url.lastPathComponent
            return (ext == "png" || ext == "jpg" || ext == "jpeg") && filename.hasPrefix("shot_")
        }

        let sorted = screenshotFiles.sorted { u1, u2 in
            let d1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let d2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return d1 > d2
        }

        if let newest = sorted.first {
            latestSavedURL = newest
            return newest
        }
        return nil
    }

    /// Reveals the latest screenshot in macOS Finder, selecting the file.
    @discardableResult
    public func revealLatestScreenshot(directoryURL: URL? = nil) -> Bool {
        guard let url = resolveLatestScreenshotURL(directoryURL: directoryURL) else {
            return false
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }
}
