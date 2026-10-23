import Foundation
import CoreGraphics
import AppKit
import UniformTypeIdentifiers

public final class EditorPanel: NSPanel {
    public private(set) var document: EditorDocument
    public let canvasView: EditorCanvasView
    public let toolbarView: EditorToolbarView
    public private(set) var scrollView: NSScrollView?
    public private(set) var welcomeDropView: WelcomeDropView?
    public private(set) var hasImage: Bool

    private var metaLabel: NSTextField?
    private var isPinned: Bool = false
    public var onClose: (() -> Void)?
    public private(set) var sourceFileURL: URL?
    private var hasSavedComposition: Bool = false

    public init(document: EditorDocument? = nil, title: String = "Impact", sourceFileURL: URL? = nil) {
        let doc = document ?? EditorDocument.makePlaceholder()
        self.document = doc
        self.hasImage = (document != nil)
        self.sourceFileURL = sourceFileURL
        self.canvasView = EditorCanvasView(document: doc)
        self.toolbarView = EditorToolbarView(canvasView: canvasView)

        // Calculate window size based on image dimensions or default empty size
        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxW = visibleFrame.width * 0.85
        let maxH = visibleFrame.height * 0.85

        let windowW: CGFloat
        let windowH: CGFloat
        if let doc = document {
            let defaultWidth: CGFloat = 600.0
            let defaultHeight: CGFloat = 400.0
            let imgW = doc.activeCanvasBounds.width
            let imgH = doc.activeCanvasBounds.height
            windowW = min(maxW, max(defaultWidth, imgW + 40.0))
            windowH = min(maxH, max(defaultHeight, imgH + 80.0))
        } else {
            windowW = 680.0
            windowH = 460.0
        }

        let initialX = visibleFrame.midX - windowW / 2.0
        let initialY = visibleFrame.midY - windowH / 2.0

        let contentRect = NSRect(x: initialX, y: initialY, width: windowW, height: windowH)

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Minimum window size is compact and responsive (window width controls toolbar tools collapse)
        minSize = NSSize(width: 280.0, height: 200.0)

        // Normal window level so standard Cmd-Tab app switching and window ordering works as expected
        level = .normal
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = NSColor(white: 0.14, alpha: 0.98)
        hasShadow = true
        collectionBehavior = [.managed, .participatesInCycle, .fullScreenPrimary]

        registerForDraggedTypes([.fileURL])

        setupContentView()
        setupToolbarActions()

        toolbarView.layoutSubtreeIfNeeded()
        toolbarView.updateResponsiveOverflow()

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            self?.toolbarView.layoutSubtreeIfNeeded()
            self?.toolbarView.updateResponsiveOverflow()
        }
    }

    override public func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag)
        toolbarView.layoutSubtreeIfNeeded()
        toolbarView.updateResponsiveOverflow()
    }

    override public func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag, animate: animateFlag)
        toolbarView.layoutSubtreeIfNeeded()
        toolbarView.updateResponsiveOverflow()
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { true }

    override public func becomeKey() {
        super.becomeKey()
        NSCursor.arrow.set()
        if let cv = contentView {
            invalidateCursorRects(for: cv)
        }
        invalidateCursorRects(for: canvasView)
    }

    override public func cancelOperation(_ sender: Any?) {
        canvasView.handleEscapeKey()
    }

    override public func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            canvasView.handleEscapeKey()
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "o" {
            ImpactAppCoordinator.shared.openImageFileDialog()
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "1" {
            scaleToFit()
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "0" {
            resetZoom()
            return
        }
        if event.modifierFlags.contains(.command) && (event.charactersIgnoringModifiers == "=" || event.charactersIgnoringModifiers == "+") {
            zoomIn()
            return
        }
        if event.modifierFlags.contains(.command) && (event.charactersIgnoringModifiers == "-" || event.charactersIgnoringModifiers == "_") {
            zoomOut()
            return
        }
        if event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers, ["c", "x", "v", "d"].contains(key) {
            // Copy / cut / paste / duplicate reach the canvas even when it is not first responder
            canvasView.keyDown(with: event)
            return
        }
        if event.keyCode == 123 || event.keyCode == 124 || event.keyCode == 125 || event.keyCode == 126 { // Arrow keys
            let isShift = event.modifierFlags.contains(.shift)
            if canvasView.nudgeSelectedLayers(keyCode: event.keyCode, isShift: isShift, isRepeat: event.isARepeat) {
                return
            }
        }
        super.keyDown(with: event)
    }

    public static var copyToClipboardOverride: Bool? = nil

    private static let shotsDefaults = UserDefaults(suiteName: "com.local.Shots")
    private static let numberedSuffixRegex = try? NSRegularExpression(pattern: #"^(.*?)-(\d+)$"#)

    public static var isCopyToClipboardEnabled: Bool {
        get {
            if let overrideVal = copyToClipboardOverride {
                return overrideVal
            }
            if let shotsDefaults = shotsDefaults {
                if let val = shotsDefaults.object(forKey: "copyToClipboard") as? Bool {
                    return val
                }
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

    public var shouldCopyOnClose: Bool = true

    override public func close() {
        // Commit any callout being typed so the copy and the saved file include it
        canvasView.endCalloutEditingIfNeeded()

        // If no image was ever loaded in this window, do not copy or save empty compositions
        guard hasImage else {
            super.close()
            onClose?()
            return
        }

        // If preference "copy to clipboard" is set, copy the image with annotations to clipboard
        if shouldCopyOnClose && EditorPanel.isCopyToClipboardEnabled {
            canvasView.copyCompositionToClipboard()
        }

        // Upon closing Impact, save to numbered file without overwriting original only if modified
        if !hasSavedComposition && (!document.layers.isEmpty || document.isModified) {
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
            if let regex = EditorPanel.numberedSuffixRegex,
               let match = regex.firstMatch(in: fullFilename, range: NSRange(fullFilename.startIndex..., in: fullFilename)) {
                let nameRange = Range(match.range(at: 1), in: fullFilename)!
                baseName = String(fullFilename[nameRange])
            } else {
                baseName = fullFilename
            }
        } else {
            baseDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
            let titleURL = URL(fileURLWithPath: title)
            let fullFilename = titleURL.deletingPathExtension().lastPathComponent
            ext = titleURL.pathExtension.isEmpty ? "png" : titleURL.pathExtension
            if !fullFilename.isEmpty && fullFilename != "Impact" && fullFilename != "Shots Editor" {
                if let regex = EditorPanel.numberedSuffixRegex,
                   let match = regex.firstMatch(in: fullFilename, range: NSRange(fullFilename.startIndex..., in: fullFilename)) {
                    let nameRange = Range(match.range(at: 1), in: fullFilename)!
                    baseName = String(fullFilename[nameRange])
                } else {
                    baseName = fullFilename
                }
            } else {
                baseName = "Annotation"
            }
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
        let format: NSBitmapImageRep.FileType
        switch ext {
        case "jpg", "jpeg":
            format = .jpeg
        case "png":
            format = .png
        case "tiff", "tif":
            format = .tiff
        case "gif":
            format = .gif
        case "bmp":
            format = .bmp
        default:
            format = .png
        }
        canvasView.saveCompositionToFile(url: targetURL, format: format)
        hasSavedComposition = true
        return targetURL
    }

    private func setupContentView() {
        guard let container = contentView else { return }
        container.wantsLayer = true

        // 1. Top Menubar glued to top of app
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbarView)

        // 2. Scroll View holding the elastic canvas (takes whatever is left of the space)
        let scrollView = EditorScrollView()
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

        // 3. Welcome / Empty state view with "Drag or click to open" (only attached when in empty state)
        if !hasImage {
            setupWelcomeDropView()
        }

        scrollView.isHidden = !hasImage

        updateVersionTitle()
        self.metaLabel = toolbarView.metaLabel

        NSLayoutConstraint.activate([
            toolbarView.topAnchor.constraint(equalTo: container.topAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 44),

            scrollView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        updateMetaLabel()

        document.onBoundsChanged = { [weak self, weak scrollView] bounds in
            guard let self = self, let sv = scrollView else { return }
            self.canvasView.frame = NSRect(origin: .zero, size: bounds.size)
            sv.documentView?.needsDisplay = true
            self.updateMetaLabel()
        }

        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let sv = self.scrollView else { return }
            if abs(self.canvasView.zoomScale - sv.magnification) > 0.001 {
                self.canvasView.zoomScale = sv.magnification
                self.updateMetaLabel()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let sv = self.scrollView else { return }
            self.canvasView.zoomScale = sv.magnification
            self.updateMetaLabel()
            self.canvasView.needsDisplay = true
        }
    }

    public func setupWelcomeDropView() {
        guard welcomeDropView == nil, let container = contentView else { return }
        let dropView = WelcomeDropView(frame: NSRect(origin: .zero, size: container.bounds.size))
        dropView.translatesAutoresizingMaskIntoConstraints = false
        dropView.openButton.onAction = {
            ImpactAppCoordinator.shared.openImageFileDialog()
        }
        container.addSubview(dropView)
        self.welcomeDropView = dropView

        NSLayoutConstraint.activate([
            dropView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            dropView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dropView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            dropView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    public static let defaultVersionTitle: String = {
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
        return "Impact v\(versionStr) (Build \(buildStr))"
    }()

    public func updateVersionTitle() {
        self.title = EditorPanel.defaultVersionTitle
    }

    /// Loads an image directly into the main window, transitioning from empty state
    public func loadImage(image: CGImage, title: String = "Impact", sourceFileURL: URL? = nil) {
        self.sourceFileURL = sourceFileURL
        let newDoc = EditorDocument(image: image)
        self.document = newDoc
        self.canvasView.setDocument(newDoc)
        self.hasImage = true
        self.hasSavedComposition = false

        welcomeDropView?.removeFromSuperview()
        welcomeDropView = nil
        scrollView?.isHidden = false

        newDoc.onBoundsChanged = { [weak self, weak scrollView] bounds in
            guard let self = self, let sv = scrollView else { return }
            self.canvasView.frame = NSRect(origin: .zero, size: bounds.size)
            sv.documentView?.needsDisplay = true
            self.updateMetaLabel()
        }

        // Adjust window size to fit image if smaller than viewport
        let visibleFrame = (self.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxW = visibleFrame.width * 0.85
        let maxH = visibleFrame.height * 0.85
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        let windowW = min(maxW, max(frame.width, max(600.0, imgW + 40.0)))
        let windowH = min(maxH, max(frame.height, max(400.0, imgH + 80.0)))

        let currentMidX = frame.midX
        let currentMidY = frame.midY
        let newX = max(visibleFrame.minX, min(currentMidX - windowW / 2.0, visibleFrame.maxX - windowW))
        let newY = max(visibleFrame.minY, min(currentMidY - windowH / 2.0, visibleFrame.maxY - windowH))
        setFrame(NSRect(x: newX, y: newY, width: windowW, height: windowH), display: true, animate: true)

        updateVersionTitle()
        updateMetaLabel()
        scaleToFit()

        toolbarView.layoutSubtreeIfNeeded()
        toolbarView.updateResponsiveOverflow()

        NSCursor.arrow.set()
        if let cv = contentView {
            invalidateCursorRects(for: cv)
        }
        invalidateCursorRects(for: canvasView)

        if EditorPanel.isCopyToClipboardEnabled {
            canvasView.copyCompositionToClipboard()
            showCopiedToClipboardToast()
        }
    }

    /// Scales the image: if smaller than viewport, center at 100% (1.0). If larger, scale to best fit centered.
    public func scaleToFit() {
        guard let sv = scrollView, hasImage else { return }
        sv.layoutSubtreeIfNeeded()

        let viewport = sv.contentView.frame.size
        guard viewport.width > 0 && viewport.height > 0 else { return }

        let imgW = document.activeCanvasBounds.width
        let imgH = document.activeCanvasBounds.height
        guard imgW > 0 && imgH > 0 else { return }

        let padding: CGFloat = 32.0
        let availableW = max(50.0, viewport.width - padding)
        let availableH = max(50.0, viewport.height - padding)

        if imgW <= availableW && imgH <= availableH {
            // If image is smaller than available viewport, show it at 100% scale
            sv.magnification = 1.0
        } else {
            // If image is larger than available viewport, scale it to best fit centered
            let fitScale = min(availableW / imgW, availableH / imgH)
            sv.magnification = max(sv.minMagnification, fitScale)
        }

        let docW = canvasView.frame.width
        let docH = canvasView.frame.height
        let visibleW = viewport.width / sv.magnification
        let visibleH = viewport.height / sv.magnification
        let centerX = (docW - visibleW) / 2.0
        let centerY = (docH - visibleH) / 2.0
        sv.contentView.scroll(to: NSPoint(x: centerX, y: centerY))
        sv.reflectScrolledClipView(sv.contentView)

        canvasView.zoomScale = sv.magnification
        updateMetaLabel()
        canvasView.needsDisplay = true
    }

    public func zoomIn() {
        guard let sv = scrollView, hasImage else { return }
        let newMag = min(sv.maxMagnification, sv.magnification * 1.25)
        sv.setMagnification(newMag, centeredAt: NSPoint(x: sv.contentView.bounds.midX, y: sv.contentView.bounds.midY))
        canvasView.zoomScale = sv.magnification
        updateMetaLabel()
    }

    public func zoomOut() {
        guard let sv = scrollView, hasImage else { return }
        let newMag = max(sv.minMagnification, sv.magnification / 1.25)
        sv.setMagnification(newMag, centeredAt: NSPoint(x: sv.contentView.bounds.midX, y: sv.contentView.bounds.midY))
        canvasView.zoomScale = sv.magnification
        updateMetaLabel()
    }

    public func resetZoom() {
        guard let sv = scrollView, hasImage else { return }
        sv.setMagnification(1.0, centeredAt: NSPoint(x: sv.contentView.bounds.midX, y: sv.contentView.bounds.midY))
        canvasView.zoomScale = sv.magnification
        updateMetaLabel()
    }

    public func setZoom(scale: CGFloat) {
        guard let sv = scrollView, hasImage else { return }
        let clamped = max(sv.minMagnification, min(sv.maxMagnification, scale))
        sv.setMagnification(clamped, centeredAt: NSPoint(x: sv.contentView.bounds.midX, y: sv.contentView.bounds.midY))
        canvasView.zoomScale = sv.magnification
        updateMetaLabel()
    }

    public func updateMetaLabel() {
        guard hasImage else {
            toolbarView.metaLabel.stringValue = ""
            return
        }
        let zoomPercent = Int(round((scrollView?.magnification ?? 1.0) * 100))
        toolbarView.updateMeta(bounds: document.activeCanvasBounds, zoomPercent: zoomPercent)
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

        toolbarView.onZoomResetRequested = { [weak self] in
            self?.resetZoom()
        }

        toolbarView.onZoomFitRequested = { [weak self] in
            self?.scaleToFit()
        }

        toolbarView.onZoomSetRequested = { [weak self] scale in
            self?.setZoom(scale: scale)
        }

        toolbarView.onSaveRequested = { [weak self] in
            guard let self = self, self.hasImage else { return }
            if let savedURL = self.saveToNextNumberedFile() {
                NSLog("Impact: Saved composition to %@", savedURL.path)
                self.showImageSavedToast()
            }
            // Explicitly keep the editor panel open and active
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        toolbarView.onOpenRequested = {
            ImpactAppCoordinator.shared.openImageFileDialog()
        }

        toolbarView.onCopyRequested = { [weak self] in
            guard let self = self, self.hasImage else { return }
            self.canvasView.copyCompositionToClipboard()
            self.showCopiedToClipboardToast()
        }
    }

    public func showCopiedToClipboardToast() {
        guard let container = contentView else { return }
        EditorToastView.show(in: container, below: toolbarView, text: "Copied to Clipboard")
    }

    public func showImageSavedToast() {
        guard let container = contentView else { return }
        EditorToastView.show(in: container, below: toolbarView, text: "Image Saved")
    }

    override public func magnify(with event: NSEvent) {
        canvasView.magnify(with: event)
    }

    override public func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            handleZoomWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    public func handleZoomWheel(with event: NSEvent) {
        guard let sv = scrollView else { return }

        let delta: CGFloat
        if event.hasPreciseScrollingDeltas {
            delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
        } else {
            delta = event.deltaY != 0 ? event.deltaY : event.scrollingDeltaY
        }
        guard delta != 0 else { return }

        let factor: CGFloat
        if event.hasPreciseScrollingDeltas {
            factor = pow(1.008, delta)
        } else {
            let steps = event.deltaY != 0 ? event.deltaY : (delta > 0 ? 1.0 : -1.0)
            factor = pow(1.15, steps)
        }

        let oldMag = sv.magnification
        let newMag = max(sv.minMagnification, min(sv.maxMagnification, oldMag * factor))
        guard newMag != oldMag else { return }

        let clipBounds = sv.contentView.bounds
        let location = event.locationInWindow
        let clipPoint = sv.contentView.convert(location, from: nil)
        let anchor = clipBounds.contains(clipPoint) ? clipPoint : NSPoint(x: clipBounds.midX, y: clipBounds.midY)

        sv.setMagnification(newMag, centeredAt: anchor)
        canvasView.zoomScale = sv.magnification
        updateMetaLabel()
    }
    // MARK: - Drag and Drop Support

    private var dropOverlay: DropOverlayView?

    public func showDropTargetOverlay(_ show: Bool) {
        guard hasImage else { return }
        if show {
            if dropOverlay == nil {
                guard let container = contentView else { return }
                let overlay = DropOverlayView()
                overlay.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(overlay, positioned: .above, relativeTo: nil)
                NSLayoutConstraint.activate([
                    overlay.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                    overlay.centerYAnchor.constraint(equalTo: container.centerYAnchor)
                ])
                self.dropOverlay = overlay
            }
        } else {
            dropOverlay?.removeFromSuperview()
            dropOverlay = nil
        }
    }

    public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if extractImageURL(from: sender) != nil {
            showDropTargetOverlay(true)
            return .copy
        }
        return []
    }

    public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return extractImageURL(from: sender) != nil ? .copy : []
    }

    public func draggingExited(_ sender: NSDraggingInfo?) {
        showDropTargetOverlay(false)
    }

    public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        showDropTargetOverlay(false)
        guard let url = extractImageURL(from: sender) else { return false }
        ImpactAppCoordinator.shared.openImageFile(url: url)
        return true
    }

    private func extractImageURL(from sender: NSDraggingInfo) -> URL? {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let first = urls.first else {
            return nil
        }
        let ext = first.pathExtension.lowercased()
        return WelcomeDropView.supportedExtensions.contains(ext) ? first : nil
    }
}

/// An NSScrollView subclass that forwards Cmd + mousewheel events to zoom handling and supports drag & drop
final class EditorScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func magnify(with event: NSEvent) {
        if let doc = documentView as? EditorCanvasView {
            doc.magnify(with: event)
        } else {
            super.magnify(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            (window as? EditorPanel)?.handleZoomWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if extractImageURL(from: sender) != nil {
            (window as? EditorPanel)?.showDropTargetOverlay(true)
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return extractImageURL(from: sender) != nil ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        (window as? EditorPanel)?.showDropTargetOverlay(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        (window as? EditorPanel)?.showDropTargetOverlay(false)
        guard let url = extractImageURL(from: sender) else { return false }
        ImpactAppCoordinator.shared.openImageFile(url: url)
        return true
    }

    private func extractImageURL(from sender: NSDraggingInfo) -> URL? {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let first = urls.first else {
            return nil
        }
        let ext = first.pathExtension.lowercased()
        return WelcomeDropView.supportedExtensions.contains(ext) ? first : nil
    }
}

/// HUD Overlay shown when dragging an image file over EditorPanel
final class DropOverlayView: NSVisualEffectView {
    init() {
        super.init(frame: .zero)
        material = .hudWindow
        state = .active
        blendingMode = .withinWindow
        wantsLayer = true
        layer?.cornerRadius = 14.0
        layer?.masksToBounds = true
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 0.95).cgColor

        let iconView = NSImageView()
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 26, weight: .medium)
            iconView.image = NSImage(systemSymbolName: "arrow.down.doc.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
        }
        iconView.contentTintColor = NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        let label = NSTextField(labelWithString: "Drop image to open in Impact")
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),

            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            (window as? EditorPanel)?.handleZoomWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }
}
