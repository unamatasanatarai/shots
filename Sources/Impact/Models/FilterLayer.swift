import Foundation
import CoreGraphics
import AppKit
import Vision
import CoreImage

public final class FilterLayer: AnnotationLayer {
    public let id: UUID
    public var type: LayerType { filterMode == .spotlight ? .spotlight : .blur }
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String = "#FFFFFF"
    public var strokeWidth: CGFloat = 4.0 {
        didSet { _cachedBoundingBox = nil }
    }
    public var cornerRadius: CGFloat = 6.0 {
        didSet { _cachedBoundingBox = nil }
    }

    public var rects: [CGRect] {
        didSet { _cachedBoundingBox = nil }
    }
    public var filterMode: FilterMode // .gaussian, .pixelate, .spotlight
    public var intensity: CGFloat
    public var isTextOnlyMode: Bool = false // Vision OCR toggle
    public var detectedTextRects: [CGRect] = []
    public var selectedRectIndex: Int? = nil

    private var _cachedBoundingBox: CGRect?

    public init(
        id: UUID = UUID(),
        rects: [CGRect] = [],
        filterMode: FilterMode = .spotlight,
        intensity: CGFloat = 6.0,
        isTextOnlyMode: Bool = false,
        selectedRectIndex: Int? = nil,
        zIndex: Int = -10, // Destructive / Masking layers drawn under vector annotations
        color: String = "#FFFFFF",
        strokeWidth: CGFloat = 4.0,
        cornerRadius: CGFloat = 6.0
    ) {
        self.id = id
        self.rects = rects
        self.filterMode = filterMode
        self.intensity = intensity
        self.isTextOnlyMode = isTextOnlyMode
        self.selectedRectIndex = selectedRectIndex
        self.zIndex = zIndex
        self.color = color
        self.strokeWidth = strokeWidth
        self.cornerRadius = cornerRadius
    }

    public func getBoundingBox() -> CGRect {
        if let cached = _cachedBoundingBox { return cached }
        guard !rects.isEmpty else { return .zero }
        var union = rects[0]
        for r in rects.dropFirst() {
            union = union.union(r)
        }
        let padding = strokeWidth / 2.0 + 8.0
        let box = union.insetBy(dx: -padding, dy: -padding)
        _cachedBoundingBox = box
        return box
    }

    public func contains(point: CGPoint) -> Bool {
        guard getBoundingBox().contains(point) else { return false }
        return rectIndex(at: point) != nil
    }

    /// Returns the index of the rectangle whose boundary catchment area (10px) contains the point.
    /// The hollow center returns nil to prevent moving by grabbing the center.
    public func rectIndex(at point: CGPoint) -> Int? {
        let catchment: CGFloat = max(10.0, strokeWidth + 6.0)
        for (idx, r) in rects.enumerated().reversed() {
            let outer = r.standardized.insetBy(dx: -catchment, dy: -catchment)
            let inner = r.standardized.insetBy(dx: catchment, dy: catchment)
            if inner.width <= 0 || inner.height <= 0 {
                if outer.contains(point) { return idx }
            } else {
                if outer.contains(point) && !inner.contains(point) {
                    return idx
                }
            }
        }
        return nil
    }

    /// 8 handle points per rectangle (matching RectangleLayer rules)
    public func getHandlePoints() -> [CGPoint] {
        var points: [CGPoint] = []
        for r in rects {
            let minX = r.minX, midX = r.midX, maxX = r.maxX
            let minY = r.minY, midY = r.midY, maxY = r.maxY
            points.append(CGPoint(x: minX, y: minY)) // 0: Top-Left
            points.append(CGPoint(x: midX, y: minY)) // 1: Top-Center
            points.append(CGPoint(x: maxX, y: minY)) // 2: Top-Right
            points.append(CGPoint(x: maxX, y: midY)) // 3: Mid-Right
            points.append(CGPoint(x: maxX, y: maxY)) // 4: Bottom-Right
            points.append(CGPoint(x: midX, y: maxY)) // 5: Bottom-Center
            points.append(CGPoint(x: minX, y: maxY)) // 6: Bottom-Left
            points.append(CGPoint(x: minX, y: midY))  // 7: Mid-Left
        }
        return points
    }

    public func getHandlePointsForSelected() -> [CGPoint] {
        if let idx = selectedRectIndex, idx >= 0 && idx < rects.count {
            let r = rects[idx]
            let minX = r.minX, midX = r.midX, maxX = r.maxX
            let minY = r.minY, midY = r.midY, maxY = r.maxY
            return [
                CGPoint(x: minX, y: minY), // 0: Top-Left
                CGPoint(x: midX, y: minY), // 1: Top-Center
                CGPoint(x: maxX, y: minY), // 2: Top-Right
                CGPoint(x: maxX, y: midY), // 3: Mid-Right
                CGPoint(x: maxX, y: maxY), // 4: Bottom-Right
                CGPoint(x: midX, y: maxY), // 5: Bottom-Center
                CGPoint(x: minX, y: maxY), // 6: Bottom-Left
                CGPoint(x: minX, y: midY)  // 7: Mid-Left
            ]
        }
        return getHandlePoints()
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        guard getBoundingBox().insetBy(dx: -12, dy: -12).contains(point) else { return nil }
        let handles = getHandlePoints()
        let hitRadius = max(radius, 10.0)
        let hitRadiusSq = hitRadius * hitRadius
        for (i, hp) in handles.enumerated() {
            let dx = point.x - hp.x
            let dy = point.y - hp.y
            if dx * dx + dy * dy <= hitRadiusSq {
                selectedRectIndex = i / 8
                return i
            }
        }
        return nil
    }

    public func move(by delta: CGPoint) {
        let idx = selectedRectIndex ?? (rects.count - 1)
        if idx >= 0 && idx < rects.count {
            rects[idx].origin.x += delta.x
            rects[idx].origin.y += delta.y
        } else {
            for i in 0..<rects.count {
                rects[i].origin.x += delta.x
                rects[i].origin.y += delta.y
            }
        }
        _cachedBoundingBox = nil
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        let handlesPerRect = 8
        let rectIndex = index / handlesPerRect
        let subIndex = index % handlesPerRect
        guard rectIndex < rects.count else { return }

        let initRect = rects[rectIndex]

        let oppX: CGFloat
        let oppY: CGFloat
        switch subIndex {
        case 0, 1: oppX = initRect.maxX; oppY = initRect.maxY
        case 2, 3: oppX = initRect.minX; oppY = initRect.maxY
        case 4, 5: oppX = initRect.minX; oppY = initRect.minY
        case 6, 7: oppX = initRect.maxX; oppY = initRect.minY
        default: oppX = initRect.maxX; oppY = initRect.maxY
        }

        switch subIndex {
        case 1, 5:
            let newY = min(point.y, oppY)
            let newH = max(4.0, abs(point.y - oppY))
            rects[rectIndex] = CGRect(x: initRect.minX, y: newY, width: initRect.width, height: newH)
        case 3, 7:
            let newX = min(point.x, oppX)
            let newW = max(4.0, abs(point.x - oppX))
            rects[rectIndex] = CGRect(x: newX, y: initRect.minY, width: newW, height: initRect.height)
        default:
            let newX = min(point.x, oppX)
            let newW = max(4.0, abs(point.x - oppX))
            let newY = min(point.y, oppY)
            let newH = max(4.0, abs(point.y - oppY))
            rects[rectIndex] = CGRect(x: newX, y: newY, width: newW, height: newH)
        }
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        context.saveGState()

        if filterMode == .spotlight {
            // Subtle natural shadow for depth and crispness matching RectangleLayer
            context.setShadow(offset: CGSize(width: 0, height: -1.0), blur: 2.5, color: NSColor.black.withAlphaComponent(0.25).cgColor)
            let strokeCGColor = FastColor.shared.cgColor(hex: color.isEmpty ? "#FFFFFF" : color)
            context.setStrokeColor(strokeCGColor)
            context.setLineWidth(strokeWidth)

            for r in rects {
                guard r.width > 0 && r.height > 0 else { continue }
                let effectiveRadius = max(0.0, min(cornerRadius, min(r.width / 2.0, r.height / 2.0)))
                let path = CGPath(roundedRect: r, cornerWidth: effectiveRadius, cornerHeight: effectiveRadius, transform: nil)
                context.addPath(path)
                context.strokePath()
            }
        }
        // Blur and pixelate filters have zero outline. Never outline.

        context.restoreGState()
    }

    public func applyFilter(to originalImage: CGImage, canvasBounds: CGRect, in context: CGContext) {
        switch filterMode {
        case .spotlight:
            drawSpotlightMask(canvasBounds: canvasBounds, in: context)

        case .gaussian, .pixelate:
            drawBlurOrPixelate(originalImage: originalImage, canvasBounds: canvasBounds, in: context)
        }
    }

    // MARK: - Performance Caching

    /// A filtered image of `rect` (in image coordinates). Rects are filtered with a margin, so nudging or
    /// slightly resizing an area reuses the cached result instead of re-running the filter.
    private struct FilterCacheEntry {
        let rect: CGRect
        let mode: FilterMode
        let intensity: CGFloat
        let image: CGImage
    }
    private var filterCache: [FilterCacheEntry] = []
    private static let filterCacheLimit = 8

    private static let colorSpaceSRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let spotlightDarkMaskColor = CGColor(gray: 0.0, alpha: 0.50)

    // MARK: - Multi-Spotlight Masking Logic (Section 6)

    /// Darkens the canvas outside the spotlight holes. Drawn as a path: no canvas-sized mask bitmap.
    private func drawSpotlightMask(canvasBounds: CGRect, in context: CGContext) {
        guard canvasBounds.width > 0 && canvasBounds.height > 0 else { return }
        let holes: [CGPath] = rects.compactMap { r in
            guard r.width > 0 && r.height > 0 else { return nil }
            let effectiveRadius = max(0.0, min(cornerRadius, min(r.width / 2.0, r.height / 2.0)))
            return CGPath(roundedRect: r, cornerWidth: effectiveRadius, cornerHeight: effectiveRadius, transform: nil)
        }

        context.saveGState()
        context.setFillColor(Self.spotlightDarkMaskColor)
        if Self.hasOverlap(rects) {
            // Even-odd would re-darken where holes overlap: punch the holes out of a transparency layer instead
            context.beginTransparencyLayer(in: canvasBounds, auxiliaryInfo: nil)
            context.fill(canvasBounds)
            context.setBlendMode(.clear)
            for hole in holes {
                context.addPath(hole)
            }
            context.fillPath()
            context.endTransparencyLayer()
        } else {
            let path = CGMutablePath()
            path.addRect(canvasBounds)
            for hole in holes {
                path.addPath(hole)
            }
            context.addPath(path)
            context.fillPath(using: .evenOdd)
        }
        context.restoreGState()
    }

    private static func hasOverlap(_ rects: [CGRect]) -> Bool {
        guard rects.count > 1 else { return false }
        for i in 0..<(rects.count - 1) {
            for j in (i + 1)..<rects.count where rects[i].intersects(rects[j]) {
                return true
            }
        }
        return false
    }

    // MARK: - Blur & Pixelate Filter

    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

    /// Releases Core Image's GPU caches (when the editor closes)
    public static func clearSharedCaches() {
        sharedCIContext.clearCaches()
    }

    private func drawBlurOrPixelate(originalImage: CGImage, canvasBounds: CGRect, in context: CGContext) {
        let targetRects = isTextOnlyMode && !detectedTextRects.isEmpty ? detectedTextRects : rects
        guard !targetRects.isEmpty else { return }

        let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(originalImage.width), height: CGFloat(originalImage.height))

        for rect in targetRects {
            let intersect = rect.intersection(imageBounds)
            guard intersect.width > 2 && intersect.height > 2 else { continue }
            guard let entry = filteredImage(covering: intersect, of: originalImage, imageBounds: imageBounds) else { continue }

            context.saveGState()

            let effectiveRadius = max(0.0, min(6.0, min(intersect.width / 2.0, intersect.height / 2.0)))
            let clipPath = CGPath(roundedRect: intersect, cornerWidth: effectiveRadius, cornerHeight: effectiveRadius, transform: nil)
            context.addPath(clipPath)
            context.clip()

            // In CoreGraphics CGImage, row 0 is at the top (y=0), as in canvas coordinates:
            // the cached rect maps 1:1 onto the canvas. Draw it right-side up in the flipped context.
            context.translateBy(x: entry.rect.origin.x, y: entry.rect.origin.y + entry.rect.height)
            context.scaleBy(x: 1.0, y: -1.0)
            context.interpolationQuality = (filterMode == .pixelate) ? .none : .high
            context.draw(entry.image, in: CGRect(x: 0, y: 0, width: entry.rect.width, height: entry.rect.height))

            // Blur tool has zero outline. Never outline.

            context.restoreGState()
        }
    }

    /// Returns a cached filtered image whose rect contains `area`, filtering a padded rect on a miss
    private func filteredImage(covering area: CGRect, of originalImage: CGImage, imageBounds: CGRect) -> FilterCacheEntry? {
        if let hit = filterCache.lastIndex(where: { $0.mode == filterMode && $0.intensity == intensity && $0.rect.contains(area) }) {
            let entry = filterCache.remove(at: hit)
            filterCache.append(entry)
            return entry
        }

        let margin = max(32.0, min(area.width, area.height) * 0.15)
        let padded = area.insetBy(dx: -margin, dy: -margin).intersection(imageBounds).integral.intersection(imageBounds)
        guard padded.width >= 1, padded.height >= 1, let crop = originalImage.cropping(to: padded) else { return nil }
        let colorSpace = originalImage.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? Self.colorSpaceSRGB

        let filtered: CGImage?
        if filterMode == .pixelate {
            // Mosaic pixelation: downscale cropped region then upscale with nearest neighbor
            let factor = max(4.0, intensity)
            filtered = Self.downscale(crop, width: max(1, Int(padded.width / factor)), height: max(1, Int(padded.height / factor)), colorSpace: colorSpace, quality: .none)
        } else {
            // Gaussian blur using CoreImage, with a downscale/upscale fallback
            let ciImage = CIImage(cgImage: crop).clampedToExtent()
            if let blurFilter = CIFilter(name: "CIGaussianBlur") {
                blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
                blurFilter.setValue(max(2.0, intensity), forKey: kCIInputRadiusKey)
                filtered = blurFilter.outputImage.flatMap {
                    Self.sharedCIContext.createCGImage($0, from: CGRect(x: 0, y: 0, width: padded.width, height: padded.height))
                } ?? Self.downscale(crop, width: max(1, Int(padded.width / 8.0)), height: max(1, Int(padded.height / 8.0)), colorSpace: colorSpace, quality: .low)
            } else {
                filtered = Self.downscale(crop, width: max(1, Int(padded.width / 8.0)), height: max(1, Int(padded.height / 8.0)), colorSpace: colorSpace, quality: .low)
            }
        }
        guard let image = filtered else { return nil }

        let entry = FilterCacheEntry(rect: padded, mode: filterMode, intensity: intensity, image: image)
        if filterCache.count >= Self.filterCacheLimit { filterCache.removeFirst() }
        filterCache.append(entry)
        return entry
    }

    private static func downscale(_ image: CGImage, width: Int, height: Int, colorSpace: CGColorSpace, quality: CGInterpolationQuality) -> CGImage? {
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.interpolationQuality = quality
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    // MARK: - Vision OCR Text-Only Identification (Section 3)

    public func performVisionTextDetection(in image: CGImage, completion: @escaping () -> Void) {
        guard isTextOnlyMode else {
            completion()
            return
        }

        // Read on the calling (main) thread: the rects may change while recognition runs
        let areaRects = rects
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                    DispatchQueue.main.async { completion() }
                    return
                }

                let imgW = CGFloat(image.width)
                let imgH = CGFloat(image.height)
                var detected: [CGRect] = []

                for obs in observations {
                    let box = obs.boundingBox
                    // Convert normalized bottom-left coordinates to image pixels
                    let textRect = CGRect(
                        x: box.minX * imgW,
                        y: (1.0 - box.maxY) * imgH,
                        width: box.width * imgW,
                        height: box.height * imgH
                    )
                    // Check if inside any of our filter rectangles
                    if areaRects.contains(where: { $0.intersects(textRect) }) {
                        detected.append(textRect)
                    }
                }

                DispatchQueue.main.async {
                    self.detectedTextRects = detected
                    completion()
                }
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([request])
        }
    }

    public func clone(withID newID: UUID) -> AnnotationLayer {
        let copy = FilterLayer(
            id: newID,
            rects: rects,
            filterMode: filterMode,
            intensity: intensity,
            isTextOnlyMode: isTextOnlyMode,
            selectedRectIndex: selectedRectIndex,
            zIndex: zIndex,
            color: color,
            strokeWidth: strokeWidth,
            cornerRadius: cornerRadius
        )
        copy.detectedTextRects = detectedTextRects
        return copy
    }
}
