import Foundation
import CoreGraphics
import AppKit

// MARK: - Modern Toolbar Button

public final class ModernToolbarButton: NSView {
    public var tooltipText: String
    public var onAction: (() -> Void)?

    private let iconImageView = NSImageView()
    public let titleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    public private(set) var isSegment: Bool = false

    public var isHovered: Bool = false {
        didSet { updateVisuals() }
    }

    public var isActive: Bool = false {
        didSet { updateVisuals() }
    }

    public var isPressed: Bool = false {
        didSet { updateVisuals() }
    }

    public init(
        systemName: String? = nil,
        text: String? = nil,
        tooltip: String,
        size: NSSize = NSSize(width: 30, height: 30),
        pointSize: CGFloat = 13.0,
        weight: NSFont.Weight = .semibold,
        isSegment: Bool = false
    ) {
        self.tooltipText = tooltip
        self.isSegment = isSegment
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = isSegment ? 0.0 : 6.0
        layer?.masksToBounds = true

        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconImageView)

        titleLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.textColor = NSColor(white: 0.82, alpha: 1.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let iconW = min(18.0, max(12.0, size.width - 6.0))
        let iconH = min(18.0, max(12.0, size.height - 6.0))

        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: iconW),
            iconImageView.heightAnchor.constraint(equalToConstant: iconH),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),

            widthAnchor.constraint(equalToConstant: size.width),
            heightAnchor.constraint(equalToConstant: size.height)
        ])

        if let text = text {
            iconImageView.isHidden = true
            titleLabel.isHidden = false
            titleLabel.stringValue = text
        } else {
            titleLabel.isHidden = true
            iconImageView.isHidden = false
            if let sysName = systemName {
                setIcon(systemName: sysName, pointSize: pointSize, weight: weight)
            }
        }
        updateVisuals()
    }

    public convenience init(systemName: String, tooltip: String, pointSize: CGFloat = 13.0, weight: NSFont.Weight = .semibold) {
        self.init(systemName: systemName, text: nil, tooltip: tooltip, size: NSSize(width: 30, height: 30), pointSize: pointSize, weight: weight, isSegment: false)
    }

    public static let ufoPointerIcon: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale: CGFloat = 13.0 / 62.0
            let ox: CGFloat = 5.0
            let oy: CGFloat = 3.5
            let p0 = CGPoint(x: ox + 0 * scale, y: oy + 0 * scale)
            let p1 = CGPoint(x: ox + 0 * scale, y: oy + 62 * scale)
            let p2 = CGPoint(x: ox + 19 * scale, y: oy + 47 * scale)
            let p3 = CGPoint(x: ox + 46 * scale, y: oy + 45 * scale)

            ctx.beginPath()
            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.addLine(to: p2)
            ctx.addLine(to: p3)
            ctx.closePath()
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            return true
        }
        img.isTemplate = true
        return img
    }()

    public convenience init(image: NSImage, tooltip: String) {
        self.init(systemName: "circle", text: nil, tooltip: tooltip, size: NSSize(width: 30, height: 30), pointSize: 13.0, weight: .semibold, isSegment: false)
        image.isTemplate = true
        self.iconImageView.image = image
        updateVisuals()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setTitle(_ newTitle: String) {
        titleLabel.stringValue = newTitle
        titleLabel.isHidden = false
        iconImageView.isHidden = true
    }

    public func setIcon(systemName: String, pointSize: CGFloat = 13.0, weight: NSFont.Weight = .semibold) {
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            var img = NSImage(systemSymbolName: systemName, accessibilityDescription: tooltipText)
            if img == nil {
                img = NSImage(systemSymbolName: "circle", accessibilityDescription: tooltipText)
            }
            iconImageView.image = img?.withSymbolConfiguration(config)
        }
    }

    private func updateVisuals() {
        if isActive {
            // Active state: Solid Apple system accent blue + pure white icon/text
            layer?.backgroundColor = isHovered
                ? NSColor(srgbRed: 0.10, green: 0.54, blue: 1.0, alpha: 1.0).cgColor
                : NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 0.95).cgColor
            layer?.borderColor = isSegment ? NSColor.clear.cgColor : NSColor.white.withAlphaComponent(0.20).cgColor
            layer?.borderWidth = isSegment ? 0.0 : 0.5
            iconImageView.contentTintColor = .white
            titleLabel.textColor = .white
        } else if isPressed {
            // Pressed state: Darker highlight
            layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.22).cgColor
            layer?.borderColor = NSColor.clear.cgColor
            layer?.borderWidth = 0.0
            iconImageView.contentTintColor = .white
            titleLabel.textColor = .white
        } else if isHovered {
            // Hover effect: Frosted light highlight pill + white icon/text
            layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.14).cgColor
            layer?.borderColor = isSegment ? NSColor.clear.cgColor : NSColor(white: 1.0, alpha: 0.12).cgColor
            layer?.borderWidth = isSegment ? 0.0 : 0.5
            iconImageView.contentTintColor = .white
            titleLabel.textColor = .white
        } else {
            // Normal state: Transparent + soft white icon/text
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = NSColor.clear.cgColor
            layer?.borderWidth = 0.0
            iconImageView.contentTintColor = NSColor(white: 0.82, alpha: 1.0)
            titleLabel.textColor = NSColor(white: 0.82, alpha: 1.0)
        }
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
        EditorTooltipWindow.shared.schedule(text: tooltipText, for: self)
    }

    override public func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        NSCursor.arrow.set()
        EditorTooltipWindow.shared.hide()
    }

    override public func mouseDown(with event: NSEvent) {
        isPressed = true
        EditorTooltipWindow.shared.hide()
    }

    override public func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if inside {
            onAction?()
        }
    }
}

// MARK: - Modern Color Swatch Button (for Popout Grid)

public final class ModernColorButton: NSView {
    public let hex: String
    public var tooltipText: String
    public var onSelect: (() -> Void)?

    private let dotView = NSView()
    private let ringView = NSView()
    private var trackingArea: NSTrackingArea?

    public var isHovered: Bool = false {
        didSet { updateVisuals() }
    }

    public var isActive: Bool = false {
        didSet { updateVisuals() }
    }

    public init(hex: String, name: String) {
        self.hex = hex
        self.tooltipText = name
        super.init(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        wantsLayer = true

        // Outer selection ring (matches screenshot highlight ring around active swatch)
        ringView.wantsLayer = true
        ringView.layer?.cornerRadius = 10.0
        ringView.layer?.borderWidth = 2.0
        ringView.layer?.borderColor = NSColor.clear.cgColor
        ringView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ringView)

        // Color swatch rounded square
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 7.0
        dotView.layer?.masksToBounds = true
        dotView.layer?.backgroundColor = NSColor(hex: hex).cgColor
        if hex.uppercased() == "#FFFFFF" {
            dotView.layer?.borderWidth = 1.0
            dotView.layer?.borderColor = NSColor(white: 0.45, alpha: 1.0).cgColor
        } else if hex.uppercased() == "#1E272E" {
            dotView.layer?.borderWidth = 1.0
            dotView.layer?.borderColor = NSColor(white: 0.30, alpha: 1.0).cgColor
        }
        dotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 36),
            heightAnchor.constraint(equalToConstant: 36),

            ringView.centerXAnchor.constraint(equalTo: centerXAnchor),
            ringView.centerYAnchor.constraint(equalTo: centerYAnchor),
            ringView.widthAnchor.constraint(equalToConstant: 36),
            ringView.heightAnchor.constraint(equalToConstant: 36),

            dotView.centerXAnchor.constraint(equalTo: centerXAnchor),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 28),
            dotView.heightAnchor.constraint(equalToConstant: 28)
        ])

        updateVisuals()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateVisuals() {
        if isActive {
            if hex.uppercased() == "#FF3B30" {
                ringView.layer?.borderColor = NSColor(srgbRed: 1.0, green: 0.60, blue: 0.58, alpha: 0.95).cgColor
            } else if hex.uppercased() == "#FFFFFF" {
                ringView.layer?.borderColor = NSColor(white: 0.85, alpha: 0.95).cgColor
            } else {
                ringView.layer?.borderColor = NSColor(hex: hex).withAlphaComponent(0.85).cgColor
            }
        } else if isHovered {
            ringView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.40).cgColor
        } else {
            ringView.layer?.borderColor = NSColor.clear.cgColor
        }
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
        EditorTooltipWindow.shared.schedule(text: tooltipText, for: self)
    }

    override public func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.arrow.set()
        EditorTooltipWindow.shared.hide()
    }

    override public func mouseDown(with event: NSEvent) {
        EditorTooltipWindow.shared.hide()
    }

    override public func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside {
            onSelect?()
        }
    }
}

// MARK: - Modern Single Color Button (in Toolbar)

public final class ModernSingleColorButton: NSView {
    public private(set) var currentColor: String = "#FF3B30"
    public var onAction: (() -> Void)?

    private let swatchView = NSView()
    private var trackingArea: NSTrackingArea?

    public var isHovered: Bool = false {
        didSet { updateVisuals() }
    }

    public init(initialColor: String = "#FF3B30") {
        self.currentColor = initialColor
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        wantsLayer = true
        layer?.cornerRadius = 6.0
        layer?.masksToBounds = true

        swatchView.wantsLayer = true
        swatchView.layer?.cornerRadius = 5.5
        swatchView.layer?.masksToBounds = true
        swatchView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swatchView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 30),

            swatchView.centerXAnchor.constraint(equalTo: centerXAnchor),
            swatchView.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatchView.widthAnchor.constraint(equalToConstant: 20),
            swatchView.heightAnchor.constraint(equalToConstant: 20)
        ])

        updateColor(hex: initialColor)
        updateVisuals()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func updateColor(hex: String) {
        self.currentColor = hex
        swatchView.layer?.backgroundColor = NSColor(hex: hex).cgColor
        if hex.uppercased() == "#FFFFFF" {
            swatchView.layer?.borderWidth = 1.0
            swatchView.layer?.borderColor = NSColor(white: 0.45, alpha: 1.0).cgColor
        } else {
            swatchView.layer?.borderWidth = 1.0
            swatchView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.20).cgColor
        }
        updateVisuals()
    }

    private func updateVisuals() {
        if isHovered {
            layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
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
        EditorTooltipWindow.shared.schedule(text: "Color Swatch", for: self)
    }

    override public func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.arrow.set()
        EditorTooltipWindow.shared.hide()
    }

    override public func mouseDown(with event: NSEvent) {
        EditorTooltipWindow.shared.hide()
    }

    override public func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside {
            onAction?()
        }
    }
}

// MARK: - Color Popout View Controller

public final class ColorPopoutViewController: NSViewController {
    public var onColorSelected: ((String) -> Void)?
    public var selectedColor: String = "#FF3B30" {
        didSet { updateSwatchStates() }
    }

    public internal(set) var swatchButtons: [ModernColorButton] = []

    override public func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 196, height: 104))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.98).cgColor
        container.layer?.cornerRadius = 14.0

        let gridStack = NSStackView()
        gridStack.orientation = .vertical
        gridStack.alignment = .centerX
        gridStack.spacing = 8.0
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(gridStack)

        NSLayoutConstraint.activate([
            gridStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            gridStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            gridStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            gridStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12)
        ])

        let swatches = EditorToolbarView.predefinedSwatches
        let row0 = Array(swatches.prefix(4))
        let row1 = Array(swatches.suffix(from: 4))

        for rowItems in [row0, row1] {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.alignment = .centerY
            rowStack.spacing = 8.0
            for item in rowItems {
                let btn = ModernColorButton(hex: item.hex, name: item.name)
                btn.onSelect = { [weak self] in
                    self?.onColorSelected?(item.hex)
                }
                swatchButtons.append(btn)
                rowStack.addArrangedSubview(btn)
            }
            gridStack.addArrangedSubview(rowStack)
        }

        self.view = container
        self.preferredContentSize = NSSize(width: 196, height: 104)
        updateSwatchStates()
    }

    public func updateSwatchStates() {
        let active = selectedColor.uppercased()
        for btn in swatchButtons {
            btn.isActive = (btn.hex.uppercased() == active)
        }
    }
}

// MARK: - Editor Top Menubar View

public final class EditorToolbarView: NSVisualEffectView {
    public weak var canvasView: EditorCanvasView?

    public struct ToolDefinition {
        public let type: LayerType
        public let title: String
        public let iconName: String?
        public let customImage: NSImage?
        public let shortcut: String
        public let shortcutModifiers: NSEvent.ModifierFlags
        public let tooltip: String

        public init(
            type: LayerType,
            title: String,
            iconName: String?,
            customImage: NSImage? = nil,
            shortcut: String = "",
            shortcutModifiers: NSEvent.ModifierFlags = [],
            tooltip: String? = nil
        ) {
            self.type = type
            self.title = title
            self.iconName = iconName
            self.customImage = customImage
            self.shortcut = shortcut
            self.shortcutModifiers = shortcutModifiers
            self.tooltip = tooltip ?? (shortcut.isEmpty ? title : "\(title) [\(shortcut.uppercased())]")
        }

        public init(type: LayerType, iconName: String?, customImage: NSImage?, tooltip: String) {
            self.type = type
            self.iconName = iconName
            self.customImage = customImage
            self.tooltip = tooltip
            let parts = tooltip.split(separator: "[")
            let baseTitle = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
            self.title = baseTitle.isEmpty ? type.rawValue : baseTitle
            if let sc = parts.dropFirst().first?.replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespaces).lowercased() {
                self.shortcut = sc
            } else {
                self.shortcut = ""
            }
            self.shortcutModifiers = []
        }
    }

    /// Full suite of tools presented in the dropdown menu when narrow
    public let dropdownToolDefinitions: [ToolDefinition] = [
        ToolDefinition(type: .arrow, title: "Arrow", iconName: "arrow.up.right", shortcut: "a"),
        ToolDefinition(type: .line, title: "Line", iconName: "line.diagonal", shortcut: "l"),
        ToolDefinition(type: .rectangle, title: "Rectangle", iconName: "square", shortcut: "r"),
        ToolDefinition(type: .ellipse, title: "Oval", iconName: "circle", shortcut: "o"),
        ToolDefinition(type: .spotlight, title: "Spotlight", iconName: "camera.metering.spot", shortcut: "s"),
        ToolDefinition(type: .counter, title: "Counter", iconName: "number.circle.fill", shortcut: "c"),
        ToolDefinition(type: .pen, title: "Pen", iconName: "pencil.tip", shortcut: "p"),
        ToolDefinition(type: .highlighter, title: "Highlighter", iconName: "highlighter", shortcut: "h"),
        ToolDefinition(type: .blur, title: "Blur", iconName: "drop.fill", shortcut: "b"),
        ToolDefinition(type: .dimension, title: "Ruler", iconName: "ruler", shortcut: "m", tooltip: "Ruler [M]")
    ]

    public let collapsibleToolDefinitions: [ToolDefinition] = [
        ToolDefinition(type: .arrow, title: "Arrow", iconName: "arrow.up.right", shortcut: "a"),
        ToolDefinition(type: .line, title: "Line", iconName: "line.diagonal", shortcut: "l"),
        ToolDefinition(type: .rectangle, title: "Rectangle", iconName: "square", shortcut: "r"),
        ToolDefinition(type: .ellipse, title: "Oval", iconName: "circle", shortcut: "o"),
        ToolDefinition(type: .spotlight, title: "Spotlight", iconName: "camera.metering.spot", shortcut: "s"),
        ToolDefinition(type: .counter, title: "Counter", iconName: "number.circle.fill", shortcut: "c"),
        ToolDefinition(type: .pen, title: "Pen", iconName: "pencil.tip", shortcut: "p"),
        ToolDefinition(type: .highlighter, title: "Highlighter", iconName: "highlighter", shortcut: "h"),
        ToolDefinition(type: .blur, title: "Blur", iconName: "drop.fill", shortcut: "b"),
        ToolDefinition(type: .dimension, title: "Ruler", iconName: "ruler", shortcut: "m", tooltip: "Ruler [M]")
    ]

    public internal(set) var toolButtons: [LayerType: ModernToolbarButton] = [:]
    public internal(set) var overflowButton: ModernToolbarButton?
    public internal(set) var singleColorButton: ModernSingleColorButton?
    public internal(set) var colorStackView: NSStackView?
    public internal(set) var toolsSeparatorView: NSView?
    public internal(set) var zoomSeparatorView: NSView?
    public internal(set) var zoomContainerView: NSView?
    public internal(set) var zoomOutButton: ModernToolbarButton?
    public internal(set) var zoomPercentButton: ModernToolbarButton?
    public internal(set) var zoomInButton: ModernToolbarButton?
    public internal(set) var zoomFitButton: ModernToolbarButton?
    public internal(set) var zoomResetButton: ModernToolbarButton?
    public internal(set) var actionSeparatorView: NSView?
    public internal(set) var undoButton: ModernToolbarButton?
    public internal(set) var openButton: ModernToolbarButton?
    public internal(set) var copyButton: ModernToolbarButton?
    public internal(set) var saveButton: ModernToolbarButton?
    public internal(set) var pinButton: ModernToolbarButton?

    public static let predefinedSwatches: [(hex: String, name: String)] = [
        ("#FF3B30", "Red"),
        ("#7048E8", "Purple"),
        ("#FFCC00", "Yellow"),
        ("#FF2D55", "Pink"),
        ("#00B894", "Teal"),
        ("#007AFF", "Blue"),
        ("#1E272E", "Dark"),
        ("#FFFFFF", "White")
    ]
    public private(set) var colorPopover: NSPopover?

    public var onPinToggle: ((Bool) -> Void)?
    public var onOpenRequested: (() -> Void)?
    public var onSaveRequested: (() -> Void)?
    public var onCopyRequested: (() -> Void)?
    public var onZoomInRequested: (() -> Void)?
    public var onZoomOutRequested: (() -> Void)?
    public var onZoomResetRequested: (() -> Void)?
    public var onZoomFitRequested: (() -> Void)?
    public var onZoomSetRequested: ((CGFloat) -> Void)?

    private var isPinned: Bool = false
    public let metaLabel = NSTextField(labelWithString: "")

    public internal(set) var contentStackView: NSStackView?

    public init(canvasView: EditorCanvasView) {
        self.canvasView = canvasView
        super.init(frame: NSRect(x: 0, y: 0, width: 880, height: 44))
        material = .titlebar
        state = .active
        blendingMode = .withinWindow
        wantsLayer = true
        layer?.masksToBounds = true
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        canvasView.document.onSelectionChanged = { [weak self] in
            self?.updateSelectedToolVisuals()
        }

        setupMenubar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: 44)
    }

    override public var mouseDownCanMoveWindow: Bool { true }

    override public func layout() {
        super.layout()
        let availableW = max(0, bounds.width - 76 - 14)
        contentStackView?.frame = NSRect(x: 76, y: 0, width: availableW, height: bounds.height)
        updateResponsiveOverflow()
    }

    private func setupMenubar() {
        // Bottom hairline border separating menubar cleanly from canvas
        let bottomLine = NSView()
        bottomLine.wantsLayer = true
        bottomLine.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        bottomLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomLine)

        NSLayoutConstraint.activate([
            bottomLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomLine.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomLine.heightAnchor.constraint(equalToConstant: 1)
        ])

        // Main horizontal content stack view (frame-based layout so menu width does not constrain window resizing)
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 3.0
        stack.translatesAutoresizingMaskIntoConstraints = true
        stack.autoresizingMask = []
        addSubview(stack)
        self.contentStackView = stack
        let initialW = max(0, bounds.width - 76 - 14)
        stack.frame = NSRect(x: 76, y: 0, width: initialW, height: bounds.height)

        // 1. Tool buttons: Select [V] (ALWAYS VISIBLE)
        let selectBtn = ModernToolbarButton(image: ModernToolbarButton.ufoPointerIcon, tooltip: "Select [V]")
        selectBtn.onAction = { [weak self] in
            guard let self = self else { return }
            self.canvasView?.document.activeTool = .select
            self.updateSelectedToolVisuals()
        }
        toolButtons[.select] = selectBtn
        stack.addArrangedSubview(selectBtn)

        // Collapsible tools: Arrow [A], Line [L], Rectangle [R], Pen [P], Highlighter [H], Counter [C], Spotlight [S], Blur [B]
        for def in collapsibleToolDefinitions {
            let btn = ModernToolbarButton(systemName: def.iconName ?? "circle", tooltip: def.tooltip)
            btn.onAction = { [weak self] in
                guard let self = self else { return }
                self.canvasView?.document.activeTool = def.type
                self.updateSelectedToolVisuals()
            }
            toolButtons[def.type] = btn
            stack.addArrangedSubview(btn)
        }

        // 3-dots horizontal overflow button (hidden when all tools fit)
        let overflowBtn = ModernToolbarButton(systemName: "ellipsis", tooltip: "More Tools", pointSize: 13.0)
        overflowBtn.onAction = { [weak self] in
            self?.showOverflowMenu()
        }
        overflowBtn.isHidden = true
        self.overflowButton = overflowBtn
        stack.addArrangedSubview(overflowBtn)

        // Zoom Separator
        let zoomSep = createSeparator()
        self.zoomSeparatorView = zoomSep
        stack.addArrangedSubview(zoomSep)

        // 2. Compact Segmented Zoom Capsule: [-] [100% ▾] [+] [Fit] [1:1]
        let zoomCapsule = NSView()
        zoomCapsule.wantsLayer = true
        zoomCapsule.layer?.cornerRadius = 6.0
        zoomCapsule.layer?.masksToBounds = true
        zoomCapsule.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        zoomCapsule.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        zoomCapsule.layer?.borderWidth = 0.5
        zoomCapsule.translatesAutoresizingMaskIntoConstraints = false

        let zoomStack = NSStackView()
        zoomStack.orientation = .horizontal
        zoomStack.alignment = .centerY
        zoomStack.spacing = 0.0
        zoomStack.translatesAutoresizingMaskIntoConstraints = false
        zoomCapsule.addSubview(zoomStack)

        NSLayoutConstraint.activate([
            zoomStack.leadingAnchor.constraint(equalTo: zoomCapsule.leadingAnchor),
            zoomStack.trailingAnchor.constraint(equalTo: zoomCapsule.trailingAnchor),
            zoomStack.topAnchor.constraint(equalTo: zoomCapsule.topAnchor),
            zoomStack.bottomAnchor.constraint(equalTo: zoomCapsule.bottomAnchor),
            zoomCapsule.heightAnchor.constraint(equalToConstant: 26)
        ])

        let zoomOutBtn = ModernToolbarButton(systemName: "minus", tooltip: "Zoom Out [Cmd -]", size: NSSize(width: 24, height: 26), pointSize: 11.0, isSegment: true)
        zoomOutBtn.onAction = { [weak self] in
            self?.onZoomOutRequested?()
        }
        self.zoomOutButton = zoomOutBtn
        zoomStack.addArrangedSubview(zoomOutBtn)

        zoomStack.addArrangedSubview(createSegmentDivider())

        let zoomPercentBtn = ModernToolbarButton(text: "100%", tooltip: "Zoom Presets", size: NSSize(width: 44, height: 26), isSegment: true)
        zoomPercentBtn.onAction = { [weak self] in
            self?.showZoomPresetsMenu()
        }
        self.zoomPercentButton = zoomPercentBtn
        zoomStack.addArrangedSubview(zoomPercentBtn)

        zoomStack.addArrangedSubview(createSegmentDivider())

        let zoomInBtn = ModernToolbarButton(systemName: "plus", tooltip: "Zoom In [Cmd +]", size: NSSize(width: 24, height: 26), pointSize: 11.0, isSegment: true)
        zoomInBtn.onAction = { [weak self] in
            self?.onZoomInRequested?()
        }
        self.zoomInButton = zoomInBtn
        zoomStack.addArrangedSubview(zoomInBtn)

        zoomStack.addArrangedSubview(createSegmentDivider())

        let zoomFitBtn = ModernToolbarButton(systemName: "arrow.up.left.and.down.right.magnifyingglass", tooltip: "Best Fit [Cmd 1]", size: NSSize(width: 26, height: 26), pointSize: 11.0, isSegment: true)
        zoomFitBtn.onAction = { [weak self] in
            self?.onZoomFitRequested?()
        }
        self.zoomFitButton = zoomFitBtn
        zoomStack.addArrangedSubview(zoomFitBtn)

        zoomStack.addArrangedSubview(createSegmentDivider())

        let zoomResetBtn = ModernToolbarButton(systemName: "1.magnifyingglass", tooltip: "Actual Size (100%) [Cmd 0]", size: NSSize(width: 26, height: 26), pointSize: 11.0, isSegment: true)
        zoomResetBtn.onAction = { [weak self] in
            self?.onZoomResetRequested?()
        }
        self.zoomResetButton = zoomResetBtn
        zoomStack.addArrangedSubview(zoomResetBtn)

        self.zoomContainerView = zoomCapsule
        stack.addArrangedSubview(zoomCapsule)

        metaLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .medium)
        metaLabel.textColor = NSColor(white: 0.65, alpha: 1.0)
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(metaLabel)

        // Flexible spacer to right-align color swatch & action buttons
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)

        // 3. Right-aligned Single color picker button
        let initialHex = canvasView?.document.activeColor ?? "#FF3B30"
        let singleBtn = ModernSingleColorButton(initialColor: initialHex)
        singleBtn.onAction = { [weak self] in
            self?.showColorPopout()
        }
        self.singleColorButton = singleBtn

        let colorStack = NSStackView()
        colorStack.orientation = .horizontal
        colorStack.alignment = .centerY
        colorStack.spacing = 0
        colorStack.addArrangedSubview(singleBtn)
        self.colorStackView = colorStack
        stack.addArrangedSubview(colorStack)

        // Tools Separator (separates color swatch from action buttons)
        let toolsSep = createSeparator()
        self.toolsSeparatorView = toolsSep
        stack.addArrangedSubview(toolsSep)

        // Action Separator (separates spacer from action buttons when color swatch is hidden)
        let actionSep = createSeparator()
        self.actionSeparatorView = actionSep
        stack.addArrangedSubview(actionSep)

        // 4. Action Buttons: Undo [Cmd Z], Open [Cmd O], Copy [Cmd C], Save [Cmd S], Pin Window (Always on Top)
        let undoBtn = ModernToolbarButton(systemName: "arrow.uturn.backward", tooltip: "Undo [Cmd Z]", pointSize: 12.0)
        undoBtn.onAction = { [weak self] in
            self?.canvasView?.document.undo()
        }
        self.undoButton = undoBtn
        stack.addArrangedSubview(undoBtn)

        let openBtn = ModernToolbarButton(systemName: "folder", tooltip: "Open Image… [Cmd O]", pointSize: 12.0)
        openBtn.onAction = { [weak self] in
            self?.onOpenRequested?()
        }
        self.openButton = openBtn
        stack.addArrangedSubview(openBtn)

        let copyBtn = ModernToolbarButton(systemName: "doc.on.doc", tooltip: "Copy [Cmd C]", pointSize: 12.0)
        copyBtn.onAction = { [weak self] in
            self?.canvasView?.copyCompositionToClipboard()
            self?.onCopyRequested?()
        }
        self.copyButton = copyBtn
        stack.addArrangedSubview(copyBtn)

        let saveBtn = ModernToolbarButton(systemName: "square.and.arrow.down", tooltip: "Save [Cmd S]", pointSize: 12.0)
        saveBtn.onAction = { [weak self] in
            self?.onSaveRequested?()
        }
        self.saveButton = saveBtn
        stack.addArrangedSubview(saveBtn)

        let pinBtn = ModernToolbarButton(systemName: "pin", tooltip: "Always on Top", pointSize: 12.0)
        pinBtn.onAction = { [weak self] in
            guard let self = self else { return }
            self.isPinned.toggle()
            self.pinButton?.isActive = self.isPinned
            self.pinButton?.setIcon(systemName: self.isPinned ? "pin.fill" : "pin", pointSize: 12.0)
            self.onPinToggle?(self.isPinned)
        }
        self.pinButton = pinBtn
        stack.addArrangedSubview(pinBtn)

        updateSelectedToolVisuals()
        updateSelectedColorVisuals()
        updateResponsiveOverflow()
    }

    public func updateResponsiveOverflow() {
        let totalW = bounds.width
        if totalW <= 0 { return }

        // Progressive collapsing based directly on window width:
        // 1. Zoom controls (Zoom capsule: 148px, Dimension Badge: ~130px)
        let showZoom = (totalW >= 740.0)
        let showMeta = (totalW >= 920.0)
        zoomContainerView?.isHidden = !showZoom
        zoomOutButton?.isHidden = !showZoom
        zoomPercentButton?.isHidden = !showZoom
        zoomInButton?.isHidden = !showZoom
        zoomFitButton?.isHidden = !showZoom
        zoomResetButton?.isHidden = !showZoom
        zoomSeparatorView?.isHidden = !showZoom
        metaLabel.isHidden = !showMeta

        // 2. Single color picker & tools separator
        updateColorVisibility()
        let isColorVisible = (colorStackView?.isHidden == false)

        // 3. Undo button & action separator
        let showUndo = (totalW >= 400.0)
        undoButton?.isHidden = !showUndo
        actionSeparatorView?.isHidden = isColorVisible || !showUndo

        // 4. Collapsible tools (Arrow, Line, Rectangle, Oval, Spotlight, Counter, Pen, Highlighter, Blur, Ruler)
        // Calibrated to maximize visible tools across all window widths and eliminate empty space
        let totalCount = collapsibleToolDefinitions.count
        let visibleCount: Int
        if totalW >= 880.0 {
            visibleCount = totalCount // 10: All tools visible, overflow button hidden
        } else if totalW >= 830.0 {
            visibleCount = 9 // At 860pt: Ruler in dropdown, Blur visible
        } else if totalW >= 785.0 {
            visibleCount = 8
        } else if totalW >= 740.0 {
            visibleCount = 7 // At 770pt: Ruler, Blur, Highlighter in dropdown, Pen visible
        } else if totalW >= 660.0 {
            visibleCount = 6
        } else if totalW >= 580.0 {
            visibleCount = 5 // At 600pt: 5 tools (Blur hidden, overflow visible)
        } else if totalW >= 500.0 {
            visibleCount = 4 // At 500-579pt: 4 tools (Arrow, Line, Rectangle, Oval)
        } else if totalW >= 430.0 {
            visibleCount = 3 // At 430-499pt: 3 tools
        } else if totalW >= 370.0 {
            visibleCount = 2 // At 370-429pt: 2 tools
        } else if totalW >= 310.0 {
            visibleCount = 1 // At 310-369pt: 1 tool
        } else {
            visibleCount = 0 // Below 310pt (e.g. 280pt): 0 tools (Arrow and Blur hidden)
        }

        if visibleCount >= totalCount {
            for def in collapsibleToolDefinitions {
                toolButtons[def.type]?.isHidden = false
            }
            overflowButton?.isHidden = true
        } else {
            overflowButton?.isHidden = false
            for (index, def) in collapsibleToolDefinitions.enumerated() {
                toolButtons[def.type]?.isHidden = (index >= visibleCount)
            }
        }

        // Pointer, Open, Copy, Save, Pin are strictly always visible
        toolButtons[.select]?.isHidden = false
        openButton?.isHidden = false
        copyButton?.isHidden = false
        saveButton?.isHidden = false
        pinButton?.isHidden = false

        updateSelectedToolVisuals()
        contentStackView?.layoutSubtreeIfNeeded()
    }

    public func buildOverflowMenu() -> NSMenu {
        let menu = NSMenu(title: "Tools")
        menu.autoenablesItems = false

        for def in dropdownToolDefinitions {
            // Do not repeat tools that are currently visible on the main toolbar
            if let btn = toolButtons[def.type], !btn.isHidden {
                continue
            }

            let item = NSMenuItem(
                title: def.title,
                action: #selector(overflowToolSelected(_:)),
                keyEquivalent: def.shortcut
            )
            item.target = self
            item.representedObject = def.type.rawValue
            item.keyEquivalentModifierMask = def.shortcutModifiers

            if let iconName = def.iconName {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                item.image = NSImage(systemSymbolName: iconName, accessibilityDescription: def.title)?
                    .withSymbolConfiguration(config)
            } else if let custom = def.customImage {
                item.image = custom
            }

            if canvasView?.document.activeTool == def.type {
                item.state = .on
            } else {
                item.state = .off
            }
            menu.addItem(item)
        }
        return menu
    }

    public func showOverflowMenu() {
        guard let overflowBtn = overflowButton else { return }
        let menu = buildOverflowMenu()
        let location = NSPoint(x: 0, y: -4)
        menu.popUp(positioning: nil, at: location, in: overflowBtn)
    }

    @objc private func overflowToolSelected(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let type = LayerType(rawValue: rawValue) else { return }
        canvasView?.document.activeTool = type
        updateSelectedToolVisuals()
        canvasView?.needsDisplay = true
    }

    private func createSeparator() -> NSView {
        let sepContainer = NSView()
        sepContainer.translatesAutoresizingMaskIntoConstraints = false
        sepContainer.widthAnchor.constraint(equalToConstant: 12).isActive = true
        sepContainer.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        sepContainer.addSubview(line)

        NSLayoutConstraint.activate([
            line.centerXAnchor.constraint(equalTo: sepContainer.centerXAnchor),
            line.centerYAnchor.constraint(equalTo: sepContainer.centerYAnchor),
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 18)
        ])
        return sepContainer
    }

    private func createSegmentDivider() -> NSView {
        let div = NSView()
        div.wantsLayer = true
        div.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        div.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            div.widthAnchor.constraint(equalToConstant: 1),
            div.heightAnchor.constraint(equalToConstant: 16)
        ])
        return div
    }

    public func showZoomPresetsMenu() {
        guard let btn = zoomPercentButton else { return }
        let menu = buildZoomPresetsMenu()
        let location = NSPoint(x: 0, y: -4)
        menu.popUp(positioning: nil, at: location, in: btn)
    }

    public func buildZoomPresetsMenu() -> NSMenu {
        let menu = NSMenu(title: "Zoom Presets")
        menu.autoenablesItems = false

        let currentMag = canvasView?.zoomScale ?? 1.0
        let currentPercent = Int(round(currentMag * 100))

        let fitItem = NSMenuItem(title: "Best Fit", action: #selector(zoomPresetFitSelected(_:)), keyEquivalent: "1")
        fitItem.keyEquivalentModifierMask = [.command]
        fitItem.target = self
        menu.addItem(fitItem)

        let actualItem = NSMenuItem(title: "Actual Size (100%)", action: #selector(zoomPresetResetSelected(_:)), keyEquivalent: "0")
        actualItem.keyEquivalentModifierMask = [.command]
        actualItem.target = self
        if currentPercent == 100 {
            actualItem.state = .on
        }
        menu.addItem(actualItem)

        menu.addItem(NSMenuItem.separator())

        let presets: [Int] = [800, 400, 200, 150, 100, 75, 50, 25]
        for p in presets {
            let item = NSMenuItem(title: "\(p)%", action: #selector(zoomPresetPercentSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = CGFloat(p) / 100.0
            if currentPercent == p {
                item.state = .on
            }
            menu.addItem(item)
        }

        return menu
    }

    @objc private func zoomPresetFitSelected(_ sender: NSMenuItem) {
        onZoomFitRequested?()
    }

    @objc private func zoomPresetResetSelected(_ sender: NSMenuItem) {
        onZoomResetRequested?()
    }

    @objc private func zoomPresetPercentSelected(_ sender: NSMenuItem) {
        if let scale = sender.representedObject as? CGFloat {
            onZoomSetRequested?(scale)
        }
    }

    public var shouldShowColorPicker: Bool {
        guard let doc = canvasView?.document else { return false }
        let selectedLayers = doc.getSelectedLayers()
        if !selectedLayers.isEmpty {
            // Only blur has no outline / color
            let isBlurOnly = selectedLayers.allSatisfy { $0.type == .blur }
            if isBlurOnly {
                return false
            }
            return true
        }

        // When no annotation is selected:
        // Must show up only if a tool is selected (select is pointer/selection tool, blur has no outline)
        if doc.activeTool == .select || doc.activeTool == .blur {
            return false
        }
        return true
    }

    public func updateColorVisibility() {
        let totalW = bounds.width
        let visible = shouldShowColorPicker && (totalW >= 340.0 || totalW == 0)
        colorStackView?.isHidden = !visible
        toolsSeparatorView?.isHidden = !visible
        let showUndo = (totalW >= 420.0 || totalW == 0)
        actionSeparatorView?.isHidden = visible || !showUndo
        if !visible {
            colorPopover?.close()
        }
    }

    public func showColorPopout() {
        guard let btn = singleColorButton, btn.window != nil else { return }
        if let existing = colorPopover, existing.isShown {
            existing.performClose(nil)
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)

        let popoutVC = ColorPopoutViewController()
        let currentHex: String
        let selected = canvasView?.document.getSelectedLayers() ?? []
        if let first = selected.first, first.type != .blur {
            currentHex = first.color
        } else {
            currentHex = canvasView?.document.activeColor ?? "#FF3B30"
        }
        popoutVC.selectedColor = currentHex
        popoutVC.onColorSelected = { [weak self, weak popover] hex in
            guard let self = self else { return }
            self.canvasView?.document.activeColor = hex
            self.singleColorButton?.updateColor(hex: hex)
            if let doc = self.canvasView?.document {
                let selected = doc.getSelectedLayers()
                if !selected.isEmpty {
                    doc.saveSnapshot()
                    for layer in selected {
                        if layer.type != .blur {
                            layer.color = hex
                        }
                    }
                    doc.onNeedsDisplay?()
                } else if doc.activeTool == .spotlight {
                    if let spotlight = doc.layers.first(where: { ($0 as? FilterLayer)?.filterMode == .spotlight }) {
                        doc.saveSnapshot()
                        spotlight.color = hex
                        doc.onNeedsDisplay?()
                    }
                }
            }
            popover?.performClose(nil)
        }

        popover.contentViewController = popoutVC
        popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        self.colorPopover = popover
    }

    public func updateSelectedToolVisuals() {
        let current = canvasView?.document.activeTool ?? .select
        for (type, btn) in toolButtons {
            btn.isActive = (type == current)
        }
        if current == .select {
            overflowButton?.isActive = false
        } else if let btn = toolButtons[current] {
            overflowButton?.isActive = btn.isHidden
        } else if dropdownToolDefinitions.contains(where: { $0.type == current }) {
            overflowButton?.isActive = true
        } else {
            overflowButton?.isActive = false
        }
        updateSelectedColorVisuals()
    }

    public func updateSelectedColorVisuals() {
        let doc = canvasView?.document
        let selectedLayers = doc?.getSelectedLayers() ?? []
        let currentHex: String
        if let first = selectedLayers.first, first.type != .blur {
            currentHex = first.color.uppercased()
        } else {
            currentHex = doc?.activeColor.uppercased() ?? "#FF3B30"
        }
        singleColorButton?.updateColor(hex: currentHex)
        updateColorVisibility()
    }

    public func updateMeta(bounds: CGRect, zoomPercent: Int) {
        zoomPercentButton?.setTitle("\(zoomPercent)%")
        metaLabel.stringValue = "\(Int(bounds.width)) × \(Int(bounds.height)) px  (\(zoomPercent)%)"
    }
}
