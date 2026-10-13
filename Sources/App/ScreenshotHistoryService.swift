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

    public private(set) var recentItems: [ScreenshotHistoryItem] = []

    public init() {}

    /// Clears cached items (primarily for test isolation)
    public func reset() {
        recentItems = []
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
            recentItems = []
            return []
        }

        let validExtensions = Set(["png", "jpg", "jpeg"])
        let screenshotURLs = fileURLs.filter { url in
            let ext = url.pathExtension.lowercased()
            return validExtensions.contains(ext) && url.lastPathComponent.hasPrefix("shot_")
        }

        let sortedURLs = screenshotURLs.sorted { u1, u2 in
            let d1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let d2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return d1 > d2
        }

        let clampedLimit = max(1, min(limit, 20))
        let topSlice = sortedURLs.prefix(clampedLimit)

        var items: [ScreenshotHistoryItem] = []
        for url in topSlice {
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let thumb = generateThumbnail(for: url, maxPixelSize: 36)
            items.append(ScreenshotHistoryItem(
                fileURL: url,
                filename: url.lastPathComponent,
                modificationDate: modDate,
                thumbnail: thumb
            ))
        }

        self.recentItems = items
        return items
    }

    /// Generates an efficient thumbnail for a file URL using ImageIO.
    public func generateThumbnail(for url: URL, maxPixelSize: Int = 36) -> NSImage? {
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
        return NSImage(cgImage: cgThumb, size: NSSize(width: maxPixelSize, height: maxPixelSize))
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

        var current = recentItems.filter { $0.fileURL.standardizedFileURL != fileURL.standardizedFileURL }
        current.insert(newItem, at: 0)
        if current.count > ScreenshotHistoryService.defaultMaxRecentCount {
            current = Array(current.prefix(ScreenshotHistoryService.defaultMaxRecentCount))
        }
        self.recentItems = current
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
}
