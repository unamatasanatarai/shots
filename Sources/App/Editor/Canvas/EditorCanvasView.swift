import Foundation
import CoreGraphics
import AppKit

public final class EditorCanvasView: NSView, NSDraggingSource {
    public let document: EditorDocument

    // Interactive drawing & manipulation state
    private var activeCreatingLayer: AnnotationLayer?
    private var activeDraggingLayer: AnnotationLayer?
    private var activeHandleIndex: Int?
    private var dragStartPoint: CGPoint = .zero
    private var lastDragPoint: CGPoint = .zero
    private var isSpacePressed: Bool = false
    private var isShiftPressed: Bool = false

    // Zoom & Pan
    public var zoomScale: CGFloat = 1.0

    public init(document: EditorDocument) {
        self.document = document
        super.init(frame: NSRect(origin: .zero, size: document.activeCanvasBounds.size))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        document.onNeedsDisplay = { [weak self] in
            self?.needsDisplay = true
        }

        document.onBoundsChanged = { [weak self] newBounds in
            guard let self = self else { return }
            self.frame = NSRect(origin: .zero, size: newBounds.size)
            self.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var isFlipped: Bool { true } // Flipped so (0,0) is top-left, matching macOS image conventions
    override public var acceptsFirstResponder: Bool { true }

    // MARK: - Drawing Pipeline (Section 6)

    override public func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()

        // Checkerboard background for transparent canvas padding
        drawCheckerboard(in: context, rect: bounds)

        // Translate origin according to activeCanvasBounds to anchor image
        let offsetX = -document.activeCanvasBounds.origin.x
        let offsetY = -document.activeCanvasBounds.origin.y
        context.translateBy(x: offsetX, y: offsetY)

        // 1. Draw originalImage at (0, 0)
        context.draw(document.originalImage, in: document.originalImageBounds)

        // 2. Draw Destructive / Masking Layers (Spotlight & Blur)
        for layer in document.layers where layer.isVisible {
            if let filter = layer as? FilterLayer {
                filter.applyFilter(to: document.originalImage, canvasBounds: document.activeCanvasBounds, in: context)
            }
        }
        if let liveFilter = activeCreatingLayer as? FilterLayer {
            liveFilter.applyFilter(to: document.originalImage, canvasBounds: document.activeCanvasBounds, in: context)
        }

        // 3. Sort AnnotationLayer array by zIndex & draw vector layers
        var allLayers = document.layers.filter { $0.isVisible }
        if let live = activeCreatingLayer {
            allLayers.append(live)
        }
        allLayers.sort { $0.zIndex < $1.zIndex }

        for layer in allLayers {
            if let magnifier = layer as? MagnifierLayer {
                magnifier.renderMagnifiedLens(from: document.originalImage, in: context)
            }
            layer.draw(in: context, scale: zoomScale)
        }

        // 4. Draw Active Selection Handles & UI
        drawSelectionHandles(in: context)

        context.restoreGState()
    }

    private func drawCheckerboard(in context: CGContext, rect: CGRect) {
        context.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0))
        context.fill(rect)

        let checkSize: CGFloat = 16.0
        context.setFillColor(CGColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1.0))
        var y: CGFloat = rect.minY
        var row = 0
        while y < rect.maxY {
            var x: CGFloat = rect.minX + (row % 2 == 0 ? 0 : checkSize)
            while x < rect.maxX {
                context.fill(CGRect(x: x, y: y, width: checkSize, height: checkSize))
                x += checkSize * 2
            }
            y += checkSize
            row += 1
        }
    }

    private func drawSelectionHandles(in context: CGContext) {
        let selectedLayers = document.getSelectedLayers()
        guard !selectedLayers.isEmpty else { return }

        context.saveGState()
        context.setStrokeColor(NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 1.0).cgColor)
        context.setLineWidth(1.5)

        for layer in selectedLayers {
            let box = layer.getBoundingBox()
            context.stroke(box)

            // Draw circular handles
            let handleRadius: CGFloat = 4.5
            let handlePoints: [CGPoint]
            if let rectLayer = layer as? RectangleLayer {
                handlePoints = rectLayer.getHandlePoints()
            } else if let ellipseLayer = layer as? EllipseLayer {
                handlePoints = ellipseLayer.getHandlePoints()
            } else if let arrow = layer as? ArrowLayer {
                handlePoints = [arrow.start, arrow.control, arrow.end]
            } else if let line = layer as? LineLayer {
                handlePoints = [line.start, line.end]
            } else {
                handlePoints = [
                    CGPoint(x: box.minX, y: box.minY),
                    CGPoint(x: box.maxX, y: box.minY),
                    CGPoint(x: box.maxX, y: box.maxY),
                    CGPoint(x: box.minX, y: box.maxY)
                ]
            }

            for p in handlePoints {
                let handleRect = CGRect(x: p.x - handleRadius, y: p.y - handleRadius, width: handleRadius * 2, height: handleRadius * 2)
                context.setFillColor(NSColor.white.cgColor)
                context.fillEllipse(in: handleRect)
                context.setStrokeColor(NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 1.0).cgColor)
                context.setLineWidth(1.5)
                context.strokeEllipse(in: handleRect)
            }
        }

        context.restoreGState()
    }

    // MARK: - Canvas Coordinate Mapping

    private func canvasPoint(from event: NSEvent) -> CGPoint {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let offsetX = -document.activeCanvasBounds.origin.x
        let offsetY = -document.activeCanvasBounds.origin.y
        return CGPoint(x: viewPoint.x - offsetX, y: viewPoint.y - offsetY)
    }

    // MARK: - Mouse Interaction & Tool Matrix

    override public func mouseDown(with event: NSEvent) {
        let point = canvasPoint(from: event)
        dragStartPoint = point
        lastDragPoint = point

        // Check handle click on currently selected layer
        if let selected = document.getSelectedLayers().first,
           let handleIndex = selected.hitTestHandle(point: point) {
            document.saveSnapshot()
            activeDraggingLayer = selected
            activeHandleIndex = handleIndex
            return
        }

        switch document.activeTool {
        case .select:
            if let layer = document.selectLayer(at: point) {
                document.saveSnapshot()
                activeDraggingLayer = layer
                activeHandleIndex = nil
            } else {
                document.selectedLayerIDs.removeAll()
            }

        case .arrow:
            let arrow = ArrowLayer(
                start: point,
                control: point,
                end: point,
                color: document.activeColor,
                strokeWidth: document.activeStrokeWidth
            )
            activeCreatingLayer = arrow

        case .rectangle:
            let rect = RectangleLayer(
                rect: CGRect(origin: point, size: .zero),
                color: document.activeColor,
                strokeWidth: document.activeStrokeWidth
            )
            activeCreatingLayer = rect

        case .ellipse:
            let ellipse = EllipseLayer(
                rect: CGRect(origin: point, size: .zero),
                isPerfectCircle: isShiftPressed,
                color: document.activeColor,
                strokeWidth: document.activeStrokeWidth
            )
            activeCreatingLayer = ellipse

        case .line:
            let line = LineLayer(
                start: point,
                end: point,
                color: document.activeColor,
                strokeWidth: document.activeStrokeWidth
            )
            activeCreatingLayer = line

        case .pen:
            let pen = PenLayer(
                points: [point],
                color: document.activeColor,
                strokeWidth: document.activeStrokeWidth
            )
            activeCreatingLayer = pen

        case .highlighter:
            let hl = HighlighterLayer(
                points: [point],
                color: document.activeColor,
                strokeWidth: 20.0
            )
            activeCreatingLayer = hl

        case .counter:
            let counter = CounterLayer(
                center: point,
                value: document.counterStep,
                color: document.activeColor
            )
            document.counterStep += 1
            document.addLayer(counter)

        case .dimension:
            let dim = DimensionLayer(
                start: point,
                end: point,
                color: document.activeColor,
                strokeWidth: 2.0
            )
            activeCreatingLayer = dim

        case .text:
            let textLayer = TextLayer(
                origin: point,
                text: "Text",
                fontSize: document.activeFontSize,
                color: document.activeColor
            )
            document.addLayer(textLayer)

        case .callout:
            let bubble = CalloutLayer(
                frame: CGRect(x: point.x - 50, y: point.y - 40, width: 100, height: 44),
                tailTip: point,
                color: document.activeColor
            )
            activeCreatingLayer = bubble

        case .magnifier:
            let mag = MagnifierLayer(
                sourceCenter: point,
                targetCenter: CGPoint(x: point.x + 80, y: point.y - 80),
                color: document.activeColor
            )
            document.addLayer(mag)

        case .spotlight:
            let spot = FilterLayer(
                rects: [CGRect(origin: point, size: .zero)],
                filterMode: .spotlight
            )
            activeCreatingLayer = spot

        case .blur:
            let blur = FilterLayer(
                rects: [CGRect(origin: point, size: .zero)],
                filterMode: .gaussian,
                intensity: 16.0
            )
            activeCreatingLayer = blur

        default:
            break
        }

        needsDisplay = true
    }

    override public func mouseDragged(with event: NSEvent) {
        let point = canvasPoint(from: event)
        let delta = CGPoint(x: point.x - lastDragPoint.x, y: point.y - lastDragPoint.y)

        // Micro-Interaction: Spacebar mid-draw translation (Section 3.1)
        if isSpacePressed {
            if let creating = activeCreatingLayer {
                creating.move(by: delta)
                dragStartPoint.x += delta.x
                dragStartPoint.y += delta.y
                document.computeElasticBounds()
                lastDragPoint = point
                needsDisplay = true
                return
            }
        }

        // 1. Moving an existing selected layer or handle
        if let dragging = activeDraggingLayer {
            if let handleIdx = activeHandleIndex {
                dragging.updateHandle(index: handleIdx, to: point)
            } else {
                dragging.move(by: delta)
            }
            document.computeElasticBounds()
            lastDragPoint = point
            needsDisplay = true
            return
        }

        // 2. Interactive creation sizing
        if let creating = activeCreatingLayer {
            if let arrow = creating as? ArrowLayer {
                arrow.end = point
                arrow.control = CGPoint(x: (arrow.start.x + point.x) / 2.0, y: (arrow.start.y + point.y) / 2.0)
            } else if let rect = creating as? RectangleLayer {
                var w = point.x - dragStartPoint.x
                var h = point.y - dragStartPoint.y
                if isShiftPressed {
                    let side = max(abs(w), abs(h))
                    w = w >= 0 ? side : -side
                    h = h >= 0 ? side : -side
                }
                rect.rect = CGRect(
                    x: min(dragStartPoint.x, dragStartPoint.x + w),
                    y: min(dragStartPoint.y, dragStartPoint.y + h),
                    width: max(abs(w), 4.0),
                    height: max(abs(h), 4.0)
                )
            } else if let ellipse = creating as? EllipseLayer {
                var w = point.x - dragStartPoint.x
                var h = point.y - dragStartPoint.y
                if isShiftPressed || ellipse.isPerfectCircle {
                    let side = max(abs(w), abs(h))
                    w = w >= 0 ? side : -side
                    h = h >= 0 ? side : -side
                }
                ellipse.rect = CGRect(
                    x: min(dragStartPoint.x, dragStartPoint.x + w),
                    y: min(dragStartPoint.y, dragStartPoint.y + h),
                    width: max(abs(w), 4.0),
                    height: max(abs(h), 4.0)
                )
            } else if let line = creating as? LineLayer {
                line.end = point
            } else if let pen = creating as? PenLayer {
                pen.points.append(point)
            } else if let hl = creating as? HighlighterLayer {
                hl.points.append(point)
            } else if let dim = creating as? DimensionLayer {
                dim.end = point
            } else if let callout = creating as? CalloutLayer {
                callout.tailTip = point
            } else if let filter = creating as? FilterLayer {
                let r = CGRect(
                    x: min(dragStartPoint.x, point.x),
                    y: min(dragStartPoint.y, point.y),
                    width: max(abs(point.x - dragStartPoint.x), 4.0),
                    height: max(abs(point.y - dragStartPoint.y), 4.0)
                )
                filter.rects = [r]
            }

            document.computeElasticBounds()
        }

        lastDragPoint = point
        needsDisplay = true
    }

    override public func mouseUp(with event: NSEvent) {
        if let creating = activeCreatingLayer {
            document.addLayer(creating)
            activeCreatingLayer = nil
        }
        activeDraggingLayer = nil
        activeHandleIndex = nil
        needsDisplay = true
    }

    // MARK: - Keyboard Modifiers & Shortcuts (Section 3)

    override public func flagsChanged(with event: NSEvent) {
        isShiftPressed = event.modifierFlags.contains(.shift)
        needsDisplay = true
    }

    override public func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { // Spacebar
            isSpacePressed = true
        } else if event.keyCode == 51 { // Delete / Backspace
            document.removeSelectedLayers()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) {
                document.redo()
            } else {
                document.undo()
            }
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            copyCompositionToClipboard()
        } else {
            super.keyDown(with: event)
        }
    }

    override public func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { // Spacebar
            isSpacePressed = false
        }
    }

    // MARK: - Clipboard & Drag Export (Section 1 & 4)

    public func copyCompositionToClipboard() {
        guard let rendered = document.renderComposition() else { return }
        let rep = NSBitmapImageRep(cgImage: rendered)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
    }

    public func saveCompositionToFile(url: URL, format: NSBitmapImageRep.FileType = .png) {
        guard let rendered = document.renderComposition() else { return }
        let rep = NSBitmapImageRep(cgImage: rendered)
        guard let data = rep.representation(using: format, properties: [:]) else { return }
        try? data.write(to: url)
    }

    // NSDraggingSource
    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
}
