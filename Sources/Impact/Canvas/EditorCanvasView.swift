import Foundation
import CoreGraphics
import AppKit

public final class EditorCanvasView: NSView, NSDraggingSource {
    public let document: EditorDocument

    // Interactive drawing & manipulation state
    private var activeCreatingLayer: AnnotationLayer?
    private var activeDraggingLayer: AnnotationLayer?
    private var activeHandleIndex: Int?
    private var activeDraggingRectIndex: Int?
    private var initialRectForDrag: CGRect?
    private var dragStartPoint: CGPoint = .zero
    private var lastDragPoint: CGPoint = .zero
    private var isSpacePressed: Bool = false
    private var isShiftPressed: Bool = false
    private var inlineEditor: NSTextField?
    private var editingLayer: AnnotationLayer?
    var hoveredLayer: AnnotationLayer?
    var hoverOutlineLayer: AnnotationLayer?
    var hoverAlpha: CGFloat = 0.0
    private var canvasTrackingArea: NSTrackingArea?
    private var currentMouseCanvasPoint: CGPoint?

    // Zoom & Pan
    public var zoomScale: CGFloat = 1.0
    public var onCloseRequested: (() -> Void)?
    private var isRightPanning: Bool = false
    private var rightPanStartWindowPoint: NSPoint = .zero

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

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = canvasTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        canvasTrackingArea = area
    }

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

        // 1. Draw originalImage right-side up in flipped context
        context.saveGState()
        context.translateBy(x: 0, y: document.originalImageBounds.height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(document.originalImage, in: CGRect(x: document.originalImageBounds.origin.x, y: 0, width: document.originalImageBounds.width, height: document.originalImageBounds.height))
        context.restoreGState()

        // 2. Draw Destructive / Masking Layers (Spotlight & Blur)
        // Combine any live creating spotlight with the existing spotlight overlay so there is only one unified overlay
        var drawnSpotlight = false
        for layer in document.layers where layer.isVisible {
            if let filter = layer as? FilterLayer {
                if filter.filterMode == .spotlight {
                    drawnSpotlight = true
                    if let liveSpotlight = activeCreatingLayer as? FilterLayer, liveSpotlight.filterMode == .spotlight, let liveRect = liveSpotlight.rects.first {
                        let combinedRects = filter.rects + [liveRect]
                        let combined = FilterLayer(rects: combinedRects, filterMode: .spotlight, intensity: filter.intensity)
                        combined.applyFilter(to: document.originalImage, canvasBounds: document.activeCanvasBounds, in: context)
                    } else {
                        filter.applyFilter(to: document.originalImage, canvasBounds: document.activeCanvasBounds, in: context)
                    }
                } else {
                    // For blur: when actively dragging/moving an existing blur layer, don't draw its blurred image mid-drag
                    if activeDraggingLayer?.id != filter.id {
                        filter.applyFilter(to: document.originalImage, canvasBounds: document.activeCanvasBounds, in: context)
                    }
                }
            }
        }
        if !drawnSpotlight {
            if let liveFilter = activeCreatingLayer as? FilterLayer, liveFilter.filterMode == .spotlight {
                liveFilter.applyFilter(to: document.originalImage, canvasBounds: document.activeCanvasBounds, in: context)
            } else if document.activeTool == .spotlight {
                let emptySpotlight = FilterLayer(rects: [], filterMode: .spotlight)
                emptySpotlight.applyFilter(to: document.originalImage, canvasBounds: document.activeCanvasBounds, in: context)
            }
        }

        // 3. Sort AnnotationLayer array by zIndex & draw vector layers
        var allLayers = document.layers.filter { layer in
            if !layer.isVisible { return false }
            if layer.id == activeDraggingLayer?.id, let f = layer as? FilterLayer, f.filterMode != .spotlight {
                return false
            }
            return true
        }
        if let live = activeCreatingLayer {
            if !(live is FilterLayer && (live as! FilterLayer).filterMode != .spotlight) {
                allLayers.append(live)
            }
        }
        allLayers.sort { $0.zIndex < $1.zIndex }

        // 3. Draw Vector Layers (Shapes, Arrows, Text, Callout, Counter)
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        for layer in allLayers {
            if let magnifier = layer as? MagnifierLayer {
                magnifier.renderMagnifiedLens(from: document.originalImage, in: context)
            }
            layer.draw(in: context, scale: zoomScale)
        }

        NSGraphicsContext.restoreGraphicsState()

        // 4. Draw Blur Highlight / Translucent Rectangle (During live drag creation or move)
        if let liveBlur = activeCreatingLayer as? FilterLayer, liveBlur.filterMode != .spotlight {
            for r in liveBlur.rects {
                drawBlurHighlight(rect: r, in: context)
            }
        }
        if let draggingBlur = activeDraggingLayer as? FilterLayer, draggingBlur.filterMode != .spotlight {
            for r in draggingBlur.rects {
                drawBlurHighlight(rect: r, in: context)
            }
        }

        // 5. Draw Active Selection Handles & UI
        drawSelectionHandles(in: context)

        // 6. Draw Brush Outline Preview (Highlighter or Pen)
        if (document.activeTool == .highlighter || document.activeTool == .pen), activeCreatingLayer == nil, let pt = currentMouseCanvasPoint {
            let width = (document.activeTool == .highlighter) ? 20.0 : document.activeStrokeWidth
            drawBrushOutline(at: pt, in: context, strokeWidth: width)
        }

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

        context.saveGState()

        // 1. Crisp hover indicator for all annotation elements (instant, no fade, razor-sharp)
        if let target = hoverOutlineLayer, !selectedLayers.contains(where: { $0.id == target.id }) {
            if let path = hoverPath(for: target) {
                context.saveGState()

                // Crisp vibrant macOS accent blue stroke
                context.setStrokeColor(NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 1.0).cgColor)
                context.setLineWidth(1.5)
                context.setLineJoin(.round)
                context.setLineCap(.round)
                context.addPath(path)
                context.strokePath()

                context.restoreGState()
            }
        }

        guard !selectedLayers.isEmpty else {
            context.restoreGState()
            return
        }

        context.setStrokeColor(NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 1.0).cgColor)
        context.setLineWidth(1.5)

        for layer in selectedLayers {
            let box = layer.getBoundingBox()

            // Draw handles
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
            } else if let dim = layer as? DimensionLayer {
                handlePoints = [dim.start, dim.end]
            } else if let mag = layer as? MagnifierLayer {
                handlePoints = [mag.sourceCenter, mag.targetCenter]
            } else if let callout = layer as? CalloutLayer {
                handlePoints = [callout.tailTip]
            } else if let counter = layer as? CounterLayer {
                // Square rounded handle located on the tip of the peak
                let p = counter.getPeakPoint()
                let side: CGFloat = 8.5
                let handleRect = CGRect(x: p.x - side / 2.0, y: p.y - side / 2.0, width: side, height: side)
                let handlePath = CGPath(roundedRect: handleRect, cornerWidth: 2.0, cornerHeight: 2.0, transform: nil)

                context.setFillColor(NSColor.white.cgColor)
                context.addPath(handlePath)
                context.fillPath()

                context.setStrokeColor(NSColor(white: 0.25, alpha: 0.9).cgColor)
                context.setLineWidth(1.2)
                context.addPath(handlePath)
                context.strokePath()
                continue
            } else if layer is HighlighterLayer || layer is PenLayer {
                // Freehand strokes cannot be scaled, only moved: drop control handles
                handlePoints = []
            } else if let textLayer = layer as? TextLayer {
                let tBox = textLayer.getBoundingBox()
                handlePoints = [CGPoint(x: tBox.maxX, y: tBox.maxY)]
            } else if let filter = layer as? FilterLayer {
                if filter.filterMode == .spotlight {
                    handlePoints = filter.getHandlePointsForSelected()
                } else {
                    handlePoints = filter.getHandlePoints()
                }
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
        currentMouseCanvasPoint = point
        dragStartPoint = point
        lastDragPoint = point

        commitInlineEditor()
        clearHoverStateImmediately()

        // Handle double click to edit text or callout
        if event.clickCount == 2 {
            if let hit = document.layers.reversed().first(where: { $0.isVisible && $0.contains(point: point) }) {
                if hit is TextLayer || hit is CalloutLayer {
                    document.selectLayer(hit)
                    beginInlineEditing(for: hit)
                    return
                }
            }
        }

        // Check handle click on currently selected layer or any visible layer
        if let selected = document.getSelectedLayers().first,
           let handleIndex = selected.hitTestHandle(point: point) {
            document.saveSnapshot()
            activeDraggingLayer = selected
            activeHandleIndex = handleIndex
            if let rectLayer = selected as? RectangleLayer {
                initialRectForDrag = rectLayer.rect
            } else if let filter = selected as? FilterLayer {
                let rectIdx = handleIndex / 8
                filter.selectedRectIndex = rectIdx
                if rectIdx < filter.rects.count {
                    initialRectForDrag = filter.rects[rectIdx]
                }
            }
            if document.activeTool != .select && document.activeTool != .spotlight && document.activeTool != .blur {
                document.activeTool = .select
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
            }
            return
        }
        for layer in document.layers.reversed() where layer.isVisible {
            if let handleIndex = layer.hitTestHandle(point: point) {
                document.saveSnapshot()
                document.selectLayer(layer)
                activeDraggingLayer = layer
                activeHandleIndex = handleIndex
                if let rectLayer = layer as? RectangleLayer {
                    initialRectForDrag = rectLayer.rect
                } else if let filter = layer as? FilterLayer {
                    let rectIdx = handleIndex / 8
                    filter.selectedRectIndex = rectIdx
                    if rectIdx < filter.rects.count {
                        initialRectForDrag = filter.rects[rectIdx]
                    }
                }
                if document.activeTool != .select && document.activeTool != .spotlight && document.activeTool != .blur {
                    document.activeTool = .select
                    (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                }
                return
            }
        }

        // If clicking on or inside an already selected layer (e.g. Rectangle), drag-move it
        if let selected = document.getSelectedLayers().first {
            if selected.contains(point: point) {
                document.saveSnapshot()
                activeDraggingLayer = selected
                activeHandleIndex = nil
                if let filter = selected as? FilterLayer {
                    let rectIdx = filter.rectIndex(at: point) ?? 0
                    filter.selectedRectIndex = rectIdx
                    activeDraggingRectIndex = rectIdx
                    if rectIdx < filter.rects.count {
                        initialRectForDrag = filter.rects[rectIdx]
                    }
                }
                if document.activeTool != .select && document.activeTool != .spotlight && document.activeTool != .blur {
                    document.activeTool = .select
                    (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                }
                return
            }
        }

        // If clicking any existing visible annotation element while an annotation tool is active,
        // do not add a new element; immediately select it and revert activeTool to pointer (.select)
        if let hit = document.layers.reversed().first(where: { $0.isVisible && $0.contains(point: point) }) {
            document.saveSnapshot()
            document.selectLayer(hit)
            activeDraggingLayer = hit
            activeHandleIndex = nil
            if let filter = hit as? FilterLayer {
                let rectIdx = filter.rectIndex(at: point) ?? 0
                filter.selectedRectIndex = rectIdx
                activeDraggingRectIndex = rectIdx
                if rectIdx < filter.rects.count {
                    initialRectForDrag = filter.rects[rectIdx]
                }
            }
            if document.activeTool != .select && document.activeTool != .spotlight && document.activeTool != .blur {
                document.activeTool = .select
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
            }
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
                if document.activeTool != .select {
                    document.activeTool = .select
                    (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                }
            }

        case .arrow:
            if let hit = document.layers.reversed().first(where: { $0.isVisible && $0.contains(point: point) }) {
                document.saveSnapshot()
                document.selectLayer(hit)
                activeDraggingLayer = hit
                activeHandleIndex = nil
                return
            }
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
            if let hit = document.layers.reversed().first(where: { $0.isVisible && $0.contains(point: point) }), let counter = hit as? CounterLayer {
                document.selectLayer(counter)
                activeDraggingLayer = counter
                activeHandleIndex = nil
                return
            }
            let counter = CounterLayer(
                tip: point,
                value: document.nextCounterValue(),
                color: document.activeColor
            )
            activeCreatingLayer = counter

        case .dimension:
            let dim = DimensionLayer(
                start: point,
                end: point,
                color: document.activeColor,
                strokeWidth: 2.0
            )
            activeCreatingLayer = dim

        case .text:
            commitInlineEditor()
            if let hit = document.layers.reversed().first(where: { $0.isVisible && $0.contains(point: point) }), let textLayer = hit as? TextLayer {
                document.selectLayer(textLayer)
                beginInlineEditing(for: textLayer)
                return
            }
            let textLayer = TextLayer(
                origin: point,
                text: "Text",
                fontSize: document.activeFontSize,
                color: document.activeColor
            )
            activeCreatingLayer = textLayer

        case .callout:
            commitInlineEditor()
            if let hit = document.layers.reversed().first(where: { $0.isVisible && $0.contains(point: point) }), let callout = hit as? CalloutLayer {
                document.selectLayer(callout)
                beginInlineEditing(for: callout)
                return
            }
            let bubble = CalloutLayer(
                frame: CGRect(x: point.x - 60, y: point.y - 70, width: 120, height: 44),
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
                if let rectLayer = dragging as? RectangleLayer, let initRect = initialRectForDrag {
                    let oppX: CGFloat
                    let oppY: CGFloat
                    switch handleIdx {
                    case 0: oppX = initRect.maxX; oppY = initRect.maxY
                    case 1: oppX = initRect.maxX; oppY = initRect.maxY
                    case 2: oppX = initRect.minX; oppY = initRect.maxY
                    case 3: oppX = initRect.minX; oppY = initRect.maxY
                    case 4: oppX = initRect.minX; oppY = initRect.minY
                    case 5: oppX = initRect.minX; oppY = initRect.minY
                    case 6: oppX = initRect.maxX; oppY = initRect.minY
                    case 7: oppX = initRect.maxX; oppY = initRect.minY
                    default: oppX = initRect.maxX; oppY = initRect.maxY
                    }

                    switch handleIdx {
                    case 1, 5:
                        let newY = min(point.y, oppY)
                        let newH = max(4.0, abs(point.y - oppY))
                        rectLayer.rect = CGRect(x: initRect.minX, y: newY, width: initRect.width, height: newH)
                    case 7, 3:
                        let newX = min(point.x, oppX)
                        let newW = max(4.0, abs(point.x - oppX))
                        rectLayer.rect = CGRect(x: newX, y: initRect.minY, width: newW, height: initRect.height)
                    default:
                        // Corner handles (0, 2, 4, 6)
                        let newX = min(point.x, oppX)
                        let newW = max(4.0, abs(point.x - oppX))
                        let newY = min(point.y, oppY)
                        let newH = max(4.0, abs(point.y - oppY))
                        rectLayer.rect = CGRect(x: newX, y: newY, width: newW, height: newH)
                    }
                } else if let filter = dragging as? FilterLayer, let initRect = initialRectForDrag {
                    let rectIdx = handleIdx / 8
                    let subIdx = handleIdx % 8
                    let oppX: CGFloat
                    let oppY: CGFloat
                    switch subIdx {
                    case 0, 1: oppX = initRect.maxX; oppY = initRect.maxY
                    case 2, 3: oppX = initRect.minX; oppY = initRect.maxY
                    case 4, 5: oppX = initRect.minX; oppY = initRect.minY
                    case 6, 7: oppX = initRect.maxX; oppY = initRect.minY
                    default: oppX = initRect.maxX; oppY = initRect.maxY
                    }

                    if rectIdx < filter.rects.count {
                        switch subIdx {
                        case 1, 5:
                            let newY = min(point.y, oppY)
                            let newH = max(4.0, abs(point.y - oppY))
                            filter.rects[rectIdx] = CGRect(x: initRect.minX, y: newY, width: initRect.width, height: newH)
                        case 7, 3:
                            let newX = min(point.x, oppX)
                            let newW = max(4.0, abs(point.x - oppX))
                            filter.rects[rectIdx] = CGRect(x: newX, y: initRect.minY, width: newW, height: initRect.height)
                        default:
                            let newX = min(point.x, oppX)
                            let newW = max(4.0, abs(point.x - oppX))
                            let newY = min(point.y, oppY)
                            let newH = max(4.0, abs(point.y - oppY))
                            filter.rects[rectIdx] = CGRect(x: newX, y: newY, width: newW, height: newH)
                        }
                    }
                } else {
                    dragging.updateHandle(index: handleIdx, to: point)
                }
            } else {
                if let filter = dragging as? FilterLayer {
                    let idx = activeDraggingRectIndex ?? filter.selectedRectIndex ?? (filter.rects.count - 1)
                    if idx >= 0 && idx < filter.rects.count {
                        filter.rects[idx].origin.x += delta.x
                        filter.rects[idx].origin.y += delta.y
                    }
                } else {
                    dragging.move(by: delta)
                }
                NSCursor.fourDirectionalMove.set()
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
                // Always start with straight: control point is collinear midpoint
                arrow.control = CGPoint(x: (arrow.start.x + point.x) / 2.0, y: (arrow.start.y + point.y) / 2.0)
                arrow.updateRelativeControl()
            } else if let rect = creating as? RectangleLayer {
                rect.rect = CGRect(
                    x: min(dragStartPoint.x, point.x),
                    y: min(dragStartPoint.y, point.y),
                    width: abs(point.x - dragStartPoint.x),
                    height: abs(point.y - dragStartPoint.y)
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
                    width: abs(w),
                    height: abs(h)
                )
            } else if let line = creating as? LineLayer {
                if isShiftPressed {
                    let dx = point.x - dragStartPoint.x
                    let dy = point.y - dragStartPoint.y
                    let angle = atan2(dy, dx)
                    let snapped = (round(angle / (.pi / 4.0))) * (.pi / 4.0)
                    let len = hypot(dx, dy)
                    line.end = CGPoint(x: dragStartPoint.x + len * cos(snapped), y: dragStartPoint.y + len * sin(snapped))
                } else {
                    line.end = point
                }
            } else if let pen = creating as? PenLayer {
                if let last = pen.points.last {
                    if hypot(point.x - last.x, point.y - last.y) >= 2.0 {
                        pen.points.append(point)
                    }
                } else {
                    pen.points.append(point)
                }
            } else if let hl = creating as? HighlighterLayer {
                if let last = hl.points.last {
                    if hypot(point.x - last.x, point.y - last.y) >= 2.0 {
                        hl.points.append(point)
                    }
                } else {
                    hl.points.append(point)
                }
            } else if let dim = creating as? DimensionLayer {
                dim.end = point
            } else if let callout = creating as? CalloutLayer {
                callout.tailTip = point
            } else if creating is CounterLayer {
                // Peak direction is fixed at default (7:30pm) upon placement.
                // Changing peak direction can only happen when grabbing the point located on the tip of the peak.
            } else if let filter = creating as? FilterLayer {
                let r = CGRect(
                    x: min(dragStartPoint.x, point.x),
                    y: min(dragStartPoint.y, point.y),
                    width: abs(point.x - dragStartPoint.x),
                    height: abs(point.y - dragStartPoint.y)
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
            if let counter = creating as? CounterLayer {
                document.counterStep = counter.value + 1
                document.addLayer(counter)
                document.selectLayer(counter)
            } else if let textLayer = creating as? TextLayer {
                document.addLayer(textLayer)
                document.selectLayer(textLayer)
                beginInlineEditing(for: textLayer)
            } else if let callout = creating as? CalloutLayer {
                document.addLayer(callout)
                document.selectLayer(callout)
                beginInlineEditing(for: callout)
            } else {
                var isValidSize = true

                if let arrow = creating as? ArrowLayer {
                    isValidSize = hypot(arrow.end.x - arrow.start.x, arrow.end.y - arrow.start.y) >= 10.0
                } else if let rect = creating as? RectangleLayer {
                    isValidSize = rect.rect.width >= 6.0 && rect.rect.height >= 6.0
                } else if let ellipse = creating as? EllipseLayer {
                    isValidSize = ellipse.rect.width >= 6.0 && ellipse.rect.height >= 6.0
                } else if let line = creating as? LineLayer {
                    isValidSize = hypot(line.end.x - line.start.x, line.end.y - line.start.y) >= 6.0
                } else if let filter = creating as? FilterLayer {
                    isValidSize = filter.rects.first.map { $0.width >= 6.0 && $0.height >= 6.0 } ?? false
                } else if let pen = creating as? PenLayer {
                    isValidSize = !pen.points.isEmpty
                } else if let hl = creating as? HighlighterLayer {
                    isValidSize = !hl.points.isEmpty
                }

                if isValidSize {
                    if let filter = creating as? FilterLayer, filter.filterMode == .spotlight, let newHole = filter.rects.first {
                        if let existingSpotlight = document.layers.first(where: { ($0 as? FilterLayer)?.filterMode == .spotlight }) as? FilterLayer {
                            document.saveSnapshot()
                            existingSpotlight.rects.append(newHole)
                            existingSpotlight.selectedRectIndex = existingSpotlight.rects.count - 1
                            document.selectLayer(existingSpotlight)
                            document.computeElasticBounds()
                        } else {
                            filter.selectedRectIndex = 0
                            document.addLayer(filter)
                            document.selectLayer(filter)
                        }
                    } else {
                        document.addLayer(creating)
                        document.selectLayer(creating)
                    }
                }
            }
            activeCreatingLayer = nil
        }
        activeDraggingLayer = nil
        activeHandleIndex = nil
        activeDraggingRectIndex = nil
        initialRectForDrag = nil
        currentMouseCanvasPoint = canvasPoint(from: event)
        updateCursorForPoint(canvasPoint(from: event))
        needsDisplay = true
    }

    // MARK: - Right-Click Pan Support

    override public func rightMouseDown(with event: NSEvent) {
        isRightPanning = true
        rightPanStartWindowPoint = event.locationInWindow
        NSCursor.closedHand.set()
    }

    override public func rightMouseDragged(with event: NSEvent) {
        guard isRightPanning, let clipView = enclosingScrollView?.contentView else { return }
        let currentWindowPoint = event.locationInWindow
        let dx = currentWindowPoint.x - rightPanStartWindowPoint.x
        let dy = currentWindowPoint.y - rightPanStartWindowPoint.y
        rightPanStartWindowPoint = currentWindowPoint

        // Dragging right moves view content right (i.e. scroll origin x decreases)
        // Dragging down in window coordinates moves view content down (i.e. scroll origin y decreases)
        var newOrigin = clipView.bounds.origin
        newOrigin.x -= dx
        newOrigin.y -= dy

        clipView.scroll(to: clipView.constrainBoundsRect(NSRect(origin: newOrigin, size: clipView.bounds.size)).origin)
        enclosingScrollView?.reflectScrolledClipView(clipView)
        NSCursor.closedHand.set()
    }

    override public func rightMouseUp(with event: NSEvent) {
        isRightPanning = false
        updateCursorForPoint(canvasPoint(from: event))
    }

    override public func mouseEntered(with event: NSEvent) {
        currentMouseCanvasPoint = canvasPoint(from: event)
        if document.activeTool == .highlighter || document.activeTool == .pen {
            needsDisplay = true
        }
    }

    override public func mouseExited(with event: NSEvent) {
        currentMouseCanvasPoint = nil
        updateHoverState(to: nil)
        if document.activeTool == .highlighter || document.activeTool == .pen {
            needsDisplay = true
        }
    }

    override public func mouseMoved(with event: NSEvent) {
        let point = canvasPoint(from: event)
        currentMouseCanvasPoint = point
        let newlyHovered = document.layers.reversed().first { layer in
            layer.isVisible && (layer.contains(point: point) || layer.hitTestHandle(point: point) != nil)
        }
        updateHoverState(to: newlyHovered)
        updateCursorForPoint(point)
        if document.activeTool == .highlighter || document.activeTool == .pen {
            needsDisplay = true
        }
    }

    func updateHoverState(to newLayer: AnnotationLayer?) {
        if newLayer?.id != hoveredLayer?.id {
            hoveredLayer = newLayer
            hoverOutlineLayer = newLayer
            hoverAlpha = (newLayer != nil) ? 1.0 : 0.0
            needsDisplay = true
        }
    }

    func hoverPath(for layer: AnnotationLayer) -> CGPath? {
        if let counter = layer as? CounterLayer {
            return counter.pathForTeardrop()
        } else if let arrow = layer as? ArrowLayer {
            return arrow.pathForArrow()
        } else if let line = layer as? LineLayer {
            let path = CGMutablePath()
            path.move(to: line.start)
            path.addLine(to: line.end)
            return path
        } else if let rectLayer = layer as? RectangleLayer {
            let r = rectLayer.rect
            let effectiveRadius = max(0.0, min(rectLayer.cornerRadius, min(r.width / 2.0, r.height / 2.0)))
            return CGPath(roundedRect: r, cornerWidth: effectiveRadius, cornerHeight: effectiveRadius, transform: nil)
        } else if let ellipseLayer = layer as? EllipseLayer {
            return CGPath(ellipseIn: ellipseLayer.rect, transform: nil)
        } else if let callout = layer as? CalloutLayer {
            return callout.pathForCallout()
        } else if let textLayer = layer as? TextLayer {
            let box = textLayer.getBoundingBox()
            return CGPath(roundedRect: box, cornerWidth: 6.0, cornerHeight: 6.0, transform: nil)
        } else if let hl = layer as? HighlighterLayer {
            guard !hl.points.isEmpty else { return nil }
            if hl.points.count == 1 {
                let p = hl.points[0]
                let w = hl.strokeWidth
                return CGPath(ellipseIn: CGRect(x: p.x - w / 2.0, y: p.y - w / 2.0, width: w, height: w), transform: nil)
            }
            let path = CGMutablePath()
            path.move(to: hl.points[0])
            if hl.points.count == 2 {
                path.addLine(to: hl.points[1])
            } else {
                for i in 1..<hl.points.count {
                    let mid = CGPoint(
                        x: (hl.points[i - 1].x + hl.points[i].x) / 2.0,
                        y: (hl.points[i - 1].y + hl.points[i].y) / 2.0
                    )
                    path.addQuadCurve(to: mid, control: hl.points[i - 1])
                }
                path.addLine(to: hl.points.last!)
            }
            return path.copy(strokingWithWidth: hl.strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
        } else if let pen = layer as? PenLayer {
            guard !pen.points.isEmpty else { return nil }
            if pen.points.count == 1 {
                let p = pen.points[0]
                let w = pen.strokeWidth
                return CGPath(ellipseIn: CGRect(x: p.x - w / 2.0, y: p.y - w / 2.0, width: w, height: w), transform: nil)
            }
            let path = CGMutablePath()
            path.move(to: pen.points[0])
            if pen.points.count == 2 {
                path.addLine(to: pen.points[1])
            } else {
                for i in 1..<pen.points.count {
                    let mid = CGPoint(
                        x: (pen.points[i - 1].x + pen.points[i].x) / 2.0,
                        y: (pen.points[i - 1].y + pen.points[i].y) / 2.0
                    )
                    path.addQuadCurve(to: mid, control: pen.points[i - 1])
                }
                path.addLine(to: pen.points.last!)
            }
            return path.copy(strokingWithWidth: pen.strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
        } else if let filter = layer as? FilterLayer {
            let path = CGMutablePath()
            for r in filter.rects {
                guard r.width > 0 && r.height > 0 else { continue }
                let effectiveRadius = max(0.0, min(6.0, min(r.width / 2.0, r.height / 2.0)))
                path.addPath(CGPath(roundedRect: r, cornerWidth: effectiveRadius, cornerHeight: effectiveRadius, transform: nil))
            }
            return path.isEmpty ? nil : path
        } else if let dim = layer as? DimensionLayer {
            let path = CGMutablePath()
            path.move(to: dim.start)
            path.addLine(to: dim.end)
            let angle = atan2(dim.end.y - dim.start.y, dim.end.x - dim.start.x)
            let perp = angle + .pi / 2.0
            let tickHalf: CGFloat = 7.0
            let s1 = CGPoint(x: dim.start.x - tickHalf * cos(perp), y: dim.start.y - tickHalf * sin(perp))
            let s2 = CGPoint(x: dim.start.x + tickHalf * cos(perp), y: dim.start.y + tickHalf * sin(perp))
            path.move(to: s1); path.addLine(to: s2)
            let e1 = CGPoint(x: dim.end.x - tickHalf * cos(perp), y: dim.end.y - tickHalf * sin(perp))
            let e2 = CGPoint(x: dim.end.x + tickHalf * cos(perp), y: dim.end.y + tickHalf * sin(perp))
            path.move(to: e1); path.addLine(to: e2)
            return path
        } else if let mag = layer as? MagnifierLayer {
            let path = CGMutablePath()
            let lensRect = CGRect(x: mag.targetCenter.x - mag.radius, y: mag.targetCenter.y - mag.radius, width: mag.radius * 2, height: mag.radius * 2)
            path.addPath(CGPath(ellipseIn: lensRect, transform: nil))
            let sourceRect = CGRect(x: mag.sourceCenter.x - 10, y: mag.sourceCenter.y - 10, width: 20, height: 20)
            path.addPath(CGPath(ellipseIn: sourceRect, transform: nil))
            path.move(to: mag.sourceCenter)
            path.addLine(to: mag.targetCenter)
            return path
        } else if let bezel = layer as? BezelLayer {
            let titleBarHeight: CGFloat = bezel.style == .macWindow ? 32.0 : 0.0
            let frameRect = CGRect(
                x: bezel.targetBounds.minX,
                y: bezel.targetBounds.minY - titleBarHeight,
                width: bezel.targetBounds.width,
                height: bezel.targetBounds.height + titleBarHeight
            )
            return CGPath(roundedRect: frameRect, cornerWidth: 10.0, cornerHeight: 10.0, transform: nil)
        } else {
            let box = layer.getBoundingBox()
            return CGPath(roundedRect: box, cornerWidth: 4.0, cornerHeight: 4.0, transform: nil)
        }
    }

    func clearHoverStateImmediately() {
        hoveredLayer = nil
        hoverOutlineLayer = nil
        hoverAlpha = 0.0
        needsDisplay = true
    }

    private func drawBrushOutline(at point: CGPoint, in context: CGContext, strokeWidth: CGFloat) {
        context.saveGState()

        let radius = strokeWidth / 2.0
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: strokeWidth, height: strokeWidth)

        let color = NSColor(hex: document.activeColor)

        // Subtle color tint inside the brush outline
        context.setFillColor(color.withAlphaComponent(0.25).cgColor)
        context.fillEllipse(in: rect)

        // Outer contrasting stroke (dark shadow/stroke)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.60).cgColor)
        context.setLineWidth(max(1.0, strokeWidth <= 6.0 ? 1.0 : 2.0))
        context.strokeEllipse(in: rect)

        // Inner bright stroke
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        context.setLineWidth(max(0.5, strokeWidth <= 6.0 ? 0.75 : 1.0))
        context.strokeEllipse(in: rect)

        // Center crosshair / precision dot
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - 0.75, y: point.y - 0.75, width: 1.5, height: 1.5))

        context.restoreGState()
    }

    private func drawBlurHighlight(rect: CGRect, in context: CGContext) {
        guard rect.width > 0 && rect.height > 0 else { return }
        context.saveGState()

        let effectiveRadius = max(0.0, min(6.0, min(rect.width / 2.0, rect.height / 2.0)))
        let path = CGPath(roundedRect: rect, cornerWidth: effectiveRadius, cornerHeight: effectiveRadius, transform: nil)

        // Frosted translucent highlight fill
        context.setFillColor(NSColor(srgbRed: 0.15, green: 0.55, blue: 0.95, alpha: 0.28).cgColor)
        context.addPath(path)
        context.fillPath()

        // Crisp accent border
        context.setStrokeColor(NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 0.90).cgColor)
        context.setLineWidth(1.5)
        context.addPath(path)
        context.strokePath()

        context.restoreGState()
    }

    override public func cursorUpdate(with event: NSEvent) {
        let point = canvasPoint(from: event)
        updateCursorForPoint(point)
    }

    private func updateCursorForPoint(_ point: CGPoint) {
        if isRightPanning {
            NSCursor.closedHand.set()
            return
        }

        // While actively dragging a layer's body, maintain the 4-directional move cursor
        if activeDraggingLayer != nil && activeHandleIndex == nil {
            NSCursor.fourDirectionalMove.set()
            return
        }

        // If dragging or hovering over a handle, use appropriate handle cursor
        if let selected = document.getSelectedLayers().first,
           let handleIndex = selected.hitTestHandle(point: point) {
            if selected is RectangleLayer {
                switch handleIndex {
                case 1, 5:
                    NSCursor.resizeUpDown.set()
                    return
                case 3, 7:
                    NSCursor.resizeLeftRight.set()
                    return
                default:
                    NSCursor.crosshair.set()
                    return
                }
            } else if selected is FilterLayer {
                let subIdx = handleIndex % 8
                switch subIdx {
                case 1, 5:
                    NSCursor.resizeUpDown.set()
                    return
                case 3, 7:
                    NSCursor.resizeLeftRight.set()
                    return
                default:
                    NSCursor.crosshair.set()
                    return
                }
            } else {
                NSCursor.crosshair.set()
                return
            }
        }
        if let hovered = hoveredLayer, let handleIndex = hovered.hitTestHandle(point: point) {
            if hovered is RectangleLayer {
                switch handleIndex {
                case 1, 5:
                    NSCursor.resizeUpDown.set()
                    return
                case 3, 7:
                    NSCursor.resizeLeftRight.set()
                    return
                default:
                    NSCursor.crosshair.set()
                    return
                }
            } else if hovered is FilterLayer {
                let subIdx = handleIndex % 8
                switch subIdx {
                case 1, 5:
                    NSCursor.resizeUpDown.set()
                    return
                case 3, 7:
                    NSCursor.resizeLeftRight.set()
                    return
                default:
                    NSCursor.crosshair.set()
                    return
                }
            } else {
                NSCursor.crosshair.set()
                return
            }
        }

        // When in select mode, check if hovering over any movable layer
        if document.activeTool == .select {
            let hitsMovableLayer = document.layers.reversed().contains { layer in
                layer.isVisible && layer.contains(point: point)
            }
            if hitsMovableLayer {
                NSCursor.fourDirectionalMove.set()
                return
            }
        }

        // Also if any already selected layer contains the point (even if switching tools), dragging it moves it
        let hitsSelectedLayer = document.getSelectedLayers().contains { layer in
            layer.isVisible && layer.contains(point: point)
        }
        if hitsSelectedLayer {
            NSCursor.fourDirectionalMove.set()
            return
        }

        // Default tool cursors
        switch document.activeTool {
        case .select:
            NSCursor.arrow.set()
        case .text, .callout:
            NSCursor.iBeam.set()
        default:
            NSCursor.crosshair.set()
        }
    }

    // MARK: - Keyboard Modifiers & Shortcuts (Section 3)

    override public func flagsChanged(with event: NSEvent) {
        isShiftPressed = event.modifierFlags.contains(.shift)
        needsDisplay = true
    }

    public func handleEscapeKey() {
        let wasEditing = inlineEditor != nil
        if wasEditing {
            commitInlineEditor()
        }

        let wasCreating = activeCreatingLayer != nil
        if wasCreating {
            activeCreatingLayer = nil
        }

        let wasDragging = activeDraggingLayer != nil
        if wasDragging {
            activeDraggingLayer = nil
            activeHandleIndex = nil
            activeDraggingRectIndex = nil
            initialRectForDrag = nil
        }

        let hasSelection = !document.selectedLayerIDs.isEmpty
        let isNonPointerTool = document.activeTool != .select

        if wasEditing || wasCreating || wasDragging || hasSelection || isNonPointerTool {
            document.selectedLayerIDs.removeAll()
            if document.activeTool != .select {
                document.activeTool = .select
            }
            (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
            clearHoverStateImmediately()
            needsDisplay = true
        } else {
            if let panel = window as? EditorPanel {
                panel.close()
            } else if let win = window {
                win.close()
            }
            onCloseRequested?()
        }
    }

    override public func cancelOperation(_ sender: Any?) {
        handleEscapeKey()
    }

    override public func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            handleEscapeKey()
            return
        }
        if event.keyCode == 49 { // Spacebar
            isSpacePressed = true
        } else if event.keyCode == 51 { // Delete / Backspace
            if let selected = document.getSelectedLayers().first as? FilterLayer, selected.filterMode == .spotlight {
                if selected.rects.count > 1, let idx = selected.selectedRectIndex, idx < selected.rects.count {
                    document.saveSnapshot()
                    selected.rects.remove(at: idx)
                    selected.selectedRectIndex = max(0, selected.rects.count - 1)
                    document.computeElasticBounds()
                    clearHoverStateImmediately()
                    needsDisplay = true
                    return
                }
            }
            document.removeSelectedLayers()
            clearHoverStateImmediately()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) {
                document.redo()
            } else {
                document.undo()
            }
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            copyCompositionToClipboard()
        } else if event.modifierFlags.contains(.command) && (event.charactersIgnoringModifiers == "=" || event.charactersIgnoringModifiers == "+") {
            (window as? EditorPanel)?.zoomIn()
        } else if event.modifierFlags.contains(.command) && (event.charactersIgnoringModifiers == "-" || event.charactersIgnoringModifiers == "_") {
            (window as? EditorPanel)?.zoomOut()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "0" {
            (window as? EditorPanel)?.resetZoom()
        } else if inlineEditor == nil && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) {
            let key = (event.charactersIgnoringModifiers ?? "").lowercased()
            if key == "v" {
                document.activeTool = .select
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                needsDisplay = true
            } else if key == "a" {
                document.activeTool = .arrow
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                needsDisplay = true
            } else if key == "l" {
                document.activeTool = .line
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                needsDisplay = true
            } else if key == "r" {
                document.activeTool = .rectangle
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                needsDisplay = true
            } else if key == "c" {
                document.activeTool = .counter
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                needsDisplay = true
            } else if key == "p" {
                document.activeTool = .pen
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                needsDisplay = true
            } else if key == "h" {
                document.activeTool = .highlighter
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                needsDisplay = true
            } else if key == "s" {
                document.activeTool = .spotlight
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                needsDisplay = true
            } else if key == "b" {
                document.activeTool = .blur
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                needsDisplay = true
            } else {
                super.keyDown(with: event)
            }
        } else {
            super.keyDown(with: event)
        }
    }

    override public func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { // Spacebar
            isSpacePressed = false
        }
    }

    // MARK: - macOS Pinch-to-Zoom Gesture

    override public func magnify(with event: NSEvent) {
        if let sv = enclosingScrollView {
            let oldMag = sv.magnification
            let factor = 1.0 + event.magnification
            let newMag = max(sv.minMagnification, min(sv.maxMagnification, oldMag * factor))
            
            // Magnify centered at cursor location in clipView
            let clipPoint = sv.contentView.convert(event.locationInWindow, from: nil)
            sv.setMagnification(newMag, centeredAt: clipPoint)
            zoomScale = sv.magnification
            (window as? EditorPanel)?.updateMetaLabel()
        } else {
            super.magnify(with: event)
        }
    }

    // MARK: - Clipboard & Drag Export (Section 1 & 4)

    public func copyCompositionToClipboard() {
        guard let rendered = document.renderComposition() else { return }
        let rep = NSBitmapImageRep(cgImage: rendered)
        let nsImage = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
        if let pngData = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(pngData, forType: .png)
        }
    }

    public func saveCompositionToFile(url: URL, format: NSBitmapImageRep.FileType = .png) {
        guard let rendered = document.renderComposition() else { return }
        let rep = NSBitmapImageRep(cgImage: rendered)
        let properties: [NSBitmapImageRep.PropertyKey: Any] = (format == .jpeg) ? [.compressionFactor: 0.95] : [:]
        guard let data = rep.representation(using: format, properties: properties) else { return }
        try? data.write(to: url)
    }

    // NSDraggingSource
    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    // MARK: - Inline Text Editing (Section 2 & 4)

    public func beginInlineEditing(for layer: AnnotationLayer) {
        commitInlineEditor()

        let initialText: String
        let initialFont: NSFont
        let textRect: CGRect

        let offsetX = -document.activeCanvasBounds.origin.x
        let offsetY = -document.activeCanvasBounds.origin.y

        if let textLayer = layer as? TextLayer {
            initialText = textLayer.text
            initialFont = NSFont.systemFont(ofSize: textLayer.fontSize, weight: .semibold)
            let box = textLayer.getBoundingBox()
            textRect = CGRect(x: box.origin.x + offsetX, y: box.origin.y + offsetY, width: max(box.width, 100), height: max(box.height, 28))
        } else if let callout = layer as? CalloutLayer {
            initialText = callout.text
            initialFont = NSFont.systemFont(ofSize: callout.fontSize, weight: .bold)
            let f = callout.frame
            textRect = CGRect(x: f.origin.x + offsetX, y: f.origin.y + offsetY, width: max(f.width, 100), height: max(f.height, 36))
        } else {
            return
        }

        editingLayer = layer
        let textField = NSTextField(frame: textRect)
        textField.stringValue = initialText
        textField.font = initialFont
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.backgroundColor = NSColor(white: 0.15, alpha: 0.95)
        textField.textColor = NSColor.white
        textField.focusRingType = .none
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.target = self
        textField.action = #selector(editorAction(_:))
        textField.delegate = self

        addSubview(textField)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textField)
        textField.selectText(nil)
        self.inlineEditor = textField
    }

    public func commitInlineEditor() {
        guard let tf = inlineEditor, let layer = editingLayer else { return }
        let newText = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let textLayer = layer as? TextLayer {
            textLayer.text = newText.isEmpty ? "Text" : newText
        } else if let callout = layer as? CalloutLayer {
            callout.text = newText.isEmpty ? "Callout" : newText
        }

        tf.removeFromSuperview()
        self.inlineEditor = nil
        self.editingLayer = nil
        document.computeElasticBounds()
        needsDisplay = true
    }

    @objc private func editorAction(_ sender: Any) {
        commitInlineEditor()
    }
}

extension EditorCanvasView: NSTextFieldDelegate {
    public func controlTextDidEndEditing(_ obj: Notification) {
        commitInlineEditor()
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Shift+Enter or Alt+Enter inserts newline for multiline callout text; Enter alone commits
            if NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.option) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            commitInlineEditor()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            handleEscapeKey()
            return true
        }
        return false
    }
}
