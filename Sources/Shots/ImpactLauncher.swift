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

        // 2. Check LaunchServices for registered app by bundle ID
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.unamatasanatarai.Impact") {
            cachedImpactAppURL = appURL
            return appURL
        }

        // 3. Check /Applications and ~/Applications
        let systemApp = URL(fileURLWithPath: "/Applications/\(candidateName)")
        if FileManager.default.fileExists(atPath: systemApp.path) {
            cachedImpactAppURL = systemApp
            return systemApp
        }
        let userApp = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(candidateName)")
        if FileManager.default.fileExists(atPath: userApp.path) {
            cachedImpactAppURL = userApp
            return userApp
        }

        // 4. Check relative to executable parent structure
        if let execURL = Bundle.main.executableURL {
            let projectOrContainingDir = execURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let buildImpact = projectOrContainingDir.appendingPathComponent("build/\(candidateName)")
            if FileManager.default.fileExists(atPath: buildImpact.path) {
                cachedImpactAppURL = buildImpact
                return buildImpact
            }
        }

        return nil
    }

    /// Temporary hand-off files older than this are deleted when a new one is written
    static let tempCaptureLifetime: TimeInterval = 3600
    static let tempCapturePrefix = "capture_"

    public func openImpact(with image: CGImage, title: String = "Impact") {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        Self.purgeStaleTempCaptures(in: tempDirectory)

        // Save to temporary PNG file via fast hardware ImageIO and launch Impact.app
        guard let tempURL = Self.writeTempCapture(image, in: tempDirectory) else {
            // Nothing to open: never hand Impact (or the default app) a URL that does not exist
            NSLog("ImpactLauncher: failed to write temporary capture; not opening Impact")
            return
        }

        if let impactURL = findImpactAppURL() {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([tempURL], withApplicationAt: impactURL, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(tempURL)
        }
    }

    /// Encodes the image to a uniquely named capture_*.png in `directory`; nil if encoding or writing failed
    static func writeTempCapture(_ image: CGImage, in directory: URL) -> URL? {
        let name = "\(tempCapturePrefix)\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(8)).png"
        let url = directory.appendingPathComponent(name)
        guard let data = SaveService.shared.encodePNG(image: image) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            NSLog("ImpactLauncher: could not write %@: %@", url.path, error.localizedDescription)
            return nil
        }
    }

    /// Deletes capture_*.png hand-off files older than `maxAge` (Impact has long since loaded them)
    @discardableResult
    static func purgeStaleTempCaptures(
        in directory: URL,
        maxAge: TimeInterval = tempCaptureLifetime,
        now: Date = Date()
    ) -> Int {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var removed = 0
        for url in entries {
            let name = url.lastPathComponent
            guard name.hasPrefix(tempCapturePrefix), url.pathExtension.lowercased() == "png" else { continue }
            guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  now.timeIntervalSince(modified) > maxAge else { continue }
            if (try? fm.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
    }

    public func openImageFile(url: URL) {
        if let impactURL = findImpactAppURL() {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: impactURL, configuration: config, completionHandler: nil)
            return
        }

        // If Impact.app is not installed, open the existing file directly with default handler
        NSWorkspace.shared.open(url)
    }
}
