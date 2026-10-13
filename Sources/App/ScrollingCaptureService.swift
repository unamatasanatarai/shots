import Cocoa
import CoreGraphics

public final class ScrollingCaptureService {
    public static let shared = ScrollingCaptureService()

    /// The maximum allowed output height for scrolling captures (enforced at 20,000 px).
    public static let maxAllowedHeight: Int = 20_000

    public init() {}

    // MARK: - Overlap Detection

    /// Detects vertical scroll offset (pixels scrolled) between consecutive frames.
    /// Returns the number of new vertical pixels introduced in frame2, or nil if no valid shift found.
    public func detectVerticalOffset(between frame1: CGImage, and frame2: CGImage) -> Int {
        guard frame1.width > 0 && frame1.height > 0 && frame2.width > 0 && frame2.height > 0 else {
            return frame2.height
        }
        guard frame1.width == frame2.width else { return frame2.height }
        let width = frame1.width
        let height = frame1.height

        guard let data1 = frame1.dataProvider?.data, let ptr1 = CFDataGetBytePtr(data1),
              let data2 = frame2.dataProvider?.data, let ptr2 = CFDataGetBytePtr(data2) else {
            return height
        }

        let len1 = CFDataGetLength(data1)
        let len2 = CFDataGetLength(data2)
        let bpr1 = frame1.bytesPerRow
        let bpr2 = frame2.bytesPerRow

        // If frames are identical, shift is 0
        if areFramesIdentical(ptr1: ptr1, bpr1: bpr1, len1: len1, ptr2: ptr2, bpr2: bpr2, len2: len2, width: width, height: height) {
            return 0
        }

        if height <= 5 {
            return height
        }

        // Bounded search range: require meaningful overlap to prevent false matches at the boundary
        let minOverlap = max(1, min(40, height / 3))
        let maxShift = max(1, min(height - minOverlap, max(500, height / 2)))
        guard maxShift >= 1 else { return height }

        // Horizontal sample bounds:
        // Inset by 10px on the left (gutter/line numbers) and 25px on the right (scrollbar thumb)
        let colStart = (width >= 20) ? 10 : 0
        let colEnd = (width >= 40) ? (width - 25) : width
        let colStep = max(1, (colEnd - colStart) / 30)

        func calcDiff(forShift s: Int) -> Double {
            let overlapHeight = height - s
            var totalDiff = 0.0
            var sampleCount = 0
            let rowStep = max(1, overlapHeight / 30)

            for y in stride(from: 0, to: overlapHeight, by: rowStep) {
                let row1 = y + s
                let row2 = y
                let rowIdx1 = row1 * bpr1
                let rowIdx2 = row2 * bpr2

                for x in stride(from: colStart, to: colEnd, by: colStep) {
                    let idx1 = rowIdx1 + x * 4
                    let idx2 = rowIdx2 + x * 4
                    guard idx1 + 2 < len1 && idx2 + 2 < len2 else { continue }
                    let diff = abs(Double(ptr1[idx1]) - Double(ptr2[idx2])) +
                               abs(Double(ptr1[idx1 + 1]) - Double(ptr2[idx2 + 1])) +
                               abs(Double(ptr1[idx1 + 2]) - Double(ptr2[idx2 + 2]))
                    totalDiff += diff
                    sampleCount += 1
                }
            }
            return sampleCount > 0 ? (totalDiff / Double(sampleCount)) : Double.greatestFiniteMagnitude
        }

        var bestShift = height
        var minDifference = Double.greatestFiniteMagnitude
        var maxDifference = 0.0

        // Exact single-pixel precision search: tests every candidate shift
        for shift in 1...maxShift {
            let avgDiff = calcDiff(forShift: shift)
            if avgDiff < minDifference {
                minDifference = avgDiff
                bestShift = shift
            }
            if avgDiff > maxDifference {
                maxDifference = avgDiff
            }
        }

        // Match validation: low average difference and distinct contrast against non-matching shifts
        if minDifference < 35.0 && (maxDifference - minDifference >= 2.0) {
            return bestShift
        }

        // Fallback: return full frame height if no overlap found
        return height
    }

    private func areFramesIdentical(
        ptr1: UnsafePointer<UInt8>,
        bpr1: Int,
        len1: Int,
        ptr2: UnsafePointer<UInt8>,
        bpr2: Int,
        len2: Int,
        width: Int,
        height: Int
    ) -> Bool {
        guard width > 0 && height > 0 else { return false }
        let sampleRows = stride(from: 0, to: height, by: max(1, height / 10))
        let sampleCols = stride(from: 0, to: width, by: max(1, width / 10))
        var samplesChecked = 0
        for y in sampleRows {
            for x in sampleCols {
                let i1 = y * bpr1 + x * 4
                let i2 = y * bpr2 + x * 4
                guard i1 + 2 < len1 && i2 + 2 < len2 else { return false }
                if ptr1[i1] != ptr2[i2] || ptr1[i1 + 1] != ptr2[i2 + 1] || ptr1[i1 + 2] != ptr2[i2 + 2] {
                    return false
                }
                samplesChecked += 1
            }
        }
        return samplesChecked > 0
    }

    // MARK: - Frame Stitching & Height Clamping

    /// Stitches an array of captured frames into a single continuous vertical image.
    /// Strictly enforces maximum output height clamping at 20,000 px.
    public func stitchFrames(_ frames: [CGImage], maxHeight: Int = maxAllowedHeight) -> CGImage? {
        guard let firstFrame = frames.first else { return nil }
        if frames.count == 1 {
            return clampImageHeight(firstFrame, maxHeight: maxHeight)
        }

        let width = firstFrame.width
        var slices: [(image: CGImage, sourceY: Int, sliceHeight: Int)] = []

        // Initial slice is full first frame
        slices.append((image: firstFrame, sourceY: 0, sliceHeight: firstFrame.height))
        var accumulatedHeight = firstFrame.height

        for i in 1..<frames.count {
            if accumulatedHeight >= maxHeight {
                break
            }

            autoreleasepool {
                let prev = frames[i - 1]
                let curr = frames[i]
                let shift = detectVerticalOffset(between: prev, and: curr)

                if shift == 0 {
                    // Identical frame, skip duplicate
                    return
                }

                // Slice out the newly revealed bottom content
                let sliceHeight = min(shift, curr.height)
                let sourceY = max(0, curr.height - sliceHeight)

                // Check if adding this slice exceeds max allowed height
                let remainingSpace = maxHeight - accumulatedHeight
                let actualSliceHeight = min(sliceHeight, remainingSpace)

                if actualSliceHeight > 0 {
                    slices.append((image: curr, sourceY: sourceY, sliceHeight: actualSliceHeight))
                    accumulatedHeight += actualSliceHeight
                }
            }
        }

        // Clamp final height to exactly maxHeight if exceeded
        let finalHeight = min(accumulatedHeight, maxHeight)
        guard finalHeight > 0 else { return firstFrame }

        // Create unified CGContext
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: finalHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return clampImageHeight(firstFrame, maxHeight: maxHeight)
        }

        // Fill background
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: finalHeight))

        // Draw slices top to bottom in bitmap coordinates
        var currentYOffset = 0
        for slice in slices {
            let cropW = min(width, slice.image.width)
            guard let croppedSlice = slice.image.cropping(to: CGRect(
                x: 0,
                y: slice.sourceY,
                width: cropW,
                height: slice.sliceHeight
            )) else {
                continue
            }

            // In CGContext (flipped coordinates), draw each slice sequentially
            let drawRect = CGRect(
                x: 0,
                y: finalHeight - currentYOffset - slice.sliceHeight,
                width: cropW,
                height: slice.sliceHeight
            )
            ctx.draw(croppedSlice, in: drawRect)
            currentYOffset += slice.sliceHeight

            if currentYOffset >= finalHeight {
                break
            }
        }

        return ctx.makeImage()
    }

    /// Enforces height clamping on any single image at maxAllowedHeight (20,000 px).
    public func clampImageHeight(_ image: CGImage, maxHeight: Int = maxAllowedHeight) -> CGImage {
        guard image.height > maxHeight else { return image }
        let cropRect = CGRect(x: 0, y: 0, width: image.width, height: maxHeight)
        return image.cropping(to: cropRect) ?? image
    }
}
