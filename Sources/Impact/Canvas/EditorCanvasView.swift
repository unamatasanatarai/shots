import Foundation
import CoreGraphics
import AppKit

public final class EditorCanvasView: NSView, NSDraggingSource {
    public private(set) var document: EditorDocument

    // Interactive drawing & manipulation state
    var activeCreatingLayer: AnnotationLayer?
    var activeDraggingLayer: AnnotationLayer?
    private var activeHandleIndex: Int?
    private var activeDraggingRectIndex: Int?
    private var initialRectForDrag: CGRect?
    private var dragStartPoint: CGPoint = .zero
    private var calloutGrabOffset: CGPoint = .zero
    private var lastDragPoint: CGPoint = .zero
    private var isSpacePressed: Bool = false
    private var isShiftPressed: Bool = false
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

    // In-place callout/text editing
    private struct CalloutEditSession {
        let layer: TextEditableLayer
        let isNew: Bool
        let preSession: [AnnotationLayer] // clones taken before the layer was appended (new) or before editing
        let originalText: String
        let originalColor: String
    }
    private var calloutSession: CalloutEditSession?
    private(set) var calloutEditor: CalloutTextView?
    public var isEditingCallout: Bool { calloutSession != nil }
    private var isEndingCalloutEditing = false
    // A click on the already-selected callout/text body: edits on mouse-up unless it turns into a drag
    private var pendingEditCallout: TextEditableLayer?

    public init(document: EditorDocument) {
        self.document = document
        super.init(frame: NSRect(origin: .zero, size: document.activeCanvasBounds.size))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        setupDocumentCallbacks()
    }

    private func setupDocumentCallbacks() {
        document.onNeedsDisplay = { [weak self] in
            self?.needsDisplay = true
        }

        document.onBoundsChanged = { [weak self] newBounds in
            guard let self = self else { return }
            self.frame = NSRect(origin: .zero, size: newBounds.size)
            // The elastic origin shifts when the canvas grows left/up; keep the editor on its bubble
            self.positionCalloutEditor()
            self.needsDisplay = true
        }

        // Switching to any other tool finishes the session; the new tool stays active
        document.onActiveToolChanged = { [weak self] tool in
            guard let self = self, !self.isEndingCalloutEditing, tool != .callout, tool != .text, self.isEditingCallout else { return }
            self.finishCalloutEditing(switchToSelect: false)
        }
    }

    /// Dynamically loads a new document into this canvas view
    public func setDocument(_ newDoc: EditorDocument) {
        endCalloutEditing()
        self.document = newDoc
        self.activeCreatingLayer = nil
        self.activeDraggingLayer = nil
        self.pendingEditCallout = nil
        self.activeHandleIndex = nil
        self.activeDraggingRectIndex = nil
        self.initialRectForDrag = nil
        self.hoveredLayer = nil
        self.hoverOutlineLayer = nil
        self.zoomScale = 1.0
        self.frame = NSRect(origin: .zero, size: newDoc.activeCanvasBounds.size)
        setupDocumentCallbacks()
        self.needsDisplay = true
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
            options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
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
        drawCheckerboard(in: context, rect: dirtyRect.intersection(bounds))

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

        // 2a. Draw Blur / Pixelate Layers (always UNDER spotlight overlay)
        for layer in document.layers where layer.isVisible {
            if let filter = layer as? FilterLayer, filter.filterMode != .spotlight {
                // When actively dragging/moving an existing blur layer, don't draw its blurred image mid-drag
                if activeDraggingLayer?.id != filter.id {
                    filter.applyFilter(to: document.originalImage, canvasBounds: document.activeCanvasBounds, in: context)
                }
            }
        }

        // 2b. Draw Spotlight Overlay (always ON TOP of blur layers)
        // Combine any live creating spotlight with the existing spotlight overlay so there is only one unified overlay
        var drawnSpotlight = false
        for layer in document.layers where layer.isVisible {
            if let filter = layer as? FilterLayer, filter.filterMode == .spotlight {
                drawnSpotlight = true
                if let liveSpotlight = activeCreatingLayer as? FilterLayer, liveSpotlight.filterMode == .spotlight, let liveRect = liveSpotlight.rects.first {
                    let combinedRects = filter.rects + [liveRect]
                    let combined = FilterLayer(
                        rects: combinedRects,
                        filterMode: .spotlight,
                        intensity: filter.intensity,
                        color: filter.color,
                        strokeWidth: filter.strokeWidth,
                        cornerRadius: filter.cornerRadius
                    )
                    combined.applyFilter(to: document.originalImage, canvasBounds: document.activeCanvasBounds, in: context)
                } else {
                    filter.applyFilter(to: document.originalImage, canvasBounds: document.activeCanvasBounds, in: context)
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

        // 3. Draw Vector Layers (Shapes, Arrows, Dimension, Counter)
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        for layer in allLayers {
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

    private static let checkerboardTile: CGImage = {
        let size = 32
        let half = 16
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setFillColor(CGColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: half, height: half))
        ctx.fill(CGRect(x: half, y: half, width: half, height: half))
        return ctx.makeImage()!
    }()
    private static let selectionAccentCGColor = CGColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
    private static let handleFillCGColor = CGColor(gray: 1.0, alpha: 1.0)
    private static let counterHandleBorderCGColor = CGColor(gray: 0.25, alpha: 0.9)
    private static let blurHighlightFillCGColor = CGColor(srgbRed: 0.15, green: 0.55, blue: 0.95, alpha: 0.28)
    private static let brushDarkOutlineCGColor = CGColor(gray: 0.0, alpha: 0.60)
    private static let brushLightOutlineCGColor = CGColor(gray: 1.0, alpha: 0.95)

    private func drawCheckerboard(in context: CGContext, rect: CGRect) {
        context.draw(Self.checkerboardTile, in: rect, byTiling: true)
    }

    private func drawSelectionHandles(in context: CGContext) {
        let selectedLayers = document.getSelectedLayers()

        context.saveGState()

        // 1. Crisp hover indicator for all annotation elements (instant, no fade, razor-sharp)
        if let target = hoverOutlineLayer, !selectedLayers.contains(where: { $0.id == target.id }) {
            if let path = hoverPath(for: target) {
                context.saveGState()

                // Crisp vibrant macOS accent blue stroke
                context.setStrokeColor(Self.selectionAccentCGColor)
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

        context.setStrokeColor(Self.selectionAccentCGColor)
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
            } else if let callout = layer as? CalloutLayer {
                // Handles are hidden while the callout's text is being edited
                handlePoints = callout.id == calloutSession?.layer.id ? [] : [callout.tailTip]
            } else if layer is TextLayer {
                handlePoints = []
            } else if let counter = layer as? CounterLayer {
                // Square rounded handle located on the tip of the peak
                let p = counter.getPeakPoint()
                let side: CGFloat = 8.5
                let handleRect = CGRect(x: p.x - side / 2.0, y: p.y - side / 2.0, width: side, height: side)
                let handlePath = CGPath(roundedRect: handleRect, cornerWidth: 2.0, cornerHeight: 2.0, transform: nil)

                context.setFillColor(Self.handleFillCGColor)
                context.addPath(handlePath)
                context.fillPath()

                context.setStrokeColor(Self.counterHandleBorderCGColor)
                context.setLineWidth(1.2)
                context.addPath(handlePath)
                context.strokePath()
                continue
            } else if layer is HighlighterLayer || layer is PenLayer {
                // Freehand strokes cannot be scaled, only moved: drop control handles
                handlePoints = []
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
                context.setFillColor(Self.handleFillCGColor)
                context.fillEllipse(in: handleRect)
                context.setStrokeColor(Self.selectionAccentCGColor)
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

        // While editing, a click outside the callout finishes editing and does nothing else.
        // Body clicks land in the editor; clicks on the editing callout's beak are ignored.
        if let session = calloutSession {
            if !session.layer.contains(point: point) {
                endCalloutEditing()
            }
            return
        }

        currentMouseCanvasPoint = point
        dragStartPoint = point
        lastDragPoint = point
        pendingEditCallout = nil

        clearHoverStateImmediately()

        // Check handle click on currently selected layer or any visible layer
        if let selected = document.getSelectedLayers().first,
           let handleIndex = selected.hitTestHandle(point: point) {
            document.saveSnapshot()
            if document.activeTool != .select && document.activeTool != .blur {
                document.activeTool = .select
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                document.selectLayer(selected)
            }
            activeDraggingLayer = selected
            activeHandleIndex = handleIndex
            if let rectLayer = selected as? RectangleLayer {
                initialRectForDrag = rectLayer.rect
            } else if let ellipseLayer = selected as? EllipseLayer {
                initialRectForDrag = ellipseLayer.rect
            } else if let filter = selected as? FilterLayer {
                let rectIdx = handleIndex / 8
                filter.selectedRectIndex = rectIdx
                if rectIdx < filter.rects.count {
                    initialRectForDrag = filter.rects[rectIdx]
                }
            }
            return
        }
        for layer in document.layers.reversed() where layer.isVisible {
            if let handleIndex = layer.hitTestHandle(point: point) {
                document.saveSnapshot()
                if document.activeTool != .select && document.activeTool != .blur {
                    document.activeTool = .select
                    (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                }
                document.selectLayer(layer)
                activeDraggingLayer = layer
                activeHandleIndex = handleIndex
                if let rectLayer = layer as? RectangleLayer {
                    initialRectForDrag = rectLayer.rect
                } else if let ellipseLayer = layer as? EllipseLayer {
                    initialRectForDrag = ellipseLayer.rect
                } else if let filter = layer as? FilterLayer {
                    let rectIdx = handleIndex / 8
                    filter.selectedRectIndex = rectIdx
                    if rectIdx < filter.rects.count {
                        initialRectForDrag = filter.rects[rectIdx]
                    }
                }
                return
            }
        }

        // Callout or Text body (tip handle already handled above): a double-click edits any callout/text,
        // a click on the selected one edits on mouse-up unless it becomes a drag
        if let hitEditable = document.layers.reversed().first(where: { $0.isVisible && ($0 as? TextEditableLayer)?.bodyRect.contains(point) == true }) as? TextEditableLayer {
            if event.clickCount >= 2 {
                beginCalloutEditing(hitEditable, isNew: false, caretAt: point)
                return
            }
            if document.selectedLayerIDs == [hitEditable.id] {
                pendingEditCallout = hitEditable
            }
        }

        // If clicking on or inside an already selected layer (e.g. Rectangle), drag-move it
        if let selected = document.getSelectedLayers().first {
            if selected.contains(point: point) {
                document.saveSnapshot()
                if document.activeTool != .select && document.activeTool != .blur {
                    document.activeTool = .select
                    (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                    document.selectLayer(selected)
                }
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
                return
            }
        }

        // If clicking any existing visible annotation element while an annotation tool is active,
        // do not add a new element; immediately select it and revert activeTool to pointer (.select)
        if let hit = document.layers.reversed().first(where: { $0.isVisible && $0.contains(point: point) }) {
            document.saveSnapshot()
            if document.activeTool != .select && document.activeTool != .blur {
                document.activeTool = .select
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
            }
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
            return
        }

        // If clicking inside a spotlight rectangle (hollow center) while spotlight tool is active, cancel tool to "Select (V)"
        if document.activeTool == .spotlight {
            if let spotlight = document.layers.reversed().first(where: { ($0 as? FilterLayer)?.filterMode == .spotlight }) as? FilterLayer {
                if let rectIdx = spotlight.rects.indices.reversed().first(where: { spotlight.rects[$0].standardized.contains(point) }) {
                    document.saveSnapshot()
                    document.activeTool = .select
                    (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                    document.selectLayer(spotlight)
                    spotlight.selectedRectIndex = rectIdx
                    needsDisplay = true
                    return
                }
            }
        }

        switch document.activeTool {
        case .select:
            if let layer = document.selectLayer(at: point) {
                document.saveSnapshot()
                activeDraggingLayer = layer
                activeHandleIndex = nil
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
            } else {
                document.selectedLayerIDs.removeAll()
                if document.activeTool != .select {
                    document.activeTool = .select
                }
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
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

        case .spotlight:
            let spot = FilterLayer(
                rects: [CGRect(origin: point, size: .zero)],
                filterMode: .spotlight,
                color: document.activeColor
            )
            activeCreatingLayer = spot

        case .blur:
            let blur = FilterLayer(
                rects: [CGRect(origin: point, size: .zero)],
                filterMode: .gaussian,
                intensity: 6.0,
                color: document.activeColor
            )
            activeCreatingLayer = blur

        case .callout:
            // The press pins the beak tip; dragging places the body while the tip stays put
            let callout = CalloutLayer(tip: point, color: document.activeColor)
            calloutGrabOffset = CGPoint(x: point.x - callout.origin.x, y: point.y - callout.origin.y)
            activeCreatingLayer = callout

        case .text:
            let textLayer = TextLayer(center: point, color: document.activeColor)
            activeCreatingLayer = textLayer
        }

        needsDisplay = true
    }

    override public func mouseDragged(with event: NSEvent) {
        let point = canvasPoint(from: event)
        // A pending edit click stays a click until it moves more than 3 pt; the callout only
        // starts moving then, so a click that edits leaves the layer untouched
        if pendingEditCallout != nil {
            if hypot(point.x - dragStartPoint.x, point.y - dragStartPoint.y) <= 3.0 { return }
            pendingEditCallout = nil
        }

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
                } else if let ellipseLayer = dragging as? EllipseLayer, let initRect = initialRectForDrag {
                    // Ellipse handles:
                    // 0: Top-Center (vertical resize)
                    // 1: Right-Center (horizontal resize)
                    // 2: Bottom-Center (vertical resize)
                    // 3: Left-Center (horizontal resize)
                    switch handleIdx {
                    case 0: // Top edge: vertical resize
                        let oppY = initRect.maxY
                        let newY = min(point.y, oppY)
                        let newH = max(4.0, abs(point.y - oppY))
                        var newRect = CGRect(x: initRect.minX, y: newY, width: initRect.width, height: newH)
                        if ellipseLayer.isPerfectCircle || isShiftPressed {
                            let side = newH
                            let cx = initRect.midX
                            newRect = CGRect(x: cx - side / 2.0, y: newY, width: side, height: side)
                        }
                        ellipseLayer.rect = newRect

                    case 1: // Right edge: horizontal resize
                        let oppX = initRect.minX
                        let newX = min(point.x, oppX)
                        let newW = max(4.0, abs(point.x - oppX))
                        var newRect = CGRect(x: newX, y: initRect.minY, width: newW, height: initRect.height)
                        if ellipseLayer.isPerfectCircle || isShiftPressed {
                            let side = newW
                            let cy = initRect.midY
                            newRect = CGRect(x: newX, y: cy - side / 2.0, width: side, height: side)
                        }
                        ellipseLayer.rect = newRect

                    case 2: // Bottom edge: vertical resize
                        let oppY = initRect.minY
                        let newY = min(point.y, oppY)
                        let newH = max(4.0, abs(point.y - oppY))
                        var newRect = CGRect(x: initRect.minX, y: newY, width: initRect.width, height: newH)
                        if ellipseLayer.isPerfectCircle || isShiftPressed {
                            let side = newH
                            let cx = initRect.midX
                            newRect = CGRect(x: cx - side / 2.0, y: newY, width: side, height: side)
                        }
                        ellipseLayer.rect = newRect

                    case 3: // Left edge: horizontal resize
                        let oppX = initRect.maxX
                        let newX = min(point.x, oppX)
                        let newW = max(4.0, abs(point.x - oppX))
                        var newRect = CGRect(x: newX, y: initRect.minY, width: newW, height: initRect.height)
                        if ellipseLayer.isPerfectCircle || isShiftPressed {
                            let side = newW
                            let cy = initRect.midY
                            newRect = CGRect(x: newX, y: cy - side / 2.0, width: side, height: side)
                        }
                        ellipseLayer.rect = newRect

                    default:
                        ellipseLayer.updateHandle(index: handleIdx, to: point)
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
                    let dpx = point.x - last.x
                    let dpy = point.y - last.y
                    if dpx * dpx + dpy * dpy >= 4.0 {
                        pen.points.append(point)
                    }
                } else {
                    pen.points.append(point)
                }
            } else if let hl = creating as? HighlighterLayer {
                if let last = hl.points.last {
                    let dpx = point.x - last.x
                    let dpy = point.y - last.y
                    if dpx * dpx + dpy * dpy >= 4.0 {
                        hl.points.append(point)
                    }
                } else {
                    hl.points.append(point)
                }
            } else if let dim = creating as? DimensionLayer {
                dim.end = point
            } else if let callout = creating as? CalloutLayer {
                callout.origin = CGPoint(x: point.x - calloutGrabOffset.x, y: point.y - calloutGrabOffset.y)
            } else if let textLayer = creating as? TextLayer {
                textLayer.center = point
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
        if let callout = pendingEditCallout {
            pendingEditCallout = nil
            // The mouseDown drag snapshot is a no-op; the editing session records its own step
            document.discardLastSnapshot()
            activeDraggingLayer = nil
            beginCalloutEditing(callout, isNew: false, caretAt: canvasPoint(from: event))
        }
        if let creating = activeCreatingLayer {
            if let counter = creating as? CounterLayer {
                document.counterStep = counter.value + 1
                document.addLayer(counter)
                document.selectLayer(counter)
            } else if let callout = creating as? CalloutLayer {
                // Appended without addLayer's snapshot: the editing session records one undo step when it ends
                let preSession = document.layers.map { $0.clone() }
                document.layers.append(callout)
                activeCreatingLayer = nil
                document.computeElasticBounds()
                beginCalloutEditing(callout, isNew: true, preSession: preSession)
            } else if let textLayer = creating as? TextLayer {
                let preSession = document.layers.map { $0.clone() }
                document.layers.append(textLayer)
                activeCreatingLayer = nil
                document.computeElasticBounds()
                beginCalloutEditing(textLayer, isNew: true, preSession: preSession)
            } else {
                var isValidSize = true

                if let arrow = creating as? ArrowLayer {
                    let dx = arrow.end.x - arrow.start.x
                    let dy = arrow.end.y - arrow.start.y
                    isValidSize = dx * dx + dy * dy >= 100.0
                } else if let rect = creating as? RectangleLayer {
                    isValidSize = rect.rect.width >= 6.0 && rect.rect.height >= 6.0
                } else if let ellipse = creating as? EllipseLayer {
                    isValidSize = ellipse.rect.width >= 6.0 && ellipse.rect.height >= 6.0
                } else if let line = creating as? LineLayer {
                    let dx = line.end.x - line.start.x
                    let dy = line.end.y - line.start.y
                    isValidSize = dx * dx + dy * dy >= 36.0
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
                } else if let filter = creating as? FilterLayer, filter.filterMode == .spotlight {
                    // Clicking on the overlay without creating a valid rectangle cancels tool to "Select (V)"
                    document.cleanupEmptySpotlight()
                    if document.activeTool != .select {
                        document.activeTool = .select
                    }
                }
            }
            activeCreatingLayer = nil
            (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
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

        // Convert window points into clipView document coordinates, which automatically
        // divides by magnification and handles the flipped coordinate system, ensuring
        // the canvas moves 1:1 with screen pixels regardless of zoom level.
        let p1 = clipView.convert(rightPanStartWindowPoint, from: nil)
        let p2 = clipView.convert(currentWindowPoint, from: nil)
        let deltaX = p2.x - p1.x
        let deltaY = p2.y - p1.y
        rightPanStartWindowPoint = currentWindowPoint

        var newOrigin = clipView.bounds.origin
        newOrigin.x -= deltaX
        newOrigin.y -= deltaY

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
            if let filter = newLayer as? FilterLayer, filter.filterMode != .spotlight {
                hoverOutlineLayer = nil
            } else {
                hoverOutlineLayer = newLayer
            }
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
        } else if let hl = layer as? HighlighterLayer {
            return hl.hoverOutlinePath()
        } else if let pen = layer as? PenLayer {
            return pen.hoverOutlinePath()
        } else if let filter = layer as? FilterLayer {
            // Blur tool must have NO OUTLINE. Zero outline. Never outline.
            guard filter.filterMode == .spotlight else { return nil }
            let path = CGMutablePath()
            let rectsToOutline: [CGRect]
            if filter.rects.count > 1, let pt = currentMouseCanvasPoint, let idx = filter.rectIndex(at: pt) ?? filter.hitTestHandle(point: pt).map({ $0 / 8 }) {
                rectsToOutline = [filter.rects[idx]]
            } else {
                rectsToOutline = filter.rects
            }
            for r in rectsToOutline {
                guard r.width > 0 && r.height > 0 else { continue }
                let effectiveRadius = max(0.0, min(filter.cornerRadius, min(r.width / 2.0, r.height / 2.0)))
                path.addPath(CGPath(roundedRect: r, cornerWidth: effectiveRadius, cornerHeight: effectiveRadius, transform: nil))
            }
            return path.isEmpty ? nil : path
        } else if let callout = layer as? CalloutLayer {
            return callout.pathForCallout()
        } else if let textLayer = layer as? TextLayer {
            return CGPath(roundedRect: textLayer.bodyRect, cornerWidth: 4.0, cornerHeight: 4.0, transform: nil)
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

        // Subtle color tint inside the brush outline
        context.setFillColor(FastColor.shared.cgColor(hex: document.activeColor, alpha: 0.25))
        context.fillEllipse(in: rect)

        // Outer contrasting stroke (dark shadow/stroke)
        context.setStrokeColor(Self.brushDarkOutlineCGColor)
        context.setLineWidth(max(1.0, strokeWidth <= 6.0 ? 1.0 : 2.0))
        context.strokeEllipse(in: rect)

        // Inner bright stroke
        context.setStrokeColor(Self.brushLightOutlineCGColor)
        context.setLineWidth(max(0.5, strokeWidth <= 6.0 ? 0.75 : 1.0))
        context.strokeEllipse(in: rect)

        // Center crosshair / precision dot
        context.setFillColor(Self.handleFillCGColor)
        context.fillEllipse(in: CGRect(x: point.x - 0.75, y: point.y - 0.75, width: 1.5, height: 1.5))

        context.restoreGState()
    }

    private func drawBlurHighlight(rect: CGRect, in context: CGContext) {
        guard rect.width > 0 && rect.height > 0 else { return }
        context.saveGState()

        let effectiveRadius = max(0.0, min(6.0, min(rect.width / 2.0, rect.height / 2.0)))
        let path = CGPath(roundedRect: rect, cornerWidth: effectiveRadius, cornerHeight: effectiveRadius, transform: nil)

        // Frosted translucent highlight fill with zero outline
        context.setFillColor(Self.blurHighlightFillCGColor)
        context.addPath(path)
        context.fillPath()

        context.restoreGState()
    }

    override public func resetCursorRects() {
        super.resetCursorRects()
        if isEditingCallout {
            // CalloutTextView adds its own I-beam rect over the text box
            addCursorRect(bounds, cursor: .arrow)
            return
        }
        let cursor: NSCursor
        switch document.activeTool {
        case .select: cursor = .arrow
        case .callout: cursor = .iBeam
        default: cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override public func cursorUpdate(with event: NSEvent) {
        let point = canvasPoint(from: event)
        updateCursorForPoint(point)
    }

    private func cursorForHandle(on layer: AnnotationLayer, handleIndex: Int) -> NSCursor {
        if layer is RectangleLayer || layer is FilterLayer {
            let subIdx = handleIndex % 8
            switch subIdx {
            case 0, 4:
                return NSCursor.sleekResizeDiagonalNWSE
            case 2, 6:
                return NSCursor.sleekResizeDiagonalNESW
            case 1, 5:
                return NSCursor.sleekResizeUpDown
            case 3, 7:
                return NSCursor.sleekResizeLeftRight
            default:
                return NSCursor.sleekResizeDiagonalNWSE
            }
        }
        if layer is EllipseLayer {
            switch handleIndex {
            case 0, 2: // Top and Bottom handles: vertical resize
                return NSCursor.sleekResizeUpDown
            case 1, 3: // Right and Left handles: horizontal resize
                return NSCursor.sleekResizeLeftRight
            default:
                return NSCursor.sleekResizeUpDown
            }
        }
        if let line = layer as? LineLayer {
            return directionalResizeCursor(from: line.start, to: line.end)
        }
        if let arrow = layer as? ArrowLayer {
            return directionalResizeCursor(from: arrow.start, to: arrow.end)
        }
        if let dim = layer as? DimensionLayer {
            return directionalResizeCursor(from: dim.start, to: dim.end)
        }
        return NSCursor.sleekMove
    }

    private func directionalResizeCursor(from: CGPoint, to: CGPoint) -> NSCursor {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let angle = atan2(dy, dx)
        var deg = angle * 180.0 / .pi
        while deg < -90 { deg += 180 }
        while deg > 90 { deg -= 180 }
        if deg > -22.5 && deg <= 22.5 {
            return NSCursor.sleekResizeLeftRight
        } else if deg > 67.5 || deg <= -67.5 {
            return NSCursor.sleekResizeUpDown
        } else if deg > 22.5 && deg <= 67.5 {
            return NSCursor.sleekResizeDiagonalNWSE
        } else {
            return NSCursor.sleekResizeDiagonalNESW
        }
    }

    private func updateCursorForPoint(_ point: CGPoint) {
        if isRightPanning {
            NSCursor.closedHand.set()
            return
        }

        // While typing, the text box shows the text cursor; a click anywhere else only finishes editing
        if let session = calloutSession {
            if session.layer.bodyRect.contains(point) {
                NSCursor.iBeam.set()
            } else {
                NSCursor.arrow.set()
            }
            return
        }

        // While actively dragging a layer's body, maintain the sleek 4-directional move cursor
        if activeDraggingLayer != nil && activeHandleIndex == nil {
            NSCursor.sleekMove.set()
            return
        }

        // If dragging or hovering over a handle, use appropriate sleek handle cursor
        if let selected = document.getSelectedLayers().first,
           let handleIndex = selected.hitTestHandle(point: point) {
            cursorForHandle(on: selected, handleIndex: handleIndex).set()
            return
        }
        if let hovered = hoveredLayer, let handleIndex = hovered.hitTestHandle(point: point) {
            cursorForHandle(on: hovered, handleIndex: handleIndex).set()
            return
        }

        // Check if hovering over any movable layer border/body
        if hoveredLayer != nil {
            NSCursor.sleekMove.set()
            return
        }
        let hitsMovableLayer = document.layers.reversed().contains { layer in
            layer.isVisible && layer.contains(point: point)
        }
        if hitsMovableLayer {
            NSCursor.sleekMove.set()
            return
        }

        // Also if any already selected layer contains the point (even if switching tools), dragging it moves it
        let hitsSelectedLayer = document.getSelectedLayers().contains { layer in
            layer.isVisible && layer.contains(point: point)
        }
        if hitsSelectedLayer {
            NSCursor.sleekMove.set()
            return
        }

        // Default tool cursors
        switch document.activeTool {
        case .select:
            NSCursor.arrow.set()
        case .callout, .text:
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
        // Safety net: Esc normally reaches the editor first (cancelOperation:)
        if isEditingCallout {
            endCalloutEditing()
            return
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

        if wasCreating || wasDragging || hasSelection || isNonPointerTool {
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

    @discardableResult
    public func nudgeSelectedLayers(keyCode: UInt16, isShift: Bool, isRepeat: Bool = false) -> Bool {
        let selectedLayers = document.getSelectedLayers()
        guard !selectedLayers.isEmpty else { return false }

        let step: CGFloat = isShift ? 10.0 : 1.0
        let delta: CGPoint

        switch keyCode {
        case 123: // Left Arrow
            delta = CGPoint(x: -step, y: 0)
        case 124: // Right Arrow
            delta = CGPoint(x: step, y: 0)
        case 125: // Down Arrow
            delta = CGPoint(x: 0, y: step)
        case 126: // Up Arrow
            delta = CGPoint(x: 0, y: -step)
        default:
            return false
        }

        if !isRepeat {
            document.saveSnapshot()
        }

        for layer in selectedLayers {
            layer.move(by: delta)
        }

        document.computeElasticBounds()
        needsDisplay = true
        return true
    }

    override public func cancelOperation(_ sender: Any?) {
        handleEscapeKey()
    }

    override public func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            handleEscapeKey()
            return
        }
        if event.keyCode == 123 || event.keyCode == 124 || event.keyCode == 125 || event.keyCode == 126 { // Arrow keys
            let isShift = event.modifierFlags.contains(.shift)
            if nudgeSelectedLayers(keyCode: event.keyCode, isShift: isShift, isRepeat: event.isARepeat) {
                return
            }
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
            copySelectionOrComposition()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "x" {
            cutSelectedLayers()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
            pasteLayers()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "d" {
            duplicateSelectedLayers()
        } else if event.modifierFlags.contains(.command) && (event.charactersIgnoringModifiers == "=" || event.charactersIgnoringModifiers == "+") {
            (window as? EditorPanel)?.zoomIn()
        } else if event.modifierFlags.contains(.command) && (event.charactersIgnoringModifiers == "-" || event.charactersIgnoringModifiers == "_") {
            (window as? EditorPanel)?.zoomOut()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "1" {
            (window as? EditorPanel)?.scaleToFit()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "0" {
            (window as? EditorPanel)?.resetZoom()
        } else if !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) {
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
            } else if key == "o" {
                document.activeTool = .ellipse
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                needsDisplay = true
            } else if key == "m" {
                document.activeTool = .dimension
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                needsDisplay = true
            } else if key == "t" {
                document.activeTool = .callout
                (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
                needsDisplay = true
            } else if key == "x" {
                document.activeTool = .text
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
            guard newMag != oldMag else { return }

            let clipBounds = sv.contentView.bounds
            let location = event.locationInWindow
            let clipPoint = sv.contentView.convert(location, from: nil)
            let anchor = clipBounds.contains(clipPoint) ? clipPoint : NSPoint(x: clipBounds.midX, y: clipBounds.midY)

            sv.setMagnification(newMag, centeredAt: anchor)
            zoomScale = sv.magnification
            (window as? EditorPanel)?.updateMetaLabel()
        } else {
            super.magnify(with: event)
        }
    }

    // MARK: - macOS Scroll Wheel (Cmd + Scroll to Zoom)

    override public func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            handleZoomWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    public func handleZoomWheel(with event: NSEvent) {
        if let panel = window as? EditorPanel {
            panel.handleZoomWheel(with: event)
        } else if let sv = enclosingScrollView {
            handleZoomWheelDirect(with: event, scrollView: sv)
        }
    }

    private func handleZoomWheelDirect(with event: NSEvent, scrollView sv: NSScrollView) {
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
        zoomScale = sv.magnification
        (window as? EditorPanel)?.updateMetaLabel()
    }

    // MARK: - Annotation Clipboard (⌘C / ⌘X / ⌘V / ⌘D)
    // While a callout's text is edited, CalloutTextView takes ⌘C / ⌘X / ⌘V for the text first

    /// ⌘C: copies the selected annotations silently; with nothing selected, the flattened composition
    public func copySelectionOrComposition() {
        if !isEditingCallout && document.copySelectedLayers() {
            return
        }
        copyCompositionToClipboard()
        (window as? EditorPanel)?.showCopiedToClipboardToast()
    }

    public func cutSelectedLayers() {
        guard !isEditingCallout, document.cutSelectedLayers() else { return }
        clearHoverStateImmediately()
        needsDisplay = true
    }

    /// Pastes and selects the copies; the document switches to the Select tool so they can be dragged
    public func pasteLayers() {
        guard !isEditingCallout, document.pasteLayers() else { return }
        (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
        needsDisplay = true
    }

    public func duplicateSelectedLayers() {
        guard !isEditingCallout, document.duplicateSelectedLayers() else { return }
        (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
        needsDisplay = true
    }

    // MARK: - Clipboard & Drag Export (Section 1 & 4)

    public func copyCompositionToClipboard() {
        endCalloutEditingIfNeeded()
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
        endCalloutEditingIfNeeded()
        guard let rendered = document.renderComposition() else { return }
        let rep = NSBitmapImageRep(cgImage: rendered)
        let properties: [NSBitmapImageRep.PropertyKey: Any] = (format == .jpeg) ? [.compressionFactor: 0.95] : [:]
        guard let data = rep.representation(using: format, properties: properties) else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("EditorCanvasView: Failed to save composition to %@: %@", url.path, error.localizedDescription)
        }
    }

    // MARK: - Callout Text Editing

    /// Opens a transparent editor over the callout/text body; the layer draws only the bubble/shadow meanwhile
    func beginCalloutEditing(_ layer: TextEditableLayer, isNew: Bool, preSession: [AnnotationLayer]? = nil, caretAt point: CGPoint? = nil) {
        endCalloutEditing()

        calloutSession = CalloutEditSession(
            layer: layer,
            isNew: isNew,
            preSession: preSession ?? document.layers.map { $0.clone() },
            originalText: layer.text,
            originalColor: layer.color
        )
        layer.isTextHidden = true
        document.selectedLayerIDs = [layer.id]

        let editor = CalloutTextView()
        editor.string = layer.text
        editor.apply(textColor: layer.textColor, withShadow: layer is TextLayer)
        editor.session = self
        editor.delegate = self
        calloutEditor = editor
        addSubview(editor)
        positionCalloutEditor()
        var caret = (editor.string as NSString).length
        if let point = point {
            // Caret at the clicked character: canvas point → view point → editor coordinates
            let canvasOrigin = document.activeCanvasBounds.origin
            let viewPoint = CGPoint(x: point.x - canvasOrigin.x, y: point.y - canvasOrigin.y)
            caret = editor.characterIndexForInsertion(at: editor.convert(viewPoint, from: self))
        }
        editor.setSelectedRange(NSRange(location: caret, length: 0))

        if isNew {
            resetZoomAndCenterIfNeeded(around: layer)
        }

        // The caret must blink right away: make sure the panel is key so keystrokes reach the editor
        if let window = window {
            if window.isVisible && (!window.isKeyWindow || !NSApp.isActive) {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
            window.makeFirstResponder(editor)
            window.invalidateCursorRects(for: self)
        }
        if let mousePoint = currentMouseCanvasPoint {
            updateCursorForPoint(mousePoint)
        }
        needsDisplay = true
    }

    /// When adding a callout or text and zoom is < 100%, resets zoom to 100%
    /// and centers around the annotation as close as the current canvas setup allows.
    public func resetZoomAndCenterIfNeeded(around layer: AnnotationLayer) {
        let currentZoom = enclosingScrollView?.magnification ?? zoomScale
        guard currentZoom < 0.9999 else { return }

        let box = layer.getBoundingBox()
        let annotationCenter = CGPoint(x: box.midX, y: box.midY)

        if let sv = enclosingScrollView {
            let clipView = sv.contentView
            sv.magnification = 1.0
            zoomScale = sv.magnification

            let canvasOrigin = document.activeCanvasBounds.origin
            let targetViewX = annotationCenter.x - canvasOrigin.x
            let targetViewY = annotationCenter.y - canvasOrigin.y
            let viewportSize = clipView.bounds.size

            let proposedOrigin = NSPoint(
                x: round(targetViewX - viewportSize.width / 2.0),
                y: round(targetViewY - viewportSize.height / 2.0)
            )
            let constrainedOrigin = clipView.constrainBoundsRect(NSRect(origin: proposedOrigin, size: viewportSize)).origin

            clipView.scroll(to: constrainedOrigin)
            sv.reflectScrolledClipView(clipView)

            (window as? EditorPanel)?.updateMetaLabel()
        } else {
            zoomScale = 1.0
        }
        needsDisplay = true
    }

    /// Commits the session: empty text removes the callout, a change becomes one undo step,
    /// and the finished callout stays selected with the Select tool active
    public func endCalloutEditing() {
        finishCalloutEditing(switchToSelect: true)
    }

    /// Finishes a session before anything that must not see it open (export, window close)
    public func endCalloutEditingIfNeeded() {
        if isEditingCallout {
            endCalloutEditing()
        }
    }

    /// New callouts change the document once they hold text; existing ones when text or color differ
    private func calloutSessionChanged(_ session: CalloutEditSession, text: String) -> Bool {
        session.isNew ? !text.isEmpty : (text != session.originalText || session.layer.color != session.originalColor)
    }

    /// `switchToSelect` is false when a tool change ends the session: the chosen tool stays and nothing is selected
    private func finishCalloutEditing(switchToSelect: Bool) {
        guard let session = calloutSession, !isEndingCalloutEditing else { return }
        isEndingCalloutEditing = true
        defer { isEndingCalloutEditing = false }
        let callout = session.layer
        let editor = calloutEditor
        if let editor = editor {
            callout.text = editor.string
        }
        calloutSession = nil
        calloutEditor = nil

        let removed = callout.text.isEmpty
        if removed {
            document.layers.removeAll { $0.id == callout.id }
        }
        if calloutSessionChanged(session, text: callout.text) {
            document.pushSnapshot(session.preSession)
            document.isModified = true
        }
        callout.isTextHidden = false

        if let editor = editor {
            let hadFocus = window?.firstResponder === editor
            editor.session = nil
            editor.delegate = nil
            editor.removeFromSuperview()
            if hadFocus {
                window?.makeFirstResponder(self)
            }
        }

        // Set the tool first: its didSet clears the selection
        if switchToSelect && document.activeTool != .select {
            document.activeTool = .select
        }
        document.selectedLayerIDs = removed || document.activeTool != .select ? [] : [callout.id]
        document.computeElasticBounds()
        (window as? EditorPanel)?.toolbarView.updateSelectedToolVisuals()
        window?.invalidateCursorRects(for: self)
        if let mousePoint = currentMouseCanvasPoint {
            updateCursorForPoint(mousePoint)
        }
        needsDisplay = true
    }

    /// ⌘Z while editing: finishes the session and takes it back as a whole. An unchanged session
    /// pushed no undo step, so ending it is the whole revert and no earlier step is touched
    func revertCalloutSession() {
        guard let session = calloutSession else { return }
        let changed = calloutSessionChanged(session, text: calloutEditor?.string ?? session.layer.text)
        endCalloutEditing()
        if changed {
            document.undo()
        }
    }

    /// Re-applies the editing text color after a recolor (white text flips to dark on white)
    public func syncCalloutEditorAppearance() {
        guard let editor = calloutEditor, let session = calloutSession else { return }
        editor.apply(textColor: session.layer.textColor, withShadow: session.layer is TextLayer)
        editor.needsDisplay = true
    }

    /// Keeps the editor exactly over the body: view coordinates = canvas coordinates − elastic origin
    private func positionCalloutEditor() {
        guard let editor = calloutEditor, let session = calloutSession else { return }
        let canvasOrigin = document.activeCanvasBounds.origin
        let frame = session.layer.bodyRect.offsetBy(dx: -canvasOrigin.x, dy: -canvasOrigin.y)
        if editor.frame != frame {
            editor.frame = frame
        }
    }

    // NSDraggingSource
    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

}

extension EditorCanvasView: CalloutEditingSession, NSTextViewDelegate {
    public func textDidChange(_ notification: Notification) {
        guard let editor = notification.object as? CalloutTextView, editor === calloutEditor,
              let callout = calloutSession?.layer else { return }
        // The body re-measures from the text, so the bubble grows and shrinks with every keystroke
        callout.text = editor.string
        document.computeElasticBounds()
        positionCalloutEditor()
        needsDisplay = true
    }

    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard textView === calloutEditor else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            endCalloutEditing()
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) || commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            return true
        }
        return false
    }
}
