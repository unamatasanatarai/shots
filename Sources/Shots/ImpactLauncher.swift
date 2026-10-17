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
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.local.Impact") {
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

        // If Impact.app is not installed, open the existing file directly with default handler
        NSWorkspace.shared.open(url)
    }
}
