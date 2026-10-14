import Foundation
import CoreGraphics
import AppKit
import Vision

public final class FilterLayer: AnnotationLayer {
    public let id: UUID
    public var type: LayerType { filterMode == .spotlight ? .spotlight : .blur }
    public var zIndex: Int
    public var isVisible: Bool = true
    public var color: String = "#000000"
    public var strokeWidth: CGFloat = 2.0

    public var rects: [CGRect]
    public var filterMode: FilterMode // .gaussian, .pixelate, .spotlight
    public var intensity: CGFloat
    public var isTextOnlyMode: Bool = false // Vision OCR toggle
    public var detectedTextRects: [CGRect] = []

    public init(
        id: UUID = UUID(),
        rects: [CGRect] = [],
        filterMode: FilterMode = .spotlight,
        intensity: CGFloat = 16.0,
        isTextOnlyMode: Bool = false,
        zIndex: Int = -10 // Destructive / Masking layers drawn under vector annotations
    ) {
        self.id = id
        self.rects = rects
        self.filterMode = filterMode
        self.intensity = intensity
        self.isTextOnlyMode = isTextOnlyMode
        self.zIndex = zIndex
    }

    public func getBoundingBox() -> CGRect {
        guard !rects.isEmpty else { return .zero }
        var union = rects[0]
        for r in rects.dropFirst() {
            union = union.union(r)
        }
        return union.insetBy(dx: -4, dy: -4)
    }

    public func contains(point: CGPoint) -> Bool {
        return rects.contains { $0.contains(point) }
    }

    public func hitTestHandle(point: CGPoint, radius: CGFloat = 8.0) -> Int? {
        guard let first = rects.first else { return nil }
        let handles = [
            CGPoint(x: first.minX, y: first.minY),
            CGPoint(x: first.maxX, y: first.minY),
            CGPoint(x: first.maxX, y: first.maxY),
            CGPoint(x: first.minX, y: first.maxY)
        ]
        for (i, hp) in handles.enumerated() {
            if hypot(point.x - hp.x, point.y - hp.y) <= radius { return i }
        }
        return nil
    }

    public func move(by delta: CGPoint) {
        for i in 0..<rects.count {
            rects[i].origin.x += delta.x
            rects[i].origin.y += delta.y
        }
    }

    public func updateHandle(index: Int, to point: CGPoint) {
        guard !rects.isEmpty else { return }
        var minX = rects[0].minX
        var maxX = rects[0].maxX
        var minY = rects[0].minY
        var maxY = rects[0].maxY

        switch index {
        case 0: minX = point.x; minY = point.y
        case 1: maxX = point.x; minY = point.y
        case 2: maxX = point.x; maxY = point.y
        case 3: minX = point.x; maxY = point.y
        default: break
        }

        rects[0] = CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: max(abs(maxX - minX), 4.0),
            height: max(abs(maxY - minY), 4.0)
        )
    }

    public func draw(in context: CGContext, scale: CGFloat) {
        // Spotlight masking and blur filtering are coordinated by the canvas rendering pipeline
        // to access the original backing bitmap and offscreen mask buffers.
        // For standalone drawing (or vector preview overlays):
        if filterMode == .spotlight {
            context.saveGState()
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            context.setLineWidth(1.5)
            for r in rects {
                context.stroke(r)
            }
            context.restoreGState()
        }
    }

    public func applyFilter(to originalImage: CGImage, canvasBounds: CGRect, in context: CGContext) {
        switch filterMode {
        case .spotlight:
            drawSpotlightMask(canvasBounds: canvasBounds, in: context)

        case .gaussian, .pixelate:
            drawBlurOrPixelate(originalImage: originalImage, canvasBounds: canvasBounds, in: context)
        }
    }

    // MARK: - Multi-Spotlight Masking Logic (Section 6)

    private func drawSpotlightMask(canvasBounds: CGRect, in context: CGContext) {
        guard !rects.isEmpty else { return }

        let width = Int(ceil(canvasBounds.width))
        let height = Int(ceil(canvasBounds.height))
        guard width > 0 && height > 0 else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let maskContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        // 1. Fill offscreen buffer with black at alpha: 0.45
        maskContext.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
        maskContext.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // 2. Set blend mode to .clear to punch holes in flipped coordinates
        maskContext.setBlendMode(.clear)
        for r in rects {
            // Adjust to maskContext coordinates where (0,0) is bottom-left of canvasBounds
            let localY = canvasBounds.height - (r.origin.y - canvasBounds.origin.y) - r.height
            let localRect = CGRect(
                x: r.origin.x - canvasBounds.origin.x,
                y: localY,
                width: r.width,
                height: r.height
            )
            let path = CGPath(roundedRect: localRect, cornerWidth: 8.0, cornerHeight: 8.0, transform: nil)
            maskContext.addPath(path)
            maskContext.fillPath()
        }

        // 3. Draw buffer back onto main context right-side up
        if let maskImage = maskContext.makeImage() {
            context.saveGState()
            context.translateBy(x: canvasBounds.origin.x, y: canvasBounds.origin.y + canvasBounds.height)
            context.scaleBy(x: 1.0, y: -1.0)
            context.draw(maskImage, in: CGRect(x: 0, y: 0, width: canvasBounds.width, height: canvasBounds.height))
            context.restoreGState()
        }
    }

    // MARK: - Blur & Pixelate Filter

    private func drawBlurOrPixelate(originalImage: CGImage, canvasBounds: CGRect, in context: CGContext) {
        let targetRects = isTextOnlyMode && !detectedTextRects.isEmpty ? detectedTextRects : rects
        guard !targetRects.isEmpty else { return }

        let imgW = CGFloat(originalImage.width)
        let imgH = CGFloat(originalImage.height)

        for rect in targetRects {
            let intersect = rect.intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
            guard intersect.width > 2 && intersect.height > 2 else { continue }

            // Since originalImage's CGImage internal coordinate system is unflipped (y=0 at bottom),
            // the crop rect corresponding to canvas coordinate (intersect) has y = imgH - intersect.maxY
            let cropY = imgH - intersect.maxY
            let imageCropRect = CGRect(x: intersect.origin.x, y: cropY, width: intersect.width, height: intersect.height)

            context.saveGState()
            context.clip(to: intersect)

            if filterMode == .pixelate {
                // Mosaic pixelation: downscale cropped region then upscale with nearest neighbor
                let factor = max(4.0, intensity)
                let lowW = max(1, Int(intersect.width / factor))
                let lowH = max(1, Int(intersect.height / factor))
                let colorSpace = CGColorSpaceCreateDeviceRGB()

                if let crop = originalImage.cropping(to: imageCropRect),
                   let lowCtx = CGContext(data: nil, width: lowW, height: lowH, bitsPerComponent: 8, bytesPerRow: lowW * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    lowCtx.interpolationQuality = .none
                    lowCtx.draw(crop, in: CGRect(x: 0, y: 0, width: lowW, height: lowH))
                    if let pixelatedImage = lowCtx.makeImage() {
                        context.saveGState()
                        context.translateBy(x: intersect.origin.x, y: intersect.origin.y + intersect.height)
                        context.scaleBy(x: 1.0, y: -1.0)
                        context.interpolationQuality = .none
                        context.draw(pixelatedImage, in: CGRect(x: 0, y: 0, width: intersect.width, height: intersect.height))
                        context.restoreGState()
                    }
                }
            } else {
                // Gaussian blur / translucent frosted overlay
                context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 0.85))
                context.fill(intersect)

                // Mosaic pattern overlay for privacy
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let crop = originalImage.cropping(to: imageCropRect) {
                    let factor: CGFloat = 8.0
                    let lowW = max(1, Int(intersect.width / factor))
                    let lowH = max(1, Int(intersect.height / factor))
                    if let lowCtx = CGContext(data: nil, width: lowW, height: lowH, bitsPerComponent: 8, bytesPerRow: lowW * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                        lowCtx.interpolationQuality = .none
                        lowCtx.draw(crop, in: CGRect(x: 0, y: 0, width: lowW, height: lowH))
                        if let lowImage = lowCtx.makeImage() {
                            context.saveGState()
                            context.translateBy(x: intersect.origin.x, y: intersect.origin.y + intersect.height)
                            context.scaleBy(x: 1.0, y: -1.0)
                            context.interpolationQuality = .low
                            context.draw(lowImage, in: CGRect(x: 0, y: 0, width: intersect.width, height: intersect.height))
                            context.restoreGState()
                        }
                    }
                }
            }

            // Outline around blurred area
            context.setStrokeColor(NSColor.lightGray.withAlphaComponent(0.5).cgColor)
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
            id: UUID(),
            rects: rects,
            filterMode: filterMode,
            intensity: intensity,
            isTextOnlyMode: isTextOnlyMode,
            zIndex: zIndex
        )
        copy.detectedTextRects = detectedTextRects
        return copy
    }
}
