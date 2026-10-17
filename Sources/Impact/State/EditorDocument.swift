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
            }
        }
    }
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
        let overlay = FilterLayer(rects: [], filterMode: .spotlight)
        layers.insert(overlay, at: 0)
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
        layers.append(layer)
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
        if layer.type != .spotlight && layer.type != .blur {
            activeColor = layer.color
        }
        onNeedsDisplay?()
    }

    public func selectLayer(at point: CGPoint) -> AnnotationLayer? {
        // Reverse iterate to select top-most layer
        for layer in layers.reversed() {
            if layer.isVisible && layer.contains(point: point) {
                selectedLayerIDs = [layer.id]
                if layer.type != .spotlight && layer.type != .blur {
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

    // MARK: - Undo / Redo

    public func saveSnapshot() {
        let snapshot = layers.map { $0.clone() }
        undoStack.append(snapshot)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
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

    public func renderComposition() -> CGImage? {
        computeElasticBounds()

        let width = Int(ceil(activeCanvasBounds.width))
        let height = Int(ceil(activeCanvasBounds.height))
        guard width > 0 && height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: Self.colorSpaceRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
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

        // 3. Draw Destructive / Masking layers (Spotlight & Blur)
        for layer in layers where layer.isVisible {
            if let filterLayer = layer as? FilterLayer {
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
