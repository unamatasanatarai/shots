import Cocoa
import CoreGraphics

public enum ImageFormat: String, CaseIterable {
    case png = "png"
    case jpg = "jpg"

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

    public private(set) var latestSavedURL: URL?

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

    // MARK: - Saving Pipeline

    /// Persists encoded image data to the target directory with the given filename.
    @discardableResult
    public func saveImageData(_ data: Data, to directoryURL: URL, filename: String) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        let destinationURL = directoryURL.appendingPathComponent(filename)
        try data.write(to: destinationURL, options: .atomic)
        latestSavedURL = destinationURL
        return destinationURL
    }

    /// Persists a CGImage as PNG to the target directory.
    @discardableResult
    public func savePNG(_ image: CGImage, to directoryURL: URL, filename: String) throws -> URL {
        guard let data = encodePNG(image: image) else {
            throw NSError(
                domain: "SaveService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode image to PNG"]
            )
        }
        return try saveImageData(data, to: directoryURL, filename: filename)
    }

    // MARK: - Pasteboard Operations

    /// Copies a CGImage and optional raw PNG data to the general system pasteboard.
    public func copyToPasteboard(image: CGImage, pngData: Data? = nil, fileURL: URL? = nil) {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let pb = NSPasteboard.general
        pb.clearContents()

        pb.writeObjects([nsImage])

        if let fileURL = fileURL {
            pb.writeObjects([fileURL as NSURL])
        }

        if let data = pngData ?? encodePNG(image: image) {
            pb.setData(data, forType: .png)
        }
    }
}
