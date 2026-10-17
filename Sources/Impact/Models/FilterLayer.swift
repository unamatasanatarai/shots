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
        didSet {
            _cachedBoundingBox = nil
            cachedSpotlightMask = nil
        }
    }

    public var rects: [CGRect] {
        didSet {
            _cachedBoundingBox = nil
            cachedSpotlightMask = nil
        }
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
        } else {
            context.setLineWidth(1.5)
            for (idx, r) in rects.enumerated() {
                guard r.width > 0 && r.height > 0 else { continue }
                if selectedRectIndex == idx {
                    let effectiveRadius = max(0.0, min(cornerRadius, min(r.width / 2.0, r.height / 2.0)))
                    let path = CGPath(roundedRect: r, cornerWidth: effectiveRadius, cornerHeight: effectiveRadius, transform: nil)
                    context.addPath(path)
                    context.setStrokeColor(NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 0.95).cgColor)
                    context.strokePath()
                }
            }
        }

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
    private var cachedSpotlightMask: (bounds: CGRect, rects: [CGRect], image: CGImage)?

    private struct FilterCacheKey: Hashable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let mode: FilterMode
        let intensity: Double

        init(rect: CGRect, mode: FilterMode, intensity: CGFloat) {
            self.x = Double(rect.origin.x)
            self.y = Double(rect.origin.y)
            self.width = Double(rect.size.width)
            self.height = Double(rect.size.height)
            self.mode = mode
            self.intensity = Double(intensity)
        }
    }
    private var filterCache: [FilterCacheKey: CGImage] = [:]

    // MARK: - Multi-Spotlight Masking Logic (Section 6)

    private static var scratchSpotlightContext: CGContext?
    private static var scratchContextWidth: Int = 0
    private static var scratchContextHeight: Int = 0
    private static let colorSpaceRGB = CGColorSpaceCreateDeviceRGB()
    private static let spotlightDarkMaskColor = CGColor(gray: 0.0, alpha: 0.50)
    private static let blurOutlineColor = CGColor(gray: 0.75, alpha: 0.35)

    private func drawSpotlightMask(canvasBounds: CGRect, in context: CGContext) {
        let width = Int(ceil(canvasBounds.width))
        let height = Int(ceil(canvasBounds.height))
        guard width > 0 && height > 0 else { return }

        let maskImage: CGImage
        if let cached = cachedSpotlightMask, cached.bounds == canvasBounds && cached.rects == rects {
            maskImage = cached.image
        } else {
            let maskContext: CGContext
            if let existing = Self.scratchSpotlightContext, Self.scratchContextWidth == width, Self.scratchContextHeight == height {
                maskContext = existing
                maskContext.setBlendMode(.copy)
                maskContext.setFillColor(Self.spotlightDarkMaskColor)
                maskContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
            } else {
                guard let newCtx = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: Self.colorSpaceRGB,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return }
                Self.scratchSpotlightContext = newCtx
                Self.scratchContextWidth = width
                Self.scratchContextHeight = height
                maskContext = newCtx
                maskContext.setFillColor(Self.spotlightDarkMaskColor)
                maskContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }

            // 2. Set blend mode to .clear to punch holes in flipped coordinates
            maskContext.setBlendMode(.clear)
            for r in rects {
                guard r.width > 0 && r.height > 0 else { continue }
                // Adjust to maskContext coordinates where (0,0) is bottom-left of canvasBounds
                let localY = canvasBounds.height - (r.origin.y - canvasBounds.origin.y) - r.height
                let localRect = CGRect(
                    x: r.origin.x - canvasBounds.origin.x,
                    y: localY,
                    width: r.width,
                    height: r.height
                )
                let effectiveRadius = max(0.0, min(cornerRadius, min(r.width / 2.0, r.height / 2.0)))
                let path = CGPath(roundedRect: localRect, cornerWidth: effectiveRadius, cornerHeight: effectiveRadius, transform: nil)
                maskContext.addPath(path)
                maskContext.fillPath()
            }

            guard let generated = maskContext.makeImage() else { return }
            cachedSpotlightMask = (bounds: canvasBounds, rects: rects, image: generated)
            maskImage = generated
        }

        // 3. Draw buffer back onto main context right-side up
        context.saveGState()
        context.translateBy(x: canvasBounds.origin.x, y: canvasBounds.origin.y + canvasBounds.height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(maskImage, in: CGRect(x: 0, y: 0, width: canvasBounds.width, height: canvasBounds.height))
        context.restoreGState()
    }

    // MARK: - Blur & Pixelate Filter

    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

    private func drawBlurOrPixelate(originalImage: CGImage, canvasBounds: CGRect, in context: CGContext) {
        let targetRects = isTextOnlyMode && !detectedTextRects.isEmpty ? detectedTextRects : rects
        guard !targetRects.isEmpty else { return }

        let imgW = CGFloat(originalImage.width)
        let imgH = CGFloat(originalImage.height)

        for rect in targetRects {
            let intersect = rect.intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
            guard intersect.width > 2 && intersect.height > 2 else { continue }

            // In CoreGraphics CGImage, row 0 is at the top (y=0).
            // In canvas coordinates, y=0 is also at the top of the image.
            // Therefore, the crop rect in originalImage maps 1:1 with intersect.
            let imageCropRect = intersect

            context.saveGState()

            let effectiveRadius = max(0.0, min(6.0, min(intersect.width / 2.0, intersect.height / 2.0)))
            let clipPath = CGPath(roundedRect: intersect, cornerWidth: effectiveRadius, cornerHeight: effectiveRadius, transform: nil)
            context.addPath(clipPath)
            context.clip()

            let cacheKey = FilterCacheKey(rect: intersect, mode: filterMode, intensity: intensity)
            if let cached = filterCache[cacheKey] {
                context.saveGState()
                context.translateBy(x: intersect.origin.x, y: intersect.origin.y + intersect.height)
                context.scaleBy(x: 1.0, y: -1.0)
                context.interpolationQuality = (filterMode == .pixelate) ? .none : .high
                context.draw(cached, in: CGRect(x: 0, y: 0, width: intersect.width, height: intersect.height))
                context.restoreGState()
            } else if filterMode == .pixelate {
                // Mosaic pixelation: downscale cropped region then upscale with nearest neighbor
                let factor = max(4.0, intensity)
                let lowW = max(1, Int(intersect.width / factor))
                let lowH = max(1, Int(intersect.height / factor))

                if let crop = originalImage.cropping(to: imageCropRect),
                   let lowCtx = CGContext(data: nil, width: lowW, height: lowH, bitsPerComponent: 8, bytesPerRow: lowW * 4, space: Self.colorSpaceRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    lowCtx.interpolationQuality = .none
                    lowCtx.draw(crop, in: CGRect(x: 0, y: 0, width: lowW, height: lowH))
                    if let pixelatedImage = lowCtx.makeImage() {
                        if filterCache.count > 50 { filterCache.removeAll(keepingCapacity: true) }
                        filterCache[cacheKey] = pixelatedImage
                        context.saveGState()
                        context.translateBy(x: intersect.origin.x, y: intersect.origin.y + intersect.height)
                        context.scaleBy(x: 1.0, y: -1.0)
                        context.interpolationQuality = .none
                        context.draw(pixelatedImage, in: CGRect(x: 0, y: 0, width: intersect.width, height: intersect.height))
                        context.restoreGState()
                    }
                }
            } else {
                // Gaussian blur using CoreImage with fallback
                if let crop = originalImage.cropping(to: imageCropRect) {
                    var rendered = false
                    let ciImage = CIImage(cgImage: crop).clampedToExtent()
                    if let blurFilter = CIFilter(name: "CIGaussianBlur") {
                        blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
                        blurFilter.setValue(max(2.0, intensity), forKey: kCIInputRadiusKey)
                        if let output = blurFilter.outputImage,
                           let blurredCG = FilterLayer.sharedCIContext.createCGImage(output, from: CGRect(x: 0, y: 0, width: intersect.width, height: intersect.height)) {
                            if filterCache.count > 50 { filterCache.removeAll(keepingCapacity: true) }
                            filterCache[cacheKey] = blurredCG
                            context.saveGState()
                            context.translateBy(x: intersect.origin.x, y: intersect.origin.y + intersect.height)
                            context.scaleBy(x: 1.0, y: -1.0)
                            context.interpolationQuality = .high
                            context.draw(blurredCG, in: CGRect(x: 0, y: 0, width: intersect.width, height: intersect.height))
                            context.restoreGState()
                            rendered = true
                        }
                    }

                    if !rendered {
                        // High-speed downscale/upscale blur fallback
                        let factor: CGFloat = 8.0
                        let lowW = max(1, Int(intersect.width / factor))
                        let lowH = max(1, Int(intersect.height / factor))
                        if let lowCtx = CGContext(data: nil, width: lowW, height: lowH, bitsPerComponent: 8, bytesPerRow: lowW * 4, space: Self.colorSpaceRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                            lowCtx.interpolationQuality = .low
                            lowCtx.draw(crop, in: CGRect(x: 0, y: 0, width: lowW, height: lowH))
                            if let lowImage = lowCtx.makeImage() {
                                if filterCache.count > 50 { filterCache.removeAll(keepingCapacity: true) }
                                filterCache[cacheKey] = lowImage
                                context.saveGState()
                                context.translateBy(x: intersect.origin.x, y: intersect.origin.y + intersect.height)
                                context.scaleBy(x: 1.0, y: -1.0)
                                context.interpolationQuality = .high
                                context.draw(lowImage, in: CGRect(x: 0, y: 0, width: intersect.width, height: intersect.height))
                                context.restoreGState()
                            }
                        }
                    }
                }
            }

            // Outline around blurred area
            context.setStrokeColor(Self.blurOutlineColor)
            context.setLineWidth(1.0)
            context.stroke(intersect)

            context.restoreGState()
        }
    }

    // MARK: - Vision OCR Text-Only Identification (Section 3)

    public func performVisionTextDetection(in image: CGImage, completion: @escaping () -> Void) {
        guard isTextOnlyMode else {
            completion()
            return
        }

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
                    if self.rects.contains(where: { $0.intersects(textRect) }) {
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

    public func clone() -> AnnotationLayer {
        let copy = FilterLayer(
            id: id,
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
