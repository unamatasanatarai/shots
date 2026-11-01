import Foundation
import CoreGraphics
import AppKit
import UniformTypeIdentifiers

public final class ImpactAppCoordinator {
    public static let shared = ImpactAppCoordinator()

    public private(set) var activePanel: EditorPanel?
    public var welcomePanel: WelcomePanel? { return nil }

    private init() {}

    /// Images still decoding: their editor isn't open yet, so Impact must not quit meanwhile (main thread only)
    private(set) var pendingOpenCount = 0

    /// No editor open and none on the way
    var isIdle: Bool { activePanel == nil && pendingOpenCount == 0 }

    /// Quits Impact once no editor window is open. The delay avoids reacting during window swaps
    /// (old panel closed before the new one is shown) and lets a pending open-file event arrive.
    private func terminateIfNoEditorSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // isRunning is false when hosted by the test runner (no app.run()), so tests aren't killed
            guard self.isIdle, NSApp.isRunning else { return }
            NSApp.terminate(nil)
        }
    }

    /// Brings Impact back to a regular app (Dock icon, menu bar) before showing a window
    private func activate() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens the single main window in empty/welcome state with "Drag or click to open"
    public func openEmptyEditor() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let existing = self.activePanel, existing.isVisible {
                existing.makeKeyAndOrderFront(nil)
                self.activate()
                return
            }

            let panel = EditorPanel()
            self.activePanel = panel

            panel.onClose = { [weak self] in
                if self?.activePanel === panel {
                    self?.activePanel = nil
                }
                self?.terminateIfNoEditorSoon()
            }

            panel.makeKeyAndOrderFront(nil)
            self.activate()
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
                self.activate()
                return
            }

            let document = EditorDocument(image: image)
            let panel = EditorPanel(document: document, title: title, sourceFileURL: sourceFileURL)
            self.activePanel = panel

            panel.onClose = { [weak self] in
                if self?.activePanel === panel {
                    self?.activePanel = nil
                }
                self?.terminateIfNoEditorSoon()
            }

            panel.makeKeyAndOrderFront(nil)
            self.activate()
            panel.scaleToFit()

            if EditorPanel.isCopyToClipboardEnabled {
                panel.canvasView.copyCompositionToClipboard()
                panel.showCopiedToClipboardToast()
            }
        }
    }

    public func openImageFile(url: URL) {
        let begin = { self.pendingOpenCount += 1 }
        if Thread.isMainThread { begin() } else { DispatchQueue.main.sync(execute: begin) }
        // Decode off the main thread, up front: a lazily decoded image would decode during the first paint
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let decodeOptions = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, decodeOptions) else {
                NSLog("ImpactAppCoordinator: Failed to load image from %@", url.path)
                DispatchQueue.main.async {
                    self?.pendingOpenCount -= 1
                    self?.terminateIfNoEditorSoon()
                }
                return
            }
            self?.openEditor(with: cgImage, title: url.lastPathComponent, sourceFileURL: url)
            // openEditor shows the panel in a main-queue block queued just above: count down after it
            DispatchQueue.main.async { self?.pendingOpenCount -= 1 }
        }
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

            self.activate()
            if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
                self.openImageFile(url: selectedURL)
            } else {
                self.terminateIfNoEditorSoon()
            }
        }
    }

    /// Closes the editor now when called on the main thread (callers see it closed on return), else on the main queue
    public func closeEditor() {
        let close = { [weak self] in
            self?.activePanel?.close()
            self?.activePanel = nil
        }
        if Thread.isMainThread { close() } else { DispatchQueue.main.async(execute: close) }
    }
}
