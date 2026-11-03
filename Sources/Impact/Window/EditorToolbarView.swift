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
        titleLabel.textColor = ImpactTheme.toolbarForeground
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
            layer?.borderColor = isSegment ? NSColor.clear.cgColor : resolvedCGColor(ImpactTheme.activeBorder)
            layer?.borderWidth = isSegment ? 0.0 : 0.5
            iconImageView.contentTintColor = .white
            titleLabel.textColor = .white
        } else if isPressed {
            // Pressed state: Darker highlight
            layer?.backgroundColor = resolvedCGColor(ImpactTheme.pressedFill)
            layer?.borderColor = NSColor.clear.cgColor
            layer?.borderWidth = 0.0
            iconImageView.contentTintColor = ImpactTheme.toolbarForegroundStrong
            titleLabel.textColor = ImpactTheme.toolbarForegroundStrong
        } else if isHovered {
            // Hover effect: highlight pill, stronger icon/text
            layer?.backgroundColor = resolvedCGColor(ImpactTheme.hoverFill)
            layer?.borderColor = isSegment ? NSColor.clear.cgColor : resolvedCGColor(ImpactTheme.hoverBorder)
            layer?.borderWidth = isSegment ? 0.0 : 0.5
            iconImageView.contentTintColor = ImpactTheme.toolbarForegroundStrong
            titleLabel.textColor = ImpactTheme.toolbarForegroundStrong
        } else {
            // Normal state: transparent, soft icon/text
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = NSColor.clear.cgColor
            layer?.borderWidth = 0.0
            iconImageView.contentTintColor = ImpactTheme.toolbarForeground
            titleLabel.textColor = ImpactTheme.toolbarForeground
        }
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateVisuals()
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
        if hex.uppercased() == "#FFFFFF" || hex.uppercased() == "#1E272E" {
            dotView.layer?.borderWidth = 1.0
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
                ringView.layer?.borderColor = resolvedCGColor(ImpactTheme.whiteSwatchActiveRing)
            } else {
                ringView.layer?.borderColor = NSColor(hex: hex).withAlphaComponent(0.85).cgColor
            }
        } else if isHovered {
            ringView.layer?.borderColor = resolvedCGColor(ImpactTheme.swatchHoverRing)
        } else {
            ringView.layer?.borderColor = NSColor.clear.cgColor
        }
        // White and near-black swatches need an outline that contrasts with the popover in either mode
        if dotView.layer?.borderWidth ?? 0 > 0 {
            dotView.layer?.borderColor = resolvedCGColor(ImpactTheme.swatchBorder)
        }
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateVisuals()
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
        swatchView.layer?.borderWidth = 1.0
        updateVisuals()
    }

    private func updateVisuals() {
        swatchView.layer?.borderColor = resolvedCGColor(ImpactTheme.swatchBorder)
        layer?.backgroundColor = isHovered ? resolvedCGColor(ImpactTheme.hoverFill) : NSColor.clear.cgColor
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateVisuals()
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
        let container = ThemedLayerView(fill: ImpactTheme.popoverBackground)
        container.frame = NSRect(x: 0, y: 0, width: 196, height: 104)
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
        ToolDefinition(type: .arrowText, title: "Arrow + Text", iconName: "arrow.up.right.square", shortcut: "a", shortcutModifiers: [.shift], tooltip: "Arrow + Text [Shift A]"),
        ToolDefinition(type: .line, title: "Line", iconName: "line.diagonal", shortcut: "l"),
        ToolDefinition(type: .rectangle, title: "Rectangle", iconName: "square", shortcut: "r"),
        ToolDefinition(type: .ellipse, title: "Oval", iconName: "circle", shortcut: "o"),
        ToolDefinition(type: .spotlight, title: "Spotlight", iconName: "camera.metering.spot", shortcut: "s"),
        ToolDefinition(type: .counter, title: "Counter", iconName: "number.circle.fill", shortcut: "c"),
        ToolDefinition(type: .callout, title: "Callout", iconName: "text.bubble", shortcut: "t"),
        ToolDefinition(type: .text, title: "Text", iconName: "textformat", shortcut: "x"),
        ToolDefinition(type: .pen, title: "Pen", iconName: "pencil.tip", shortcut: "p"),
        ToolDefinition(type: .highlighter, title: "Highlighter", iconName: "highlighter", shortcut: "h"),
        ToolDefinition(type: .blur, title: "Blur", iconName: "drop.fill", shortcut: "b"),
        ToolDefinition(type: .dimension, title: "Ruler", iconName: "ruler", shortcut: "m", tooltip: "Ruler [M]")
    ]

    public let collapsibleToolDefinitions: [ToolDefinition] = [
        ToolDefinition(type: .arrow, title: "Arrow", iconName: "arrow.up.right", shortcut: "a"),
        ToolDefinition(type: .arrowText, title: "Arrow + Text", iconName: "arrow.up.right.square", shortcut: "a", shortcutModifiers: [.shift], tooltip: "Arrow + Text [Shift A]"),
        ToolDefinition(type: .line, title: "Line", iconName: "line.diagonal", shortcut: "l"),
        ToolDefinition(type: .rectangle, title: "Rectangle", iconName: "square", shortcut: "r"),
        ToolDefinition(type: .ellipse, title: "Oval", iconName: "circle", shortcut: "o"),
        ToolDefinition(type: .spotlight, title: "Spotlight", iconName: "camera.metering.spot", shortcut: "s"),
        ToolDefinition(type: .counter, title: "Counter", iconName: "number.circle.fill", shortcut: "c"),
        ToolDefinition(type: .callout, title: "Callout", iconName: "text.bubble", shortcut: "t"),
        ToolDefinition(type: .text, title: "Text", iconName: "textformat", shortcut: "x"),
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
    /// Fixed-width slot left of the tools holding the color swatch and its separator
    public internal(set) var colorSlotView: NSView?
    public internal(set) var zoomSeparatorView: NSView?
    public internal(set) var zoomContainerView: NSView?
    public internal(set) var zoomPercentButton: ModernToolbarButton?
    public internal(set) var zoomFitButton: ModernToolbarButton?
    public internal(set) var zoomResetButton: ModernToolbarButton?
    public internal(set) var actionSeparatorView: NSView?
    /// "⋯" at the right edge: Undo, Open, Copy, Save and Always on Top
    public internal(set) var actionsMenuButton: ModernToolbarButton?
    public internal(set) var colorReadoutView: ColorPickerReadoutView?
    /// Arranged views to ignore when measuring free space (the flexible spacer)
    private var toolbarSpacerView: NSView?

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
    public var onPickedColorCopyRequested: (() -> Void)?

    public private(set) var isPinned: Bool = false
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
        canvasView.onPointerPixelChanged = { [weak self] x, y in
            guard let self = self, let canvas = self.canvasView else { return }
            self.colorReadoutView?.showSample(of: canvas.document.originalImage, x: x, y: y)
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
        let bottomLine = ThemedLayerView(fill: ImpactTheme.separator)
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

        // 0. Active color swatch, left of the tools, then a separator. They sit in a fixed-width slot so the
        // tools never shift when the swatch hides (Select and Blur have no color)
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
        colorStack.translatesAutoresizingMaskIntoConstraints = false
        colorStack.addArrangedSubview(singleBtn)
        self.colorStackView = colorStack

        let toolsSep = createSeparator()
        self.toolsSeparatorView = toolsSep

        let colorSlot = NSView()
        colorSlot.translatesAutoresizingMaskIntoConstraints = false
        colorSlot.addSubview(colorStack)
        colorSlot.addSubview(toolsSep)
        NSLayoutConstraint.activate([
            colorSlot.widthAnchor.constraint(equalToConstant: 30 + 3 + 12),
            colorSlot.heightAnchor.constraint(equalToConstant: 30),
            colorStack.leadingAnchor.constraint(equalTo: colorSlot.leadingAnchor),
            colorStack.centerYAnchor.constraint(equalTo: colorSlot.centerYAnchor),
            toolsSep.trailingAnchor.constraint(equalTo: colorSlot.trailingAnchor),
            toolsSep.centerYAnchor.constraint(equalTo: colorSlot.centerYAnchor)
        ])
        self.colorSlotView = colorSlot
        stack.addArrangedSubview(colorSlot)

        // 1. Tool buttons: Select [V] (ALWAYS VISIBLE)
        let selectBtn = ModernToolbarButton(image: ModernToolbarButton.ufoPointerIcon, tooltip: "Select / Crop [V]")
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
        let zoomCapsule = ThemedLayerView(fill: ImpactTheme.capsuleFill, border: ImpactTheme.capsuleBorder)
        zoomCapsule.layer?.cornerRadius = 6.0
        zoomCapsule.layer?.masksToBounds = true
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

        // Only the current zoom shows; Zoom In / Zoom Out live in its menu with the presets
        let zoomPercentBtn = ModernToolbarButton(text: "100%", tooltip: "Zoom", size: NSSize(width: 48, height: 26), isSegment: true)
        zoomPercentBtn.onAction = { [weak self] in
            self?.showZoomPresetsMenu()
        }
        self.zoomPercentButton = zoomPercentBtn
        zoomStack.addArrangedSubview(zoomPercentBtn)

        self.zoomContainerView = zoomCapsule
        stack.addArrangedSubview(zoomCapsule)

        // Flexible spacer to right-align color swatch & action buttons
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)
        self.toolbarSpacerView = spacer

        // Always-on color picker readout: loupe, swatch, hex and "tab to copy"
        let readout = ColorPickerReadoutView(frame: .zero)
        readout.onCopyRequested = { [weak self] in
            self?.onPickedColorCopyRequested?()
        }
        self.colorReadoutView = readout
        stack.addArrangedSubview(readout)
        stack.setCustomSpacing(8.0, after: readout)

        // Action Separator (separates the color readout from the action buttons)
        let actionSep = createSeparator()
        self.actionSeparatorView = actionSep
        stack.addArrangedSubview(actionSep)

        // 4. Actions (Undo, Open, Copy, Save, Always on Top) live in a "⋯" menu at the right edge
        let actionsBtn = ModernToolbarButton(systemName: "ellipsis", tooltip: "More Actions", pointSize: 13.0)
        actionsBtn.onAction = { [weak self] in
            self?.showActionsMenu()
        }
        self.actionsMenuButton = actionsBtn
        stack.addArrangedSubview(actionsBtn)

        updateSelectedToolVisuals()
        updateSelectedColorVisuals()
        updateResponsiveOverflow()
    }

    public func updateResponsiveOverflow() {
        let totalW = bounds.width
        if totalW <= 0 { return }

        // Progressive collapsing based directly on window width:
        // 1. Zoom controls (Zoom capsule)
        let showZoom = (totalW >= 562.0)
        zoomContainerView?.isHidden = !showZoom
        zoomPercentButton?.isHidden = !showZoom
        zoomSeparatorView?.isHidden = !showZoom

        // 2. Single color picker & tools separator
        updateColorVisibility()

        // 3. Separator before the actions menu
        actionSeparatorView?.isHidden = false

        // 4. Collapsible tools (Arrow, Line, Rectangle, Oval, Spotlight, Counter, Callout, Text, Pen, Highlighter, Blur, Ruler)
        // Calibrated from the measured layout so each rung adds exactly one tool and nothing is ever clipped.
        // Every tool slot is a 30pt button plus 3pt stack spacing (33pt). Rungs assume the widest case
        // (color swatch visible, overflow shown): 303pt of fixed chrome with zoom, 237pt without.
        // All 12 tools need one extra slot over 11 so Ruler collapses on its own rung (the overflow
        // button takes its place). Below the 562pt zoom cutoff the count stays capped at 8 so tools
        // never reappear when the zoom capsule hides.
        let totalCount = collapsibleToolDefinitions.count
        let visibleCount: Int
        if totalW >= 699.0 {
            visibleCount = totalCount // All 13 tools visible, overflow button hidden
        } else if totalW >= 666.0 {
            visibleCount = 12 // Ruler in dropdown
        } else if totalW >= 633.0 {
            visibleCount = 11 // Ruler, Blur in dropdown
        } else if totalW >= 600.0 {
            visibleCount = 10 // Ruler, Blur, Highlighter in dropdown
        } else if totalW >= 567.0 {
            visibleCount = 9 // Ruler, Blur, Highlighter, Pen in dropdown, Text visible
        } else if totalW >= 468.0 {
            visibleCount = 8 // Text in dropdown, Callout visible (zoom capsule hidden below 562pt)
        } else if totalW >= 435.0 {
            visibleCount = 7 // Callout in dropdown, Counter visible
        } else if totalW >= 402.0 {
            visibleCount = 6
        } else if totalW >= 369.0 {
            visibleCount = 5
        } else if totalW >= 336.0 {
            visibleCount = 4
        } else if totalW >= 303.0 {
            visibleCount = 3
        } else if totalW >= 270.0 {
            visibleCount = 2
        } else if totalW >= 237.0 {
            visibleCount = 1
        } else {
            visibleCount = 0 // Below 237pt: only Select and the overflow button remain
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

        // Pointer and the actions menu are strictly always visible
        toolButtons[.select]?.isHidden = false
        actionsMenuButton?.isHidden = false

        updateSelectedToolVisuals()
        updateColorReadoutVisibility()
        contentStackView?.layoutSubtreeIfNeeded()
    }

    /// The color readout takes only space the spacer would leave empty: it gives way to tools and actions
    func updateColorReadoutVisibility() {
        guard let readout = colorReadoutView, let stack = contentStackView else { return }
        let others = stack.arrangedSubviews.filter { $0 !== readout && !$0.isHidden }
        let used = others.reduce(CGFloat(0)) { sum, view in
            view === toolbarSpacerView ? sum : sum + view.fittingSize.width
        } + stack.spacing * CGFloat(max(0, others.count - 1))
        let needed = ColorPickerReadoutView.preferredWidth + stack.spacing + 8.0
        readout.isHidden = stack.frame.width - used < needed
    }

    // MARK: - Actions Menu ("⋯")

    public func buildActionsMenu() -> NSMenu {
        let menu = NSMenu(title: "Actions")
        menu.autoenablesItems = false
        func add(_ title: String, _ symbol: String, _ key: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.keyEquivalentModifierMask = key.isEmpty ? [] : [.command]
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(config)
            menu.addItem(item)
            return item
        }
        _ = add("Undo", "arrow.uturn.backward", "z", #selector(actionsUndoSelected(_:)))
        menu.addItem(.separator())
        _ = add("Open Image…", "folder", "o", #selector(actionsOpenSelected(_:)))
        _ = add("Copy", "doc.on.doc", "c", #selector(actionsCopySelected(_:)))
        _ = add("Save", "square.and.arrow.down", "s", #selector(actionsSaveSelected(_:)))
        menu.addItem(.separator())
        let pin = add("Always on Top", isPinned ? "pin.fill" : "pin", "", #selector(actionsPinSelected(_:)))
        pin.state = isPinned ? .on : .off
        return menu
    }

    public func showActionsMenu() {
        guard let btn = actionsMenuButton else { return }
        let menu = buildActionsMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: btn.bounds.maxX - menu.size.width, y: btn.bounds.minY - 4), in: btn)
    }

    public func performUndoAction() {
        canvasView?.performUndo()
    }

    public func performOpenAction() {
        onOpenRequested?()
    }

    public func performCopyAction() {
        if let onCopy = onCopyRequested {
            onCopy() // the panel copies and shows the toast
        } else {
            canvasView?.copyCompositionToClipboard()
        }
    }

    public func performSaveAction() {
        onSaveRequested?()
    }

    public func togglePinned() {
        isPinned.toggle()
        actionsMenuButton?.isActive = isPinned // the "⋯" button shows the window is pinned
        onPinToggle?(isPinned)
    }

    @objc private func actionsUndoSelected(_ sender: NSMenuItem) { performUndoAction() }
    @objc private func actionsOpenSelected(_ sender: NSMenuItem) { performOpenAction() }
    @objc private func actionsCopySelected(_ sender: NSMenuItem) { performCopyAction() }
    @objc private func actionsSaveSelected(_ sender: NSMenuItem) { performSaveAction() }
    @objc private func actionsPinSelected(_ sender: NSMenuItem) { togglePinned() }

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

        let line = ThemedLayerView(fill: ImpactTheme.separator)
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

        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(zoomInSelected(_:)), keyEquivalent: "+")
        zoomInItem.keyEquivalentModifierMask = [.command]
        zoomInItem.target = self
        menu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(zoomOutSelected(_:)), keyEquivalent: "-")
        zoomOutItem.keyEquivalentModifierMask = [.command]
        zoomOutItem.target = self
        menu.addItem(zoomOutItem)

        menu.addItem(NSMenuItem.separator())

        let fitItem = NSMenuItem(title: "Best Fit", action: #selector(zoomPresetFitSelected(_:)), keyEquivalent: "1")
        fitItem.keyEquivalentModifierMask = [.command]
        fitItem.target = self
        menu.addItem(fitItem)

        menu.addItem(NSMenuItem.separator())

        let presets: [Int] = [25, 50, 75, 100, 150, 200, 400, 800]
        for p in presets {
            let keyEq = (p == 100) ? "0" : ""
            let item = NSMenuItem(title: "\(p)%", action: #selector(zoomPresetPercentSelected(_:)), keyEquivalent: keyEq)
            if p == 100 {
                item.keyEquivalentModifierMask = [.command]
            }
            item.target = self
            item.representedObject = CGFloat(p) / 100.0
            if currentPercent == p {
                item.state = .on
            }
            menu.addItem(item)
        }

        return menu
    }

    @objc private func zoomInSelected(_ sender: NSMenuItem) {
        onZoomInRequested?()
    }

    @objc private func zoomOutSelected(_ sender: NSMenuItem) {
        onZoomOutRequested?()
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
        // The swatch is always shown (it sets the color the next annotation gets); only very narrow
        // windows drop it to make room
        let totalW = bounds.width
        let visible = (totalW >= 340.0 || totalW == 0)
        colorSlotView?.isHidden = !visible
        colorStackView?.isHidden = !visible
        toolsSeparatorView?.isHidden = !visible
        actionSeparatorView?.isHidden = false
        if !visible {
            colorPopover?.close()
        }
        updateColorReadoutVisibility()
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
            self?.applyPickedColor(hex)
            popover?.performClose(nil)
        }

        popover.contentViewController = popoutVC
        popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        self.colorPopover = popover
    }

    /// Applies a swatch: sets the active color and recolors the selection as one undo step
    func applyPickedColor(_ hex: String) {
        self.canvasView?.document.activeColor = hex
        self.singleColorButton?.updateColor(hex: hex)
        if let doc = self.canvasView?.document {
            let selected = doc.getSelectedLayers()
            // Picking the color the selection already has changes nothing: no undo step
            let recolorable = selected.filter { $0.type != .blur }
            if !recolorable.isEmpty && recolorable.allSatisfy({ $0.color == hex }) {
                return
            }
            if !selected.isEmpty {
                // A recolor during a callout editing session folds into the session's undo step
                if self.canvasView?.isEditingCallout != true {
                    doc.saveSnapshot()
                }
                for layer in selected {
                    if layer.type != .blur {
                        layer.color = hex
                    }
                }
                self.canvasView?.syncCalloutEditorAppearance()
                doc.onNeedsDisplay?()
            } else if doc.activeTool == .spotlight {
                if let spotlight = doc.layers.first(where: { ($0 as? FilterLayer)?.filterMode == .spotlight }) {
                    doc.saveSnapshot()
                    spotlight.color = hex
                    doc.onNeedsDisplay?()
                }
            }
        }
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
    }
}
