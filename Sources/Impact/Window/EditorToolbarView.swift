import Foundation
import CoreGraphics
import AppKit

// MARK: - Modern Toolbar Button

public final class ModernToolbarButton: NSView {
    public var tooltipText: String
    public var onAction: (() -> Void)?

    private let iconImageView = NSImageView()
    private var trackingArea: NSTrackingArea?

    public var isHovered: Bool = false {
        didSet { updateVisuals() }
    }

    public var isActive: Bool = false {
        didSet { updateVisuals() }
    }

    public var isPressed: Bool = false {
        didSet { updateVisuals() }
    }

    public init(systemName: String, tooltip: String, pointSize: CGFloat = 13.0, weight: NSFont.Weight = .semibold) {
        self.tooltipText = tooltip
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        wantsLayer = true
        layer?.cornerRadius = 6.0
        layer?.masksToBounds = true

        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconImageView)

        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 18),
            iconImageView.heightAnchor.constraint(equalToConstant: 18),
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 30)
        ])

        setIcon(systemName: systemName, pointSize: pointSize, weight: weight)
        updateVisuals()
    }

    public static var ufoPointerIcon: NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale: CGFloat = 14.0 / 62.0
            let ox: CGFloat = 3.5
            let oy: CGFloat = 2.0
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
    }

    public convenience init(image: NSImage, tooltip: String) {
        self.init(systemName: "circle", tooltip: tooltip)
        image.isTemplate = true
        self.iconImageView.image = image
        updateVisuals()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
            // Active state: Solid Apple system accent blue + pure white icon
            layer?.backgroundColor = isHovered
                ? NSColor(srgbRed: 0.10, green: 0.54, blue: 1.0, alpha: 1.0).cgColor
                : NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 0.95).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
            layer?.borderWidth = 0.5
            iconImageView.contentTintColor = .white
        } else if isPressed {
            // Pressed state: Darker highlight
            layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.22).cgColor
            layer?.borderColor = NSColor.clear.cgColor
            layer?.borderWidth = 0.0
            iconImageView.contentTintColor = .white
        } else if isHovered {
            // Hover effect: Frosted light highlight pill + white icon
            layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.14).cgColor
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
            layer?.borderWidth = 0.5
            iconImageView.contentTintColor = .white
        } else {
            // Normal state: Transparent + soft white icon
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = NSColor.clear.cgColor
            layer?.borderWidth = 0.0
            iconImageView.contentTintColor = NSColor(white: 0.82, alpha: 1.0)
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

// MARK: - Modern Color Button

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
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        wantsLayer = true

        // Outer selection ring (diameter 22)
        ringView.wantsLayer = true
        ringView.layer?.cornerRadius = 11.0
        ringView.layer?.borderWidth = 1.5
        ringView.layer?.borderColor = NSColor.clear.cgColor
        ringView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ringView)

        // Color dot (diameter 15)
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 7.5
        dotView.layer?.masksToBounds = true
        dotView.layer?.backgroundColor = NSColor(hex: hex).cgColor
        if hex.uppercased() == "#FFFFFF" {
            dotView.layer?.borderWidth = 1.0
            dotView.layer?.borderColor = NSColor(white: 0.45, alpha: 1.0).cgColor
        }
        dotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22),

            ringView.centerXAnchor.constraint(equalTo: centerXAnchor),
            ringView.centerYAnchor.constraint(equalTo: centerYAnchor),
            ringView.widthAnchor.constraint(equalToConstant: 22),
            ringView.heightAnchor.constraint(equalToConstant: 22),

            dotView.centerXAnchor.constraint(equalTo: centerXAnchor),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 15),
            dotView.heightAnchor.constraint(equalToConstant: 15)
        ])

        updateVisuals()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateVisuals() {
        if isActive {
            ringView.layer?.borderColor = NSColor.white.cgColor
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
        ToolDefinition(type: .dimension, title: "Ruler (1 or 2)", iconName: "ruler", shortcut: ""),
        ToolDefinition(type: .rectangle, title: "Rectangle", iconName: "square", shortcut: "r"),
        ToolDefinition(type: .pen, title: "Freehand Drawing", iconName: "pencil.tip", shortcut: "d"),
        ToolDefinition(type: .blur, title: "Blur", iconName: "drop.fill", shortcut: "b"),
        ToolDefinition(type: .highlighter, title: "Highlighter", iconName: "highlighter", shortcut: "h"),
        ToolDefinition(type: .spotlight, title: "Spotlight", iconName: "camera.metering.spot", shortcut: "s"),
        ToolDefinition(type: .counter, title: "Counter", iconName: "number.circle.fill", shortcut: "c"),
        ToolDefinition(type: .ellipse, title: "Oval", iconName: "circle", shortcut: "o"),
        ToolDefinition(type: .line, title: "Line", iconName: "line.diagonal", shortcut: "l")
    ]

    public let collapsibleToolDefinitions: [ToolDefinition] = [
        ToolDefinition(type: .arrow, title: "Arrow", iconName: "arrow.up.right", shortcut: "a"),
        ToolDefinition(type: .line, title: "Line", iconName: "line.diagonal", shortcut: "l"),
        ToolDefinition(type: .rectangle, title: "Rectangle", iconName: "square", shortcut: "r"),
        ToolDefinition(type: .pen, title: "Freehand Drawing", iconName: "pencil.tip", shortcut: "p"),
        ToolDefinition(type: .highlighter, title: "Highlighter", iconName: "highlighter", shortcut: "h"),
        ToolDefinition(type: .counter, title: "Counter", iconName: "number.circle.fill", shortcut: "c"),
        ToolDefinition(type: .spotlight, title: "Spotlight", iconName: "camera.metering.spot", shortcut: "s"),
        ToolDefinition(type: .blur, title: "Blur", iconName: "drop.fill", shortcut: "b")
    ]

    public internal(set) var toolButtons: [LayerType: ModernToolbarButton] = [:]
    public internal(set) var overflowButton: ModernToolbarButton?
    public internal(set) var colorStackView: NSStackView?
    public internal(set) var toolsSeparatorView: NSView?
    public internal(set) var zoomSeparatorView: NSView?
    public internal(set) var zoomOutButton: ModernToolbarButton?
    public internal(set) var zoomInButton: ModernToolbarButton?
    public internal(set) var zoomResetButton: ModernToolbarButton?
    public internal(set) var actionSeparatorView: NSView?
    public internal(set) var undoButton: ModernToolbarButton?
    public internal(set) var openButton: ModernToolbarButton?
    public internal(set) var copyButton: ModernToolbarButton?
    public internal(set) var saveButton: ModernToolbarButton?
    public internal(set) var pinButton: ModernToolbarButton?

    private let colors: [(String, String)] = [
        ("#FF3B30", "Red"),
        ("#FF9500", "Orange"),
        ("#FFCC00", "Yellow"),
        ("#34C759", "Green"),
        ("#007AFF", "Blue"),
        ("#AF52DE", "Purple"),
        ("#FFFFFF", "White"),
        ("#000000", "Black")
    ]
    private var colorButtons: [ModernColorButton] = []

    public var onPinToggle: ((Bool) -> Void)?
    public var onOpenRequested: (() -> Void)?
    public var onSaveRequested: (() -> Void)?
    public var onCopyRequested: (() -> Void)?
    public var onZoomInRequested: (() -> Void)?
    public var onZoomOutRequested: (() -> Void)?
    public var onZoomResetRequested: (() -> Void)?

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

        // 1. Tool buttons: Pointer [V] (ALWAYS VISIBLE)
        let pointerBtn = ModernToolbarButton(image: ModernToolbarButton.ufoPointerIcon, tooltip: "Pointer [V]")
        pointerBtn.onAction = { [weak self] in
            guard let self = self else { return }
            self.canvasView?.document.activeTool = .select
            self.updateSelectedToolVisuals()
        }
        toolButtons[.select] = pointerBtn
        stack.addArrangedSubview(pointerBtn)

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

        // Tools Separator
        let toolsSep = createSeparator()
        self.toolsSeparatorView = toolsSep
        stack.addArrangedSubview(toolsSep)

        // 2. Color pills with hover and active states
        let colorStack = NSStackView()
        colorStack.orientation = .horizontal
        colorStack.alignment = .centerY
        colorStack.spacing = 2.0
        for (hex, name) in colors {
            let colBtn = ModernColorButton(hex: hex, name: name)
            colBtn.onSelect = { [weak self] in
                guard let self = self else { return }
                self.canvasView?.document.activeColor = hex
                self.updateSelectedColorVisuals()
                if let doc = self.canvasView?.document {
                    let selected = doc.getSelectedLayers()
                    if !selected.isEmpty {
                        doc.saveSnapshot()
                        for layer in selected {
                            layer.color = hex
                        }
                        doc.onNeedsDisplay?()
                    }
                }
            }
            colorButtons.append(colBtn)
            colorStack.addArrangedSubview(colBtn)
        }
        self.colorStackView = colorStack
        stack.addArrangedSubview(colorStack)

        // Zoom Separator
        let zoomSep = createSeparator()
        self.zoomSeparatorView = zoomSep
        stack.addArrangedSubview(zoomSep)

        // 3. Zoom Controls: Zoom Out [Cmd -], Zoom In [Cmd +], and live dimensions badge
        let zoomOutBtn = ModernToolbarButton(systemName: "minus.magnifyingglass", tooltip: "Zoom Out [Cmd -]", pointSize: 12.0)
        zoomOutBtn.onAction = { [weak self] in
            self?.onZoomOutRequested?()
        }
        self.zoomOutButton = zoomOutBtn
        stack.addArrangedSubview(zoomOutBtn)

        let zoomInBtn = ModernToolbarButton(systemName: "plus.magnifyingglass", tooltip: "Zoom In [Cmd +]", pointSize: 12.0)
        zoomInBtn.onAction = { [weak self] in
            self?.onZoomInRequested?()
        }
        self.zoomInButton = zoomInBtn
        stack.addArrangedSubview(zoomInBtn)

        let zoomResetBtn = ModernToolbarButton(systemName: "1.magnifyingglass", tooltip: "Reset to 100% [Cmd 0]", pointSize: 12.0)
        zoomResetBtn.onAction = { [weak self] in
            self?.onZoomResetRequested?()
        }
        self.zoomResetButton = zoomResetBtn
        stack.addArrangedSubview(zoomResetBtn)

        metaLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .medium)
        metaLabel.textColor = NSColor(white: 0.65, alpha: 1.0)
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(metaLabel)

        // Flexible spacer to right-align action buttons
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)

        // Action Separator
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
        // 1. Zoom controls (Zoom Out, Zoom In, Reset 100%, Dimension Badge)
        let showZoom = (totalW >= 800.0)
        zoomOutButton?.isHidden = !showZoom
        zoomInButton?.isHidden = !showZoom
        zoomResetButton?.isHidden = !showZoom
        metaLabel.isHidden = !showZoom
        zoomSeparatorView?.isHidden = !showZoom

        // 2. Color pills & tools separator
        let showColors = (totalW >= 620.0)
        colorStackView?.isHidden = !showColors
        toolsSeparatorView?.isHidden = !showColors

        // 3. Undo button & action separator
        let showUndo = (totalW >= 420.0)
        undoButton?.isHidden = !showUndo
        actionSeparatorView?.isHidden = !showUndo

        // 4. Collapsible tools (Arrow, Line, Rectangle, Pen, Highlighter, Counter, Spotlight, Blur)
        // Monotonically scale number of visible tools based on totalW:
        // totalW >= 880: all 8 tools visible, overflow button hidden
        // totalW 820..<880: 7 tools (Blur in overflow)
        // totalW 760..<820: 6 tools (Spotlight, Blur in overflow)
        // totalW 700..<760: 5 tools (Counter, Spotlight, Blur in overflow)
        // totalW 640..<700: 4 tools
        // totalW 580..<640: 3 tools
        // totalW 520..<580: 2 tools
        // totalW 460..<520: 1 tool
        // totalW < 460: 0 tools (all collapsible tools inside 3-dots dropdown)
        let visibleCount: Int
        if totalW >= 880.0 {
            visibleCount = 8
        } else if totalW >= 820.0 {
            visibleCount = 7
        } else if totalW >= 760.0 {
            visibleCount = 6
        } else if totalW >= 700.0 {
            visibleCount = 5
        } else if totalW >= 640.0 {
            visibleCount = 4
        } else if totalW >= 580.0 {
            visibleCount = 3
        } else if totalW >= 520.0 {
            visibleCount = 2
        } else if totalW >= 460.0 {
            visibleCount = 1
        } else {
            visibleCount = 0
        }

        if visibleCount >= 8 {
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
    }

    public func updateSelectedColorVisuals() {
        let currentHex = canvasView?.document.activeColor.uppercased() ?? "#FF3B30"
        for btn in colorButtons {
            btn.isActive = (btn.hex.uppercased() == currentHex)
        }
    }

    public func updateMeta(bounds: CGRect, zoomPercent: Int) {
        metaLabel.stringValue = "\(Int(bounds.width)) × \(Int(bounds.height)) px  (\(zoomPercent)%)"
    }
}
