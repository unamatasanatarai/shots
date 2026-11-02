import Foundation
import CoreGraphics
import AppKit

public final class EditorDocument {
    /// The base image. A crop replaces it (undo restores the previous one).
    public private(set) var originalImage: CGImage
    public private(set) var originalImageBounds: CGRect
    public private(set) var activeCanvasBounds: CGRect

    public var layers: [AnnotationLayer] = [] {
        didSet { cachedTopToBottom = nil }
    }
    /// Draw order cache for hit testing (several lookups per mouse move); rebuilt when `layers` changes.
    /// zIndex/visibility only change on layers before they're inserted, which also resets it.
    private var cachedTopToBottom: [AnnotationLayer]?
    public var isModified: Bool = false

    /// Changes with every edit, undo and redo (and back when a no-op press's snapshot is discarded):
    /// a saved file is current while this matches the value recorded at save time
    public private(set) var editSerial = 0

    /// The image the editor opened with (a crop replaces originalImage; undoing it restores this object)
    private let openedImage: CGImage

    /// Whether there is anything worth saving: an annotation, or a crop. Undoing everything returns to false.
    public var hasContent: Bool {
        originalImage !== openedImage || layers.contains { layer in
            if let filter = layer as? FilterLayer { return !filter.rects.isEmpty }
            return true
        }
    }
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
    private struct Snapshot {
        let layers: [AnnotationLayer]
        let image: CGImage
    }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    private func currentSnapshot() -> Snapshot {
        Snapshot(layers: Self.historyLayers(layers), image: originalImage)
    }

    /// Clones for the undo history, without the empty spotlight overlay the spotlight tool adds while it is
    /// active: restored outside that tool it would dim the whole canvas with no hole and nothing to select
    private static func historyLayers(_ layers: [AnnotationLayer]) -> [AnnotationLayer] {
        layers.compactMap { layer in
            if let filter = layer as? FilterLayer, filter.filterMode == .spotlight, filter.rects.isEmpty { return nil }
            return layer.clone()
        }
    }

    private func restore(_ snapshot: Snapshot) {
        layers = snapshot.layers
        if snapshot.image !== originalImage {
            replaceImage(snapshot.image)
        }
        if activeTool == .spotlight {
            ensureSpotlightOverlay() // the tool's working overlay
        }
        selectedLayerIDs = selectedLayerIDs.intersection(Set(layers.map { $0.id }))
        isModified = true
        computeElasticBounds()
        onNeedsDisplay?()
    }

    public var onBoundsChanged: ((CGRect) -> Void)?
    /// Fires when a crop (or undoing one) replaces the base image
    public var onImageChanged: ((CGImage) -> Void)?
    public var onNeedsDisplay: (() -> Void)?

    public init(image: CGImage) {
        self.originalImage = image
        self.openedImage = image
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
        if let layer = topLayer(at: point) {
            selectedLayerIDs = [layer.id]
            if layer.type != .blur {
                activeColor = layer.color
            }
            onNeedsDisplay?()
            return layer
        }
        selectedLayerIDs.removeAll()
        onNeedsDisplay?()
        return nil
    }

    /// Visible layers from top to bottom as drawn: vector layers by zIndex (later wins ties), then the
    /// spotlight overlay, then blur areas. Hit testing must follow this, not array order, or an invisible
    /// blur edge added later wins clicks on an arrow drawn above it.
    public func layersTopToBottom() -> [AnnotationLayer] {
        if let cached = cachedTopToBottom { return cached }
        let order = computeTopToBottom()
        cachedTopToBottom = order
        return order
    }

    private func computeTopToBottom() -> [AnnotationLayer] {
        let visible = layers.enumerated().filter { $0.element.isVisible }
        let vectors = visible.filter { !($0.element is FilterLayer) }
            .sorted { $0.element.zIndex != $1.element.zIndex ? $0.element.zIndex > $1.element.zIndex : $0.offset > $1.offset }
        let spotlights = visible.filter { ($0.element as? FilterLayer)?.filterMode == .spotlight }.reversed()
        let blurs = visible.filter { ($0.element as? FilterLayer).map { $0.filterMode != .spotlight } ?? false }.reversed()
        return (vectors + spotlights + blurs).map { $0.element }
    }

    /// The topmost visible layer whose body contains `point`
    public func topLayer(at point: CGPoint) -> AnnotationLayer? {
        layersTopToBottom().first { $0.contains(point: point) }
    }

    /// The topmost visible layer with a handle at `point`, and that handle's index
    public func topHandle(at point: CGPoint) -> (layer: AnnotationLayer, index: Int)? {
        for layer in layersTopToBottom() {
            if let index = layer.hitTestHandle(point: point) { return (layer, index) }
        }
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
                filter.detectedTextRects = filter.detectedTextRects.map { $0.offsetBy(dx: offset.x, dy: offset.y) }
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

    /// The redo history the latest saveSnapshot cleared, so discarding that snapshot (a press that changed
    /// nothing) can put it back: a plain click must not throw away redo
    private var redoBeforeLastSnapshot: [Snapshot]?

    public func saveSnapshot() {
        snapshotSerial += 1
        editSerial += 1
        undoStack.append(currentSnapshot())
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoBeforeLastSnapshot = redoStack
        redoStack.removeAll()
    }

    /// Pushes a snapshot captured earlier (e.g. before a callout editing session) as one undo step
    public func pushSnapshot(_ snapshot: [AnnotationLayer]) {
        undoStack.append(Snapshot(layers: Self.historyLayers(snapshot), image: originalImage))
        redoBeforeLastSnapshot = nil
        editSerial += 1
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Drops the most recent snapshot when the gesture that saved it turned out to change nothing
    public func discardLastSnapshot() {
        guard undoStack.popLast() != nil else { return }
        editSerial -= 1
        if let redo = redoBeforeLastSnapshot {
            redoStack = redo
        }
        redoBeforeLastSnapshot = nil
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoBeforeLastSnapshot = nil
        editSerial += 1
        redoStack.append(currentSnapshot())
        restore(previous)
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        redoBeforeLastSnapshot = nil
        editSerial += 1
        undoStack.append(currentSnapshot())
        restore(next)
    }

    // MARK: - Crop

    /// Smallest crop, in canvas points, on either side
    public static let minimumCropSize: CGFloat = 4.0

    /// The rect a crop to `rect` would produce: snapped to whole pixels and kept inside the current canvas.
    /// Nil when too small.
    public func normalizedCropRect(_ rect: CGRect) -> CGRect? {
        let clipped = rect.standardized.intersection(activeCanvasBounds)
        guard !clipped.isNull else { return nil }
        // Edges land on whole image pixels (the image sits at 0,0) and never past the canvas, which can
        // itself end mid-pixel after elastic growth: a fractional crop would resample the whole image
        let canvas = activeCanvasBounds
        func snap(_ v: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
            let r = v.rounded()
            return r < low ? low.rounded(.up) : (r > high ? high.rounded(.down) : r)
        }
        let minX = snap(clipped.minX, low: canvas.minX, high: canvas.maxX)
        let maxX = snap(clipped.maxX, low: canvas.minX, high: canvas.maxX)
        let minY = snap(clipped.minY, low: canvas.minY, high: canvas.maxY)
        let maxY = snap(clipped.maxY, low: canvas.minY, high: canvas.maxY)
        guard maxX - minX >= Self.minimumCropSize, maxY - minY >= Self.minimumCropSize else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Crops to `rect` (canvas coordinates) as one undo step. The result behaves exactly like a newly opened
    /// image: the selected pixels become the image (areas past the old image edge stay transparent) and
    /// annotations shift with it, so the canvas grows elastically again when something extends past the edge.
    /// Annotations with no visible pixel inside are removed (a shadow or hit margin reaching in does not count);
    /// blur and spotlight areas are trimmed to the crop; other annotations crossing the edge are kept whole,
    /// and the canvas grows to fit them.
    @discardableResult
    public func crop(to rect: CGRect) -> Bool {
        guard let frame = normalizedCropRect(rect), frame != activeCanvasBounds,
              let cropped = Self.image(originalImage, croppedTo: frame) else { return false }
        saveSnapshot()

        let shift = CGPoint(x: -frame.minX, y: -frame.minY)
        layers.removeAll { layer in
            if let filter = layer as? FilterLayer {
                // A spotlight's border is centered on its rect: trim it inside the frame so the border stays whole
                let limit = filter.filterMode == .spotlight ? frame.insetBy(dx: filter.strokeWidth / 2.0, dy: filter.strokeWidth / 2.0) : frame
                filter.rects = filter.rects.compactMap { r in
                    let kept = r.standardized.intersection(limit)
                    return kept.isNull || kept.width < 1 || kept.height < 1 ? nil : kept.offsetBy(dx: shift.x, dy: shift.y)
                }
                filter.detectedTextRects = filter.detectedTextRects.compactMap { r in
                    let kept = r.intersection(frame)
                    return kept.isNull ? nil : kept.offsetBy(dx: shift.x, dy: shift.y)
                }
                if let idx = filter.selectedRectIndex, idx >= filter.rects.count {
                    filter.selectedRectIndex = filter.rects.isEmpty ? nil : filter.rects.count - 1
                }
                return filter.rects.isEmpty
            }
            guard Self.layer(layer, visiblyIntersects: frame) else { return true }
            layer.move(by: shift)
            return false
        }
        selectedLayerIDs = selectedLayerIDs.intersection(Set(layers.map { $0.id }))

        replaceImage(cropped)
        isModified = true
        computeElasticBounds()
        onNeedsDisplay?()
        return true
    }

    /// Whether `layer` paints a clearly visible pixel inside `frame`. Bounding boxes include shadows, arrowhead
    /// slack and hit margins, so they report overlap for annotations that sit visibly outside. Threshold ~31%:
    /// above every drop shadow (25% black) and below the faintest stroke (the 40% highlighter).
    static func layer(_ layer: AnnotationLayer, visiblyIntersects frame: CGRect) -> Bool {
        let region = layer.getBoundingBox().intersection(frame).integral
        guard !region.isNull, region.width >= 1, region.height >= 1 else { return false }
        let width = Int(region.width), height = Int(region.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpaceRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return true } // can't tell: keep it
        // Same flipped canvas coordinates the layers draw in
        context.translateBy(x: 0, y: region.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -region.minX, y: -region.minY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        layer.draw(in: context, scale: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for i in stride(from: 3, to: width * height * 4, by: 4) where bytes[i] >= 80 {
            return true
        }
        return false
    }

    /// The pixels of `frame` (top-left image coordinates); parts outside the image are transparent
    static func image(_ image: CGImage, croppedTo frame: CGRect) -> CGImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        // Always copied into its own buffer: CGImage.cropping(to:) shares the parent's pixels, which would
        // keep the full original alive for the document's lifetime, even after undo history drops it
        let width = Int(frame.width), height = Int(frame.height)
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? colorSpaceSRGB
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // CGContext is bottom-left: the image's top edge sits at (frame.minY) below the crop's top edge
        context.draw(image, in: CGRect(x: -frame.minX, y: frame.maxY - imageBounds.height, width: imageBounds.width, height: imageBounds.height))
        return context.makeImage()
    }

    private func replaceImage(_ image: CGImage) {
        originalImage = image
        originalImageBounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        for case let filter as FilterLayer in layers {
            filter.dropCachedFilters(notFrom: image)
        }
        onImageChanged?(image)
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
            if let ruler = layer as? DimensionLayer { ruler.labelBounds = originalImageBounds }
            // Blur/spotlight areas count by their own rects, not the padded hit box: an area reaching the
            // image edge (e.g. trimmed by a crop) must not grow the canvas
            let layerBounds: CGRect
            if let filter = layer as? FilterLayer {
                guard let first = filter.rects.first else { continue }
                let union = filter.rects.dropFirst().reduce(first.standardized) { $0.union($1.standardized) }
                // A spotlight's border straddles its rect; blur has no outline
                let border = filter.filterMode == .spotlight ? filter.strokeWidth / 2.0 : 0.0
                layerBounds = union.insetBy(dx: -border, dy: -border)
            } else {
                layerBounds = layer.getBoundingBox()
            }
            // 3. Union of everything that reaches past the image (padded once below)
            computedMinX = min(computedMinX, layerBounds.minX)
            computedMinY = min(computedMinY, layerBounds.minY)
            computedMaxX = max(computedMaxX, layerBounds.maxX)
            computedMaxY = max(computedMaxY, layerBounds.maxY)
        }

        // 10 pt of room past the outermost annotation, on whole pixels: a fractional origin would draw
        // (and export) the screenshot at a sub-pixel offset, resampling every pixel
        let image = originalImageBounds
        if computedMinX < image.minX { computedMinX = (computedMinX - 10.0).rounded(.down) }
        if computedMinY < image.minY { computedMinY = (computedMinY - 10.0).rounded(.down) }
        if computedMaxX > image.maxX { computedMaxX = (computedMaxX + 10.0).rounded(.up) }
        if computedMaxY > image.maxY { computedMaxY = (computedMaxY + 10.0).rounded(.up) }

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
        // The NSGraphicsContext below is autoreleased and holds the full-size bitmap: drain it here so repeated
        // exports don't stack canvas-sized buffers until the caller's pool drains
        autoreleasepool { renderCompositionImage() }
    }

    private func renderCompositionImage() -> CGImage? {
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
