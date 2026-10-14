import Foundation
import CoreGraphics
import AppKit
import ImageIO
import UniformTypeIdentifiers

public final class ImpactLauncher {
    public static let shared = ImpactLauncher()

    private init() {}

    // MARK: - Open In Impact (Launches separate Impact.app)

    private func findImpactAppURL() -> URL? {
        let candidateName = "Impact.app"
        // 1. Check side-by-side in same directory as Shots.app (e.g. /Applications or build/)
        if let bundleURL = Bundle.main.bundleURL as URL? {
            let sibling = bundleURL.deletingLastPathComponent().appendingPathComponent(candidateName)
            if FileManager.default.fileExists(atPath: sibling.path) {
                return sibling
            }
        }
        // 2. Check build directory
        let buildPath = URL(fileURLWithPath: "build/\(candidateName)")
        if FileManager.default.fileExists(atPath: buildPath.path) {
            return buildPath
        }
        // 3. Check system Applications directory
        let appPath = URL(fileURLWithPath: "/Applications/\(candidateName)")
        if FileManager.default.fileExists(atPath: appPath.path) {
            return appPath
        }
        return nil
    }

    public func openImpact(with image: CGImage, title: String = "Impact") {
        // Save to temporary PNG file and launch Impact.app
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("capture_\(Int(Date().timeIntervalSince1970 * 1000)).png")
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: tempURL)
            if let impactURL = findImpactAppURL() {
                let config = NSWorkspace.OpenConfiguration()
                config.arguments = [tempURL.path]
                NSWorkspace.shared.openApplication(at: impactURL, configuration: config, completionHandler: nil)
                return
            }
        }

        // If Impact.app not found via standard locations, try opening with system
        if let impactURL = findImpactAppURL() {
            let config = NSWorkspace.OpenConfiguration()
            config.arguments = [tempURL.path]
            NSWorkspace.shared.openApplication(at: impactURL, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(tempURL)
        }
    }

    public func openImageFile(url: URL) {
        if let impactURL = findImpactAppURL() {
            let config = NSWorkspace.OpenConfiguration()
            config.arguments = [url.path]
            NSWorkspace.shared.openApplication(at: impactURL, configuration: config, completionHandler: nil)
            return
        }

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            NSLog("ImpactLauncher: Failed to load image from %@", url.path)
            NSSound.beep()
            return
        }
        openImpact(with: cgImage, title: url.lastPathComponent)
    }

    public func openImageFileDialog() {
        if let impactURL = findImpactAppURL() {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: impactURL, configuration: config, completionHandler: nil)
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = true
            openPanel.canChooseDirectories = false
            openPanel.allowsMultipleSelection = false
            openPanel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
            openPanel.prompt = "Open in Impact"

            if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
                self.openImageFile(url: selectedURL)
            }
        }
    }

    public func openTestImage() {
        let possiblePaths = [
            Bundle.main.resourceURL?.appendingPathComponent("test-image.jpg"),
            URL(fileURLWithPath: "Resources/test-image.jpg"),
            URL(fileURLWithPath: "test-image.jpg"),
            URL(fileURLWithPath: "/Users/citizen/dev/shots/Resources/test-image.jpg")
        ]

        for path in possiblePaths.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: path.path) {
                openImageFile(url: path)
                return
            }
        }
        NSLog("ImpactLauncher: test-image.jpg not found")
        NSSound.beep()
    }
}
