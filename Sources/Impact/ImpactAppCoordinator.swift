import Foundation
import CoreGraphics
import AppKit
import UniformTypeIdentifiers

public final class ImpactAppCoordinator {
    public static let shared = ImpactAppCoordinator()

    public private(set) var activePanel: EditorPanel?

    private init() {}

    public func openEditor(with image: CGImage, title: String = "Impact", sourceFileURL: URL? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let document = EditorDocument(image: image)
            let panel = EditorPanel(document: document, title: title, sourceFileURL: sourceFileURL)

            self.activePanel?.close()
            self.activePanel = panel

            panel.onClose = { [weak self] in
                if self?.activePanel === panel {
                    self?.activePanel = nil
                }
                // If no replacement panel appears shortly after close, terminate the app.
                // This handles both user-initiated close and programmatic window swaps:
                // during a swap, activePanel is immediately set to the new panel, so the
                // delayed check sees it's non-nil and skips termination.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if ImpactAppCoordinator.shared.activePanel == nil {
                        NSApp.terminate(nil)
                    }
                }
            }

            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            panel.scaleToFit()
        }
    }

    public func openImageFile(url: URL) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            NSLog("ImpactAppCoordinator: Failed to load image from %@", url.path)
            NSSound.beep()
            return
        }
        openEditor(with: cgImage, title: url.lastPathComponent, sourceFileURL: url)
    }

    public func openImageFileDialog() {
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
        NSLog("ImpactAppCoordinator: test-image.jpg not found")
        NSSound.beep()
    }

    public func closeEditor() {
        DispatchQueue.main.async { [weak self] in
            self?.activePanel?.close()
            self?.activePanel = nil
        }
    }
}
