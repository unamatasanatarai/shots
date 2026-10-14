import Foundation
import CoreGraphics
import AppKit

public final class EditorToolbarView: NSVisualEffectView {
    public weak var canvasView: EditorCanvasView?

    private var toolButtons: [LayerType: NSButton] = [:]
    private let colors = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#AF52DE", "#FFFFFF", "#000000"]
    private var colorButtons: [NSButton] = []

    public var onPinToggle: ((Bool) -> Void)?
    public var onSaveRequested: (() -> Void)?
    public var onCopyRequested: (() -> Void)?
    public var onZoomInRequested: (() -> Void)?
    public var onZoomOutRequested: (() -> Void)?

    private var isPinned: Bool = false

    public init(canvasView: EditorCanvasView) {
        self.canvasView = canvasView
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 48))
        material = .hudWindow
        state = .active
        blendingMode = .withinWindow
        wantsLayer = true
        layer?.cornerRadius = 24.0
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        layer?.borderWidth = 1.0

        setupToolbar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupToolbar() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8.0
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Tool buttons: Pointer (V), Arrow (A), Rectangle (R), Counter (C), Highlighter (H)
        let tools: [(LayerType, String, String)] = [
            (.select, "cursorarrow", "Pointer (V)"),
            (.arrow, "arrow.up.right", "Arrow (A)"),
            (.rectangle, "rectangle", "Rectangle (R)"),
            (.counter, "1.circle", "Counter (C)"),
            (.highlighter, "highlighter", "Highlighter (H)")
        ]

        for (type, icon, tooltip) in tools {
            let btn = createIconButton(systemName: icon, tooltip: tooltip)
            btn.target = self
            btn.action = #selector(toolClicked(_:))
            toolButtons[type] = btn
            stack.addArrangedSubview(btn)
        }

        // Separator
        stack.addArrangedSubview(createSeparator())

        // Color pills
        for hex in colors {
            let colBtn = NSButton()
            colBtn.title = ""
            colBtn.isBordered = false
            colBtn.wantsLayer = true
            colBtn.layer?.cornerRadius = 9.0
            colBtn.layer?.masksToBounds = true
            colBtn.layer?.backgroundColor = NSColor(hex: hex).cgColor
            colBtn.layer?.borderWidth = 1.5
            colBtn.layer?.borderColor = hex == "#FFFFFF" ? NSColor.gray.cgColor : NSColor.clear.cgColor
            colBtn.translatesAutoresizingMaskIntoConstraints = false
            colBtn.widthAnchor.constraint(equalToConstant: 18).isActive = true
            colBtn.heightAnchor.constraint(equalToConstant: 18).isActive = true
            colBtn.target = self
            colBtn.action = #selector(colorClicked(_:))
            colBtn.identifier = NSUserInterfaceItemIdentifier(hex)
            colorButtons.append(colBtn)
            stack.addArrangedSubview(colBtn)
        }

        // Separator
        stack.addArrangedSubview(createSeparator())

        // Zoom Controls: Zoom Out (-), Zoom In (+)
        let zoomOutBtn = createIconButton(systemName: "minus.magnifyingglass", tooltip: "Zoom Out (Cmd -)")
        zoomOutBtn.target = self
        zoomOutBtn.action = #selector(zoomOutClicked)
        stack.addArrangedSubview(zoomOutBtn)

        let zoomInBtn = createIconButton(systemName: "plus.magnifyingglass", tooltip: "Zoom In (Cmd +)")
        zoomInBtn.target = self
        zoomInBtn.action = #selector(zoomInClicked)
        stack.addArrangedSubview(zoomInBtn)

        // Separator
        stack.addArrangedSubview(createSeparator())

        // Action Buttons: Undo, Copy, Save, Pin
        let undoBtn = createIconButton(systemName: "arrow.uturn.backward", tooltip: "Undo")
        undoBtn.target = self
        undoBtn.action = #selector(undoClicked)
        stack.addArrangedSubview(undoBtn)

        let copyBtn = createIconButton(systemName: "doc.on.doc", tooltip: "Copy (Cmd+C)")
        copyBtn.target = self
        copyBtn.action = #selector(copyClicked)
        stack.addArrangedSubview(copyBtn)

        let saveBtn = createIconButton(systemName: "square.and.arrow.down", tooltip: "Save")
        saveBtn.target = self
        saveBtn.action = #selector(saveClicked)
        stack.addArrangedSubview(saveBtn)

        let pinBtn = createIconButton(systemName: "pin", tooltip: "Pin Window")
        pinBtn.target = self
        pinBtn.action = #selector(pinClicked(_:))
        stack.addArrangedSubview(pinBtn)

        updateSelectedToolVisuals()
    }

    private func createIconButton(systemName: String, tooltip: String) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .texturedRounded
        btn.isBordered = false
        btn.toolTip = tooltip
        if #available(macOS 11.0, *) {
            btn.image = NSImage(systemSymbolName: systemName, accessibilityDescription: tooltip)
        } else {
            btn.title = tooltip
        }
        btn.contentTintColor = NSColor(white: 0.9, alpha: 1.0)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 28).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return btn
    }

    private func createSeparator() -> NSView {
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return sep
    }

    @objc private func toolClicked(_ sender: NSButton) {
        for (type, btn) in toolButtons where btn == sender {
            canvasView?.document.activeTool = type
            updateSelectedToolVisuals()
            break
        }
    }

    @objc private func colorClicked(_ sender: NSButton) {
        guard let hex = sender.identifier?.rawValue else { return }
        canvasView?.document.activeColor = hex
        for btn in colorButtons {
            btn.layer?.borderColor = btn == sender ? NSColor.white.cgColor : (btn.identifier?.rawValue == "#FFFFFF" ? NSColor.gray.cgColor : NSColor.clear.cgColor)
        }

        // Apply color change to currently selected layers
        if let doc = canvasView?.document {
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

    @objc private func zoomInClicked() {
        onZoomInRequested?()
    }

    @objc private func zoomOutClicked() {
        onZoomOutRequested?()
    }

    @objc private func undoClicked() {
        canvasView?.document.undo()
    }

    @objc private func copyClicked() {
        canvasView?.copyCompositionToClipboard()
        onCopyRequested?()
    }

    @objc private func saveClicked() {
        onSaveRequested?()
    }

    @objc private func pinClicked(_ sender: NSButton) {
        isPinned.toggle()
        sender.contentTintColor = isPinned ? NSColor.systemYellow : NSColor(white: 0.9, alpha: 1.0)
        onPinToggle?(isPinned)
    }

    public func updateSelectedToolVisuals() {
        let current = canvasView?.document.activeTool ?? .select
        for (type, btn) in toolButtons {
            btn.contentTintColor = (type == current) ? NSColor(srgbRed: 0.0, green: 0.58, blue: 1.0, alpha: 1.0) : NSColor(white: 0.9, alpha: 1.0)
        }
    }
}
