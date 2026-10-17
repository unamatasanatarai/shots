import Foundation
import CoreGraphics
import AppKit
import ImageIO
import UniformTypeIdentifiers

public final class ImpactLauncher {
    public static let shared = ImpactLauncher()

    private init() {}

    // MARK: - Open In Impact (Launches separate Impact.app)

    private var cachedImpactAppURL: URL?

    private func findImpactAppURL() -> URL? {
        if let cached = cachedImpactAppURL, FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        let candidateName = "Impact.app"
        // 1. Check side-by-side in same directory as Shots.app (e.g. /Applications or build/)
        if let bundleURL = Bundle.main.bundleURL as URL? {
            let sibling = bundleURL.deletingLastPathComponent().appendingPathComponent(candidateName)
            if FileManager.default.fileExists(atPath: sibling.path) {
                cachedImpactAppURL = sibling
                return sibling
            }
        }
        // 2. Check build directory
        let buildPath = URL(fileURLWithPath: "build/\(candidateName)")
        if FileManager.default.fileExists(atPath: buildPath.path) {
            cachedImpactAppURL = buildPath
            return buildPath
        }
        // 3. Check system Applications directory
        let appPath = URL(fileURLWithPath: "/Applications/\(candidateName)")
        if FileManager.default.fileExists(atPath: appPath.path) {
            cachedImpactAppURL = appPath
            return appPath
        }
        return nil
    }

    public func openImpact(with image: CGImage, title: String = "Impact") {
        // Save to temporary PNG file via fast hardware ImageIO and launch Impact.app
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("capture_\(Int(Date().timeIntervalSince1970 * 1000)).png")
        if let data = SaveService.shared.encodePNG(image: image) {
            try? data.write(to: tempURL, options: .atomic)
        }

        if let impactURL = findImpactAppURL() {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([tempURL], withApplicationAt: impactURL, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(tempURL)
        }
    }

    public func openImageFile(url: URL) {
        if let impactURL = findImpactAppURL() {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: impactURL, configuration: config, completionHandler: nil)
            return
        }

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            NSLog("ImpactLauncher: Failed to load image from %@", url.path)
            return
        }
        openImpact(with: cgImage, title: url.lastPathComponent)
    }
}
