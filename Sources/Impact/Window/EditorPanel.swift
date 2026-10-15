import Foundation
import CoreGraphics
import AppKit
import UniformTypeIdentifiers

public final class EditorPanel: NSPanel {
    public let document: EditorDocument
    public let canvasView: EditorCanvasView
    public let toolbarView: EditorToolbarView
    public private(set) var scrollView: NSScrollView?

    private var metaLabel: NSTextField?
    private var isPinned: Bool = false
    public var onClose: (() -> Void)?
    public let sourceFileURL: URL?
    private var hasSavedComposition: Bool = false

    public init(document: EditorDocument, title: String = "Shots Editor", sourceFileURL: URL? = nil) {
        self.document = document
        self.sourceFileURL = sourceFileURL
        self.canvasView = EditorCanvasView(document: document)
        self.toolbarView = EditorToolbarView(canvasView: canvasView)

        // Calculate window size based on image dimensions and active screen
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let maxW = screen.visibleFrame.width * 0.85
        let maxH = screen.visibleFrame.height * 0.85

        let toolbarWidth: CGFloat = 600.0
        let defaultHeight: CGFloat = 400.0

        let imgW = document.activeCanvasBounds.width
        let imgH = document.activeCanvasBounds.height

        let windowW = min(maxW, max(toolbarWidth, imgW + 40.0))
        let windowH = min(maxH, max(defaultHeight, imgH + 110.0))

        let initialX = screen.visibleFrame.midX - windowW / 2.0
        let initialY = screen.visibleFrame.midY - windowH / 2.0

        let contentRect = NSRect(x: initialX, y: initialY, width: windowW, height: windowH)

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Minimum width is the width of the tool panel; default height is 400
        minSize = NSSize(width: toolbarWidth, height: defaultHeight)

        // Normal window level so standard Cmd-Tab app switching and window ordering works as expected
        level = .normal
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = NSColor(white: 0.14, alpha: 0.98)
        hasShadow = true
        collectionBehavior = [.managed, .participatesInCycle, .fullScreenPrimary]

        setupContentView()
        setupToolbarActions()
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { true }

    override public func cancelOperation(_ sender: Any?) {
        canvasView.handleEscapeKey()
    }

    override public func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            canvasView.handleEscapeKey()
            return
        }
        super.keyDown(with: event)
    }

    public static var copyToClipboardOverride: Bool? = nil

    public static var isCopyToClipboardEnabled: Bool {
        get {
            if let overrideVal = copyToClipboardOverride {
                return overrideVal
            }
            if let shotsDefaults = UserDefaults(suiteName: "com.local.Shots"),
               let val = shotsDefaults.object(forKey: "copyToClipboard") as? Bool {
                return val
            }
            if let val = UserDefaults.standard.object(forKey: "copyToClipboard") as? Bool {
                return val
            }
            return true
        }
        set {
            copyToClipboardOverride = newValue
        }
    }

    override public func close() {
        // If preference "copy to clipboard" is set, copy the image with annotations to clipboard
        if EditorPanel.isCopyToClipboardEnabled {
            canvasView.copyCompositionToClipboard()
        }

        // When closing, if document has annotations and hasn't been saved yet, auto-save to new file
        if !document.layers.isEmpty && !hasSavedComposition {
            saveToNextNumberedFile()
        }
        super.close()
        onClose?()
    }

    /// Computes the next available numbered filename without overwriting existing files
    /// e.g. "arero.jpg" -> "arero-2.jpg", "arero-2.jpg" -> "arero-3.jpg"
    public func nextAvailableFileURL() -> URL {
        let baseDir: URL
        let baseName: String
        let ext: String

        if let source = sourceFileURL {
            baseDir = source.deletingLastPathComponent()
            let fullFilename = source.deletingPathExtension().lastPathComponent
            ext = source.pathExtension.isEmpty ? "png" : source.pathExtension

            // Check if fullFilename already ends with "-<digits>"
            let pattern = #"^(.*?)-(\d+)$"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: fullFilename, range: NSRange(fullFilename.startIndex..., in: fullFilename)) {
                let nameRange = Range(match.range(at: 1), in: fullFilename)!
                baseName = String(fullFilename[nameRange])
            } else {
                baseName = fullFilename
            }
        } else {
            baseDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
            baseName = "Annotation"
            ext = "png"
        }

        var counter = 2
        var candidateURL = baseDir.appendingPathComponent("\(baseName)-\(counter).\(ext)")
        while FileManager.default.fileExists(atPath: candidateURL.path) {
            counter += 1
            candidateURL = baseDir.appendingPathComponent("\(baseName)-\(counter).\(ext)")
        }
        return candidateURL
    }

    /// Saves the current composition directly without showing a Save As dialog
    @discardableResult
    public func saveToNextNumberedFile() -> URL? {
        let targetURL = nextAvailableFileURL()
        let ext = targetURL.pathExtension.lowercased()
        let format: NSBitmapImageRep.FileType = (ext == "jpg" || ext == "jpeg") ? .jpeg : .png
        canvasView.saveCompositionToFile(url: targetURL, format: format)
        hasSavedComposition = true
        return targetURL
    }

    private func setupContentView() {
        guard let container = contentView else { return }
        container.wantsLayer = true

        // 1. Scroll View holding the elastic canvas with auto-centering clip view
        let scrollView = NSScrollView()
        let clipView = CenteringClipView()
        scrollView.contentView = clipView
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 10.0
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = NSColor(white: 0.10, alpha: 1.0)
        scrollView.documentView = canvasView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        self.scrollView = scrollView

        // 2. Floating Toolbar at the bottom
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbarView)

        // Resolve version and build number
        let versionStr = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let buildStr: String = {
            if let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, !b.isEmpty {
                return b
            }
            if let resURL = Bundle.main.url(forResource: "BUILD_NUMBER", withExtension: nil),
               let content = try? String(contentsOf: resURL, encoding: .utf8) {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let projURL = URL(string: "file:///Users/citizen/dev/shots/BUILD_NUMBER"),
               let content = try? String(contentsOf: projURL, encoding: .utf8) {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            return "1"
        }()

        self.title = "\(title) — Build \(buildStr)"

        // 3. Header Info Bar at the top (Title + Build number on left, dimensions/zoom on right)
        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerView)

        let titleLabel = NSTextField(labelWithString: "Impact v\(versionStr) (Build \(buildStr))")
        titleLabel.font = NSFont.systemFont(ofSize: 11.0, weight: .semibold)
        titleLabel.textColor = NSColor(white: 0.65, alpha: 1.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        let meta = NSTextField(labelWithString: "\(Int(document.originalImageBounds.width)) × \(Int(document.originalImageBounds.height)) px")
        meta.font = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .medium)
        meta.textColor = NSColor(white: 0.7, alpha: 1.0)
        meta.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(meta)
        self.metaLabel = meta

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: container.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 32),

            // Left padding 76px clears the standard macOS traffic lights (close/minimize/zoom)
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 76),

            meta.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            meta.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            toolbarView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toolbarView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            toolbarView.widthAnchor.constraint(equalToConstant: 600),
            toolbarView.heightAnchor.constraint(equalToConstant: 48)
        ])

        document.onBoundsChanged = { [weak self, weak scrollView] bounds in
            guard let self = self, let sv = scrollView else { return }
            self.canvasView.frame = NSRect(origin: .zero, size: bounds.size)
            sv.documentView?.needsDisplay = true
            self.updateMetaLabel()
        }
    }

    /// Scales the image: if smaller than viewport, center at 100% (1.0). If larger, scale to best fit centered.
    public func scaleToFit() {
        guard let sv = scrollView else { return }
        sv.layoutSubtreeIfNeeded()

        let viewport = sv.contentView.bounds.size
        guard viewport.width > 0 && viewport.height > 0 else { return }

        let imgW = document.activeCanvasBounds.width
        let imgH = document.activeCanvasBounds.height
        guard imgW > 0 && imgH > 0 else { return }

        let padding: CGFloat = 32.0
        let availableW = max(50.0, viewport.width - padding)
        let availableH = max(50.0, viewport.height - padding)

        if imgW <= availableW && imgH <= availableH {
            // If image is smaller than available viewport, center it at 100% scale
            sv.magnification = 1.0
        } else {
            // If image is larger than available viewport, scale it to best fit centered
            let fitScale = min(availableW / imgW, availableH / imgH)
            sv.magnification = max(sv.minMagnification, fitScale)
        }

        canvasView.zoomScale = sv.magnification
        updateMetaLabel()
    }

    public func zoomIn() {
        guard let sv = scrollView else { return }
        let newMag = min(sv.maxMagnification, sv.magnification * 1.25)
        sv.setMagnification(newMag, centeredAt: NSPoint(x: sv.contentView.bounds.midX, y: sv.contentView.bounds.midY))
        canvasView.zoomScale = sv.magnification
        updateMetaLabel()
    }

    public func zoomOut() {
        guard let sv = scrollView else { return }
        let newMag = max(sv.minMagnification, sv.magnification / 1.25)
        sv.setMagnification(newMag, centeredAt: NSPoint(x: sv.contentView.bounds.midX, y: sv.contentView.bounds.midY))
        canvasView.zoomScale = sv.magnification
        updateMetaLabel()
    }

    public func resetZoom() {
        guard let sv = scrollView else { return }
        sv.setMagnification(1.0, centeredAt: NSPoint(x: sv.contentView.bounds.midX, y: sv.contentView.bounds.midY))
        canvasView.zoomScale = sv.magnification
        updateMetaLabel()
    }

    public func updateMetaLabel() {
        let zoomPercent = Int(round((scrollView?.magnification ?? 1.0) * 100))
        metaLabel?.stringValue = "\(Int(document.activeCanvasBounds.width)) × \(Int(document.activeCanvasBounds.height)) px  (\(zoomPercent)%)"
    }

    private func setupToolbarActions() {
        toolbarView.onPinToggle = { [weak self] pinned in
            guard let self = self else { return }
            self.isPinned = pinned
            self.level = pinned ? .floating : .normal
        }

        toolbarView.onZoomInRequested = { [weak self] in
            self?.zoomIn()
        }

        toolbarView.onZoomOutRequested = { [weak self] in
            self?.zoomOut()
        }

        toolbarView.onSaveRequested = { [weak self] in
            guard let self = self else { return }
            if let savedURL = self.saveToNextNumberedFile() {
                NSSound(named: "Tink")?.play()
                NSLog("Impact: Saved composition to %@", savedURL.path)
            }
            // Explicitly keep the editor panel open and active
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        toolbarView.onCopyRequested = {
            NSSound(named: "Tink")?.play()
        }
    }

    override public func magnify(with event: NSEvent) {
        canvasView.magnify(with: event)
    }
}

/// A clip view that centers the document view when it is smaller than the clip view viewport
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let docView = documentView else { return rect }
        if docView.frame.width < rect.width {
            rect.origin.x = (docView.frame.width - rect.width) / 2.0
        }
        if docView.frame.height < rect.height {
            rect.origin.y = (docView.frame.height - rect.height) / 2.0
        }
        return rect
    }

    override func magnify(with event: NSEvent) {
        if let doc = documentView as? EditorCanvasView {
            doc.magnify(with: event)
        } else {
            super.magnify(with: event)
        }
    }
}
