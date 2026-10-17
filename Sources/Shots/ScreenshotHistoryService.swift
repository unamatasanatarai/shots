import Cocoa
import ImageIO

public struct ScreenshotHistoryItem: Equatable {
    public let fileURL: URL
    public let filename: String
    public let modificationDate: Date
    public let thumbnail: NSImage?

    public init(fileURL: URL, filename: String, modificationDate: Date, thumbnail: NSImage? = nil) {
        self.fileURL = fileURL
        self.filename = filename
        self.modificationDate = modificationDate
        self.thumbnail = thumbnail
    }

    public static func == (lhs: ScreenshotHistoryItem, rhs: ScreenshotHistoryItem) -> Bool {
        return lhs.fileURL.standardizedFileURL == rhs.fileURL.standardizedFileURL &&
               lhs.filename == rhs.filename
    }
}

public final class ScreenshotHistoryService {
    public static let shared = ScreenshotHistoryService()

    public static let defaultMaxRecentCount = 10
    private static let validExtensions: Set<String> = ["png", "jpg", "jpeg"]

    private let lock = NSLock()
    private var _recentItems: [ScreenshotHistoryItem] = []
    private let thumbnailCache = NSCache<NSURL, NSImage>()

    public var recentItems: [ScreenshotHistoryItem] {
        lock.lock()
        defer { lock.unlock() }
        return _recentItems
    }

    public init() {}

    /// Clears cached items (primarily for test isolation)
    public func reset() {
        lock.lock()
        _recentItems = []
        thumbnailCache.removeAllObjects()
        lock.unlock()
    }

    /// Discovers and returns the list of 5–10 most recent screenshots from the save directory.
    @discardableResult
    public func fetchRecentScreenshots(
        limit: Int = defaultMaxRecentCount,
        directoryURL: URL? = nil
    ) -> [ScreenshotHistoryItem] {
        let folderURL = directoryURL ?? AppSettings.shared.resolvedSaveDirectoryURL

        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            lock.lock()
            _recentItems = []
            lock.unlock()
            return []
        }

        let fileMetadata: [(url: URL, modDate: Date)] = fileURLs.compactMap { url in
            let filename = url.lastPathComponent
            guard filename.hasPrefix("shot_") else { return nil }
            let ext = url.pathExtension.lowercased()
            guard Self.validExtensions.contains(ext) else { return nil }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return (url, modDate)
        }

        let sorted = fileMetadata.sorted { $0.modDate > $1.modDate }
        let clampedLimit = max(1, min(limit, 20))
        let topSlice = sorted.prefix(clampedLimit)

        var items: [ScreenshotHistoryItem] = []
        for entry in topSlice {
            let thumb = generateThumbnail(for: entry.url, maxPixelSize: 36)
            items.append(ScreenshotHistoryItem(
                fileURL: entry.url,
                filename: entry.url.lastPathComponent,
                modificationDate: entry.modDate,
                thumbnail: thumb
            ))
        }

        lock.lock()
        self._recentItems = items
        lock.unlock()
        return items
    }

    /// Generates an efficient thumbnail for a file URL using ImageIO with in-memory caching.
    public func generateThumbnail(for url: URL, maxPixelSize: Int = 36) -> NSImage? {
        let key = url as NSURL
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgThumb, size: NSSize(width: maxPixelSize, height: maxPixelSize))
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    /// Adds a newly captured screenshot directly to the history in memory.
    public func recordNewScreenshot(fileURL: URL) {
        let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let thumb = generateThumbnail(for: fileURL, maxPixelSize: 36)
        let newItem = ScreenshotHistoryItem(
            fileURL: fileURL,
            filename: fileURL.lastPathComponent,
            modificationDate: modDate,
            thumbnail: thumb
        )

        lock.lock()
        var current = _recentItems.filter { $0.fileURL.standardizedFileURL != fileURL.standardizedFileURL }
        current.insert(newItem, at: 0)
        if current.count > ScreenshotHistoryService.defaultMaxRecentCount {
            current = Array(current.prefix(ScreenshotHistoryService.defaultMaxRecentCount))
        }
        self._recentItems = current
        lock.unlock()
    }

    /// Reveals a selected screenshot file in macOS Finder, returning true on success.
    @discardableResult
    public func revealScreenshotInFinder(fileURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return false
        }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        return true
    }

    /// Reads image data from the screenshot URL and copies it to the general pasteboard.
    @discardableResult
    public func copyScreenshotToClipboard(fileURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return false
        }
        if let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            SaveService.shared.copyToPasteboard(image: cgImage, fileURL: fileURL)
            return true
        }

        guard let image = NSImage(contentsOf: fileURL),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            return false
        }
        SaveService.shared.copyToPasteboard(image: cgImage, fileURL: fileURL)
        return true
    }
}
