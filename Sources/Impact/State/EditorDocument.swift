import Foundation
import CoreGraphics
import AppKit

public final class EditorDocument {
    public let originalImage: CGImage
    public let originalImageBounds: CGRect
    public private(set) var activeCanvasBounds: CGRect

    public var layers: [AnnotationLayer] = []
    public var isModified: Bool = false
    public var onSelectionChanged: (() -> Void)?

    public var selectedLayerIDs: Set<UUID> = [] {
        didSet {
            if selectedLayerIDs != oldValue {
                onSelectionChanged?()
            }
        }
    }

    public var activeTool: LayerType = .select {
        didSet {
            if activeTool != oldValue {
                if oldValue == .spotlight {
                    cleanupEmptySpotlight()
                }
                if activeTool == .spotlight {
                    ensureSpotlightOverlay()
                }
                selectedLayerIDs.removeAll()
                onNeedsDisplay?()
                onSelectionChanged?()
                onActiveToolChanged?(activeTool)
            }
        }
    }
    /// Fires after every tool change (the canvas finishes a callout editing session on it)
    public var onActiveToolChanged: ((LayerType) -> Void)?
    public var activeColor: String = "#FF3B30"
    public var activeStrokeWidth: CGFloat = 4.0
    public var activeFontSize: CGFloat = 16.0
    public var counterStep: Int = 1

    /// Ensures a single unified spotlight overlay layer exists in the document
    public func ensureSpotlightOverlay() {
        if let existing = layers.first(where: { ($0 as? FilterLayer)?.filterMode == .spotlight }) as? FilterLayer {
            selectedLayerIDs = [existing.id]
            return
        }
        let overlay = FilterLayer(rects: [], filterMode: .spotlight, color: activeColor)
        // Ensure spotlight is positioned after any existing blur layers so blur areas remain under spotlight
        if let lastBlurIndex = layers.lastIndex(where: { ($0 as? FilterLayer)?.filterMode != .spotlight }) {
            layers.insert(overlay, at: lastBlurIndex + 1)
        } else {
            layers.insert(overlay, at: 0)
        }
        selectedLayerIDs = [overlay.id]
    }

    /// Removes an empty spotlight overlay if no holes were created
    public func cleanupEmptySpotlight() {
        layers.removeAll { layer in
            if let filter = layer as? FilterLayer, filter.filterMode == .spotlight {
                return filter.rects.isEmpty
            }
            return false
        }
    }

    /// Computes the next integer in sequence by reading highest existing counter value
    public func nextCounterValue() -> Int {
        let maxExisting = layers.compactMap { ($0 as? CounterLayer)?.value }.max() ?? 0
        return max(counterStep, maxExisting + 1)
    }

    // Undo / Redo
    private var undoStack: [[AnnotationLayer]] = []
    private var redoStack: [[AnnotationLayer]] = []

    public var onBoundsChanged: ((CGRect) -> Void)?
    public var onNeedsDisplay: (() -> Void)?

    public init(image: CGImage) {
        self.originalImage = image
        self.originalImageBounds = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
        self.activeCanvasBounds = self.originalImageBounds
    }

    private static let colorSpaceRGB = CGColorSpaceCreateDeviceRGB()
    private static let colorSpaceSRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Creates a minimal 1x1 placeholder document when EditorPanel opens without an image
    public static func makePlaceholder() -> EditorDocument {
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpaceRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return EditorDocument(image: context.makeImage()!)
    }

    // MARK: - Layer Management

    public func addLayer(_ layer: AnnotationLayer) {
        saveSnapshot()
        if let filter = layer as? FilterLayer, filter.filterMode != .spotlight,
           let spotlightIndex = layers.firstIndex(where: { ($0 as? FilterLayer)?.filterMode == .spotlight }) {
            // Blur areas must always be UNDER spotlight's overlay in layer hierarchy
            layers.insert(layer, at: spotlightIndex)
        } else {
            layers.append(layer)
        }
        selectedLayerIDs = [layer.id]
        isModified = true
        computeElasticBounds()
        onNeedsDisplay?()
    }

    public func removeLayer(id: UUID) {
        saveSnapshot()
        layers.removeAll { $0.id == id }
        selectedLayerIDs.remove(id)
        isModified = true
        computeElasticBounds()
        onNeedsDisplay?()
    }

    public func removeSelectedLayers() {
        guard !selectedLayerIDs.isEmpty else { return }
        saveSnapshot()
        isModified = true
        for id in selectedLayerIDs {
            if let spotlight = layers.first(where: { $0.id == id }) as? FilterLayer, spotlight.filterMode == .spotlight {
                if spotlight.rects.count > 1, let idx = spotlight.selectedRectIndex, idx < spotlight.rects.count {
                    spotlight.rects.remove(at: idx)
                    spotlight.selectedRectIndex = max(0, spotlight.rects.count - 1)
                    continue
                }
            }
            layers.removeAll { $0.id == id }
        }
        // When the last spotlight rectangle is removed, the overlay disappears
        layers.removeAll { layer in
            if let filter = layer as? FilterLayer, filter.filterMode == .spotlight {
                return filter.rects.isEmpty
            }
            return false
        }
        selectedLayerIDs.removeAll()
        computeElasticBounds()
        onNeedsDisplay?()
    }

    public func selectLayer(_ layer: AnnotationLayer) {
        selectedLayerIDs = [layer.id]
        if layer.type != .blur {
            activeColor = layer.color
        }
        onNeedsDisplay?()
    }

    public func selectLayer(at point: CGPoint) -> AnnotationLayer? {
        // Reverse iterate to select top-most layer
        for layer in layers.reversed() {
            if layer.isVisible && layer.contains(point: point) {
                selectedLayerIDs = [layer.id]
                if layer.type != .blur {
                    activeColor = layer.color
                }
                onNeedsDisplay?()
                return layer
            }
        }
        selectedLayerIDs.removeAll()
        onNeedsDisplay?()
        return nil
    }

    public func getSelectedLayers() -> [AnnotationLayer] {
        layers.filter { selectedLayerIDs.contains($0.id) }
    }

    // MARK: - Copy / Cut / Paste / Duplicate

    /// Offset of each paste step and of a duplicate, right and down in canvas points
    public static let pasteOffset: CGFloat = 10.0

    /// Stores the selection in the annotation clipboard; false when nothing is selected
    @discardableResult
    public func copySelectedLayers(to clipboard: AnnotationClipboard = .shared) -> Bool {
        let selected = getSelectedLayers()
        guard !selected.isEmpty else { return false }
        clipboard.store(selected)
        return true
    }

    /// Copies the selection, then removes it as one undo step
    @discardableResult
    public func cutSelectedLayers(to clipboard: AnnotationClipboard = .shared) -> Bool {
        guard copySelectedLayers(to: clipboard) else { return false }
        saveSnapshot()
        // Whole layers go (a spotlight with every rectangle), unlike Delete, which takes one spotlight rectangle
        layers.removeAll { selectedLayerIDs.contains($0.id) }
        selectedLayerIDs.removeAll()
        isModified = true
        computeElasticBounds()
        onNeedsDisplay?()
        return true
    }

    /// Adds copies of the clipboard contents, one offset step further than the previous paste
    @discardableResult
    public func pasteLayers(from clipboard: AnnotationClipboard = .shared) -> Bool {
        guard let paste = clipboard.nextPaste() else { return false }
        let distance = CGFloat(paste.step) * Self.pasteOffset
        insertCopies(of: paste.layers, offset: CGPoint(x: distance, y: distance))
        return true
    }

    /// Copies the selection one offset step away without touching the clipboard
    @discardableResult
    public func duplicateSelectedLayers() -> Bool {
        let selected = getSelectedLayers()
        guard !selected.isEmpty else { return false }
        insertCopies(of: selected, offset: CGPoint(x: Self.pasteOffset, y: Self.pasteOffset))
        return true
    }

    /// Inserts offset copies with fresh ids on top of the stack (keeping their relative order),
    /// renumbers counters to continue this canvas's sequence and selects the copies. One undo step.
    private func insertCopies(of sources: [AnnotationLayer], offset: CGPoint) {
        // Set the tool first: its didSet clears the selection
        if activeTool != .select {
            activeTool = .select
        }
        saveSnapshot()

        let copies = sources.map { $0.clone(withID: UUID()) }
        for copy in copies {
            if let filter = copy as? FilterLayer {
                // FilterLayer.move(by:) shifts only its selected rectangle; copies move as a whole
                filter.rects = filter.rects.map { $0.offsetBy(dx: offset.x, dy: offset.y) }
            } else {
                copy.move(by: offset)
            }
        }

        // Vector layers draw sorted by zIndex with ties in array order: lift the copies to the top z-order
        let isVector: (AnnotationLayer) -> Bool = { !($0 is FilterLayer) }
        let topZ = layers.filter(isVector).map { $0.zIndex }.max() ?? 0
        if let lowestCopyZ = copies.filter(isVector).map({ $0.zIndex }).min(), lowestCopyZ < topZ {
            for copy in copies where isVector(copy) {
                copy.zIndex += topZ - lowestCopyZ
            }
        }

        // Counters continue after the highest one on this canvas, numbered in their original order
        var nextValue = (layers.compactMap { ($0 as? CounterLayer)?.value }.max() ?? 0) + 1
        let counters = copies.compactMap { $0 as? CounterLayer }
        for counter in counters.sorted(by: { $0.value < $1.value }) {
            counter.value = nextValue
            nextValue += 1
        }

        var newSelection: Set<UUID> = []
        for copy in copies {
            let spotlightIndex = layers.firstIndex { ($0 as? FilterLayer)?.filterMode == .spotlight }
            if let filter = copy as? FilterLayer, filter.filterMode == .spotlight,
               let index = spotlightIndex, let existing = layers[index] as? FilterLayer {
                // A canvas keeps a single spotlight overlay: pasted rectangles join it
                existing.rects += filter.rects
                existing.selectedRectIndex = existing.rects.count - 1
                newSelection.insert(existing.id)
                continue
            }
            if let filter = copy as? FilterLayer, filter.filterMode != .spotlight, let index = spotlightIndex {
                // Blur areas must always be UNDER spotlight's overlay in layer hierarchy
                layers.insert(filter, at: index)
            } else {
                layers.append(copy)
            }
            newSelection.insert(copy.id)
        }

        selectedLayerIDs = newSelection
        isModified = true
        computeElasticBounds()
        onNeedsDisplay?()
    }

    // MARK: - Undo / Redo

    /// Counts saveSnapshot calls, so a gesture can tell whether the latest snapshot is its own
    public private(set) var snapshotSerial = 0

    public func saveSnapshot() {
        snapshotSerial += 1
        let snapshot = layers.map { $0.clone() }
        undoStack.append(snapshot)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Pushes a snapshot captured earlier (e.g. before a callout editing session) as one undo step
    public func pushSnapshot(_ snapshot: [AnnotationLayer]) {
        undoStack.append(snapshot)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Drops the most recent snapshot when the gesture that saved it turned out to change nothing
    public func discardLastSnapshot() {
        _ = undoStack.popLast()
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(layers.map { $0.clone() })
        layers = previous
        selectedLayerIDs = selectedLayerIDs.intersection(Set(layers.map { $0.id }))
        isModified = true
        computeElasticBounds()
        onNeedsDisplay?()
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(layers.map { $0.clone() })
        layers = next
        selectedLayerIDs = selectedLayerIDs.intersection(Set(layers.map { $0.id }))
        isModified = true
        computeElasticBounds()
        onNeedsDisplay?()
    }

    // MARK: - Elastic Canvas Auto-Sizing (Section 4)

    public func computeElasticBounds() {
        // 1. Initialize computedBounds = originalImageBounds
        var computedMinX = originalImageBounds.minX
        var computedMinY = originalImageBounds.minY
        var computedMaxX = originalImageBounds.maxX
        var computedMaxY = originalImageBounds.maxY

        // 2. Iterate through all active layers. Get layerBounds = layer.getBoundingBox()
        for layer in layers where layer.isVisible {
            let layerBounds = layer.getBoundingBox()
            // 3. If layerBounds extends outside computedBounds: union + 10px strict padding
            if layerBounds.minX < computedMinX {
                computedMinX = layerBounds.minX - 10.0
            }
            if layerBounds.minY < computedMinY {
                computedMinY = layerBounds.minY - 10.0
            }
            if layerBounds.maxX > computedMaxX {
                computedMaxX = layerBounds.maxX + 10.0
            }
            if layerBounds.maxY > computedMaxY {
                computedMaxY = layerBounds.maxY + 10.0
            }
        }

        // 4. Original Integrity: never shrink smaller than exact original background dimensions
        computedMinX = min(computedMinX, originalImageBounds.minX)
        computedMinY = min(computedMinY, originalImageBounds.minY)
        computedMaxX = max(computedMaxX, originalImageBounds.maxX)
        computedMaxY = max(computedMaxY, originalImageBounds.maxY)

        let newBounds = CGRect(
            x: computedMinX,
            y: computedMinY,
            width: computedMaxX - computedMinX,
            height: computedMaxY - computedMinY
        )

        if newBounds != activeCanvasBounds {
            activeCanvasBounds = newBounds
            onBoundsChanged?(newBounds)
        }
    }

    // MARK: - Composition Rendering (Section 6)

    /// An independent copy (same image, cloned layers) that renders the composition as it is now
    public func compositionSnapshot() -> EditorDocument {
        let snapshot = EditorDocument(image: originalImage)
        snapshot.layers = layers.map { $0.clone() }
        return snapshot
    }

    public func renderComposition() -> CGImage? {
        computeElasticBounds()

        let width = Int(ceil(activeCanvasBounds.width))
        let height = Int(ceil(activeCanvasBounds.height))
        guard width > 0 && height > 0 else { return nil }

        // The image's own color space (a capture's display profile stays intact) and native BGRA layout,
        // so drawing the original is a plain copy rather than a per-pixel conversion
        let colorSpace = originalImage.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? Self.colorSpaceSRGB
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // 1. Clear active bounds to transparent
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        // Set up flipped coordinate system to match EditorCanvasView (isFlipped = true)
        // (0,0) at top-left, Y increasing downwards
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)

        // Shift origin if minX or minY are negative so activeCanvasBounds.origin is at (0, 0)
        let offsetX = -activeCanvasBounds.origin.x
        let offsetY = -activeCanvasBounds.origin.y
        context.translateBy(x: offsetX, y: offsetY)

        // 2. Draw originalImage right-side up in flipped context
        context.saveGState()
        context.translateBy(x: 0, y: originalImageBounds.height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(originalImage, in: CGRect(x: originalImageBounds.origin.x, y: 0, width: originalImageBounds.width, height: originalImageBounds.height))
        context.restoreGState()

        // 3a. Draw Blur / Pixelate Filter layers first (always UNDER spotlight overlay)
        for layer in layers where layer.isVisible {
            if let filterLayer = layer as? FilterLayer, filterLayer.filterMode != .spotlight {
                filterLayer.applyFilter(to: originalImage, canvasBounds: activeCanvasBounds, in: context)
            }
        }

        // 3b. Draw Spotlight overlay (always ON TOP of blur layers)
        for layer in layers where layer.isVisible {
            if let filterLayer = layer as? FilterLayer, filterLayer.filterMode == .spotlight {
                filterLayer.applyFilter(to: originalImage, canvasBounds: activeCanvasBounds, in: context)
            }
        }

        // 4. Sort AnnotationLayer array by zIndex
        let sorted = layers.filter { $0.isVisible }.sorted { $0.zIndex < $1.zIndex }

        // 5. Draw Vector Layers (Shapes, Arrows, Text)
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        for layer in sorted {
            layer.draw(in: context, scale: 1.0)
        }

        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()
    }
}
