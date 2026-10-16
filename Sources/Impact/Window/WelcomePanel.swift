import Foundation
import CoreGraphics
import AppKit
import UniformTypeIdentifiers

// MARK: - Welcome / Empty State Panel

public final class WelcomePanel: NSPanel {
    public var onClose: (() -> Void)?
    public let dropView: WelcomeDropView

    public init() {
        let width: CGFloat = 520
        let height: CGFloat = 360
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let x = screen.visibleFrame.midX - width / 2.0
        let y = screen.visibleFrame.midY - height / 2.0
        let contentRect = NSRect(x: x, y: y, width: width, height: height)

        self.dropView = WelcomeDropView(frame: NSRect(origin: .zero, size: contentRect.size))

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = NSColor(white: 0.12, alpha: 0.98)
        hasShadow = true
        level = .normal
        hidesOnDeactivate = false
        collectionBehavior = [.managed, .participatesInCycle, .fullScreenPrimary]

        setupContentView()
    }

    private func setupContentView() {
        guard let container = contentView else { return }
        container.wantsLayer = true

        let visualEffect = NSVisualEffectView(frame: container.bounds)
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.autoresizingMask = [.width, .height]
        container.addSubview(visualEffect)

        dropView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(dropView)

        NSLayoutConstraint.activate([
            dropView.topAnchor.constraint(equalTo: container.topAnchor),
            dropView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dropView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            dropView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { true }

    override public func close() {
        super.close()
        onClose?()
    }

    override public func cancelOperation(_ sender: Any?) {
        close()
    }

    override public func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            close()
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "o" {
            ImpactAppCoordinator.shared.openImageFileDialog()
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "w" {
            close()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Welcome Drop View & Call To Action

public final class WelcomeDropView: NSView {
    public static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tiff", "tif", "heic", "webp", "gif", "bmp"
    ]

    public var isDragTarget: Bool = false {
        didSet {
            if oldValue != isDragTarget {
                needsDisplay = true
            }
        }
    }

    public var isHovered: Bool = false {
        didSet {
            if oldValue != isHovered {
                openButton.isHovered = isHovered
                needsDisplay = true
            }
        }
    }

    private let iconImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Drag and drop an image here")
    private let subtitleLabel = NSTextField(labelWithString: "or click anywhere to browse")
    private let formatsLabel = NSTextField(labelWithString: "Supports PNG, JPEG, TIFF, HEIC, WebP, GIF")
    public let openButton = WelcomePillButton()
    private var trackingArea: NSTrackingArea?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
        setupUI()
    }

    private func setupUI() {
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 42, weight: .light)
            iconImageView.image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: "Open Image")?
                .withSymbolConfiguration(config)
        }
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.contentTintColor = NSColor(white: 0.85, alpha: 1.0)
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconImageView)

        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = NSColor(white: 0.65, alpha: 1.0)
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.onAction = {
            ImpactAppCoordinator.shared.openImageFileDialog()
        }
        addSubview(openButton)

        formatsLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        formatsLabel.textColor = NSColor(white: 0.42, alpha: 1.0)
        formatsLabel.alignment = .center
        formatsLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(formatsLabel)

        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.topAnchor.constraint(equalTo: topAnchor, constant: 58),
            iconImageView.widthAnchor.constraint(equalToConstant: 48),
            iconImageView.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),

            subtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),

            openButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            openButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 18),
            openButton.widthAnchor.constraint(equalToConstant: 148),
            openButton.heightAnchor.constraint(equalToConstant: 34),

            formatsLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            formatsLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -38)
        ])
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.pointingHand.set()
    }

    override public func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.arrow.set()
    }

    override public func mouseDown(with event: NSEvent) {
        ImpactAppCoordinator.shared.openImageFileDialog()
    }

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let dropRect = bounds.insetBy(dx: 22, dy: 22)
        let cornerRadius: CGFloat = 16.0
        let path = NSBezierPath(roundedRect: dropRect, xRadius: cornerRadius, yRadius: cornerRadius)

        if isDragTarget {
            NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 0.14).setFill()
            path.fill()

            let strokeColor = NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 0.95)
            strokeColor.setStroke()
            let pattern: [CGFloat] = [6.0, 4.0]
            path.setLineDash(pattern, count: pattern.count, phase: 0.0)
            path.lineWidth = 2.0
            path.stroke()

            iconImageView.contentTintColor = strokeColor
        } else {
            let fillColor = isHovered ? NSColor(white: 0.15, alpha: 0.85) : NSColor(white: 0.13, alpha: 0.70)
            fillColor.setFill()
            path.fill()

            let strokeColor = isHovered ? NSColor(white: 0.40, alpha: 0.85) : NSColor(white: 0.25, alpha: 0.70)
            strokeColor.setStroke()
            let pattern: [CGFloat] = [6.0, 4.0]
            path.setLineDash(pattern, count: pattern.count, phase: 0.0)
            path.lineWidth = 1.5
            path.stroke()

            iconImageView.contentTintColor = isHovered ? NSColor.white : NSColor(white: 0.80, alpha: 1.0)
        }
    }

    // MARK: - Drag and Drop Handling

    public func extractImageURL(from sender: NSDraggingInfo) -> URL? {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let first = urls.first else {
            return nil
        }
        let ext = first.pathExtension.lowercased()
        return Self.supportedExtensions.contains(ext) ? first : nil
    }

    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if extractImageURL(from: sender) != nil {
            isDragTarget = true
            return .copy
        }
        return []
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if extractImageURL(from: sender) != nil {
            return .copy
        }
        return []
    }

    override public func draggingExited(_ sender: NSDraggingInfo?) {
        isDragTarget = false
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragTarget = false
        guard let url = extractImageURL(from: sender) else { return false }
        ImpactAppCoordinator.shared.openImageFile(url: url)
        return true
    }
}

// MARK: - Welcome Pill Button

public final class WelcomePillButton: NSView {
    public var onAction: (() -> Void)?
    private let titleLabel = NSTextField(labelWithString: "Open Image…")
    private let iconImageView = NSImageView()

    public var isHovered: Bool = false {
        didSet { updateVisuals() }
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 8.0
        layer?.masksToBounds = true
        layer?.borderWidth = 1.0

        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            iconImageView.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Open")?
                .withSymbolConfiguration(config)
        }
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconImageView)

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 16),
            iconImageView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateVisuals()
    }

    public func updateVisuals() {
        if isHovered {
            layer?.backgroundColor = NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 0.90).cgColor
            layer?.borderColor = NSColor(srgbRed: 0.20, green: 0.60, blue: 1.0, alpha: 1.0).cgColor
            iconImageView.contentTintColor = .white
            titleLabel.textColor = .white
        } else {
            layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.90).cgColor
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
            iconImageView.contentTintColor = NSColor(white: 0.90, alpha: 1.0)
            titleLabel.textColor = NSColor(white: 0.90, alpha: 1.0)
        }
    }

    override public func mouseDown(with event: NSEvent) {
        onAction?()
    }
}
