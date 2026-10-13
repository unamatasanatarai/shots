import Foundation
import CoreGraphics
import AppKit
import ImageIO

public final class EditorCoordinator {
    public static let shared = EditorCoordinator()

    public private(set) var activePanel: EditorPanel?

    private init() {}

    // MARK: - Open In Editor (Step 1 & Additional Functionality)

    public func openEditor(with image: CGImage, title: String = "Shots Editor") {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let document = EditorDocument(image: image)
            let panel = EditorPanel(document: document, title: title)

            self.activePanel?.close()
            self.activePanel = panel

            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func openImageFile(url: URL) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            NSLog("EditorCoordinator: Failed to load image from %@", url.path)
            NSSound.beep()
            return
        }
        openEditor(with: cgImage, title: url.lastPathComponent)
    }

    public func openImageFileDialog() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = true
            openPanel.canChooseDirectories = false
            openPanel.allowsMultipleSelection = false
            openPanel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
            openPanel.prompt = "Open in Editor"

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
        NSLog("EditorCoordinator: test-image.jpg not found")
        NSSound.beep()
    }

    public func closeEditor() {
        DispatchQueue.main.async { [weak self] in
            self?.activePanel?.close()
            self?.activePanel = nil
        }
    }
}
