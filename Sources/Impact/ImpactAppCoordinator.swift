import Foundation
import CoreGraphics
import AppKit
import UniformTypeIdentifiers

public final class ImpactAppCoordinator {
    public static let shared = ImpactAppCoordinator()

    public private(set) var activePanel: EditorPanel?
    public private(set) var welcomePanel: WelcomePanel?

    private init() {}

    public func openWelcome() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let existing = self.welcomePanel, existing.isVisible {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let panel = WelcomePanel()
            self.welcomePanel = panel

            panel.onClose = { [weak self] in
                if self?.welcomePanel === panel {
                    self?.welcomePanel = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if ImpactAppCoordinator.shared.activePanel == nil && ImpactAppCoordinator.shared.welcomePanel == nil {
                        NSApp.terminate(nil)
                    }
                }
            }

            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func openEditor(with image: CGImage, title: String = "Impact", sourceFileURL: URL? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let document = EditorDocument(image: image)
            let panel = EditorPanel(document: document, title: title, sourceFileURL: sourceFileURL)

            // Close welcome panel if open
            let oldWelcome = self.welcomePanel
            self.welcomePanel = nil
            oldWelcome?.close()

            self.activePanel?.close()
            self.activePanel = panel

            panel.onClose = { [weak self] in
                if self?.activePanel === panel {
                    self?.activePanel = nil
                }
                // If no replacement panel appears shortly after close, terminate the app.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if ImpactAppCoordinator.shared.activePanel == nil && ImpactAppCoordinator.shared.welcomePanel == nil {
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
