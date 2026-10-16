import Foundation
import CoreGraphics
import AppKit
import UniformTypeIdentifiers

public final class ImpactAppCoordinator {
    public static let shared = ImpactAppCoordinator()

    public private(set) var activePanel: EditorPanel?
    public var welcomePanel: WelcomePanel? { return nil }

    private init() {}

    /// Opens the single main window in empty/welcome state with "Drag or click to open"
    public func openEmptyEditor() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let existing = self.activePanel, existing.isVisible {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let panel = EditorPanel()
            self.activePanel = panel

            panel.onClose = { [weak self] in
                if self?.activePanel === panel {
                    self?.activePanel = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if ImpactAppCoordinator.shared.activePanel == nil {
                        NSApp.terminate(nil)
                    }
                }
            }

            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Backwards-compatible alias for openEmptyEditor
    public func openWelcome() {
        openEmptyEditor()
    }

    public func openEditor(with image: CGImage, title: String = "Impact", sourceFileURL: URL? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // If the single main window already exists, load the image directly into it
            if let existing = self.activePanel, existing.isVisible {
                existing.loadImage(image: image, title: title, sourceFileURL: sourceFileURL)
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let document = EditorDocument(image: image)
            let panel = EditorPanel(document: document, title: title, sourceFileURL: sourceFileURL)
            self.activePanel = panel

            panel.onClose = { [weak self] in
                if self?.activePanel === panel {
                    self?.activePanel = nil
                }
                // If no replacement panel appears shortly after close, terminate the app.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if ImpactAppCoordinator.shared.activePanel == nil {
                        NSApp.terminate(nil)
                    }
                }
            }

            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            panel.scaleToFit()

            if EditorPanel.isCopyToClipboardEnabled {
                panel.canvasView.copyCompositionToClipboard()
                panel.showCopiedToClipboardToast()
            }
        }
    }

    public func openImageFile(url: URL) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            NSLog("ImpactAppCoordinator: Failed to load image from %@", url.path)
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
            var types: [UTType] = [.png, .jpeg, .tiff, .heic, .gif, .bmp]
            if let webp = UTType(filenameExtension: "webp") {
                types.append(webp)
            }
            openPanel.allowedContentTypes = types
            openPanel.prompt = "Open in Impact"

            NSApp.activate(ignoringOtherApps: true)
            if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
                self.openImageFile(url: selectedURL)
            }
        }
    }

    public func closeEditor() {
        DispatchQueue.main.async { [weak self] in
            self?.activePanel?.close()
            self?.activePanel = nil
        }
    }
}
