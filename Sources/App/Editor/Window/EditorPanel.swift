import Foundation
import CoreGraphics
import AppKit

public final class EditorPanel: NSPanel {
    public let document: EditorDocument
    public let canvasView: EditorCanvasView
    public let toolbarView: EditorToolbarView

    private var metaLabel: NSTextField?
    private var isPinned: Bool = false

    public init(document: EditorDocument, title: String = "Shots Editor") {
        self.document = document
        self.canvasView = EditorCanvasView(document: document)
        self.toolbarView = EditorToolbarView(canvasView: canvasView)

        // Calculate appropriate window size based on image dimensions and active screen
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let maxW = screen.visibleFrame.width * 0.85
        let maxH = screen.visibleFrame.height * 0.85

        let imgW = document.activeCanvasBounds.width
        let imgH = document.activeCanvasBounds.height

        let windowW = min(maxW, max(640.0, imgW + 40.0))
        let windowH = min(maxH, max(480.0, imgH + 110.0))

        let initialX = screen.visibleFrame.midX - windowW / 2.0
        let initialY = screen.visibleFrame.midY - windowH / 2.0

        let contentRect = NSRect(x: initialX, y: initialY, width: windowW, height: windowH)

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Floating level per Section 1
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = NSColor(white: 0.14, alpha: 0.98)
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        setupContentView()
        setupToolbarActions()
    }

    private func setupContentView() {
        guard let container = contentView else { return }
        container.wantsLayer = true

        // 1. Scroll View holding the elastic canvas
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = NSColor(white: 0.10, alpha: 1.0)
        scrollView.documentView = canvasView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        // 2. Floating Toolbar at the bottom
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbarView)

        // 3. Header Info Bar at the top (Meta info: dimensions, zoom, color)
        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerView)

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

            meta.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            meta.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            toolbarView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toolbarView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            toolbarView.heightAnchor.constraint(equalToConstant: 48)
        ])

        document.onBoundsChanged = { [weak self, weak scrollView] bounds in
            guard let self = self, let sv = scrollView else { return }
            self.canvasView.frame = NSRect(origin: .zero, size: bounds.size)
            sv.documentView?.needsDisplay = true
            self.metaLabel?.stringValue = "\(Int(bounds.width)) × \(Int(bounds.height)) px"
        }
    }

    private func setupToolbarActions() {
        toolbarView.onPinToggle = { [weak self] pinned in
            guard let self = self else { return }
            self.isPinned = pinned
            self.level = pinned ? .screenSaver : .floating
            self.hidesOnDeactivate = !pinned
        }

        toolbarView.onSaveRequested = { [weak self] in
            guard let self = self else { return }
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.png, .jpeg]
            savePanel.nameFieldStringValue = "Annotation_\(Int(Date().timeIntervalSince1970)).png"
            if savePanel.runModal() == .OK, let url = savePanel.url {
                let format: NSBitmapImageRep.FileType = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg" ? .jpeg : .png
                self.canvasView.saveCompositionToFile(url: url, format: format)
            }
        }

        toolbarView.onCopyRequested = {
            NSSound(named: "Tink")?.play()
        }
    }
}
