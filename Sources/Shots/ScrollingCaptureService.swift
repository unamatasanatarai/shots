import Cocoa
import CoreGraphics

/// A frame's pixel bytes, copied out of its data provider once
struct FramePixels {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    private let data: CFData?

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        bytesPerRow = image.bytesPerRow
        data = image.dataProvider?.data
    }

    var bytes: UnsafePointer<UInt8>? { data.flatMap { CFDataGetBytePtr($0) } }
    var length: Int { data.map { CFDataGetLength($0) } ?? 0 }
}

/// Builds a scrolling capture incrementally: each frame contributes only its newly revealed rows,
/// copied out immediately, so captured frames can be released as soon as they are compared
final class ScrollStitcher {
    private let width: Int
    private let maxHeight: Int
    private let colorSpace: CGColorSpace
    private var slices: [CGImage] = []
    private(set) var height = 0

    var isFull: Bool { height >= maxHeight }

    init(firstFrame: CGImage, maxHeight: Int) {
        self.width = firstFrame.width
        self.maxHeight = maxHeight
        if let space = firstFrame.colorSpace, space.model == .rgb {
            self.colorSpace = space
        } else {
            self.colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }
        appendRows(of: firstFrame, from: 0, count: firstFrame.height)
    }

    /// Appends the bottom `newRows` rows of the frame (the content scrolled into view)
    func append(_ frame: CGImage, newRows: Int) {
        let count = min(newRows, frame.height)
        appendRows(of: frame, from: frame.height - count, count: count)
    }

    private func appendRows(of frame: CGImage, from sourceY: Int, count: Int) {
        let rows = min(count, maxHeight - height)
        guard rows > 0 else { return }
        let sliceWidth = min(width, frame.width)
        guard let crop = frame.cropping(to: CGRect(x: 0, y: sourceY, width: sliceWidth, height: rows)),
              let ctx = Self.makeContext(width: width, height: rows, colorSpace: colorSpace) else { return }
        if sliceWidth < width {
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: rows))
        }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: sliceWidth, height: rows))
        // Owns its own pixels: the source frame is not retained
        guard let slice = ctx.makeImage() else { return }
        slices.append(slice)
        height += rows
    }

    func makeImage() -> CGImage? {
        guard height > 0 else { return nil }
        if slices.count == 1 { return slices[0] }
        guard let ctx = Self.makeContext(width: width, height: height, colorSpace: colorSpace) else { return nil }
        // Bitmap origin is bottom-left: lay slices out top to bottom
        var top = 0
        for slice in slices {
            ctx.draw(slice, in: CGRect(x: 0, y: height - top - slice.height, width: slice.width, height: slice.height))
            top += slice.height
        }
        slices.removeAll()
        return ctx.makeImage()
    }

    /// Native BGRA (the display capture layout), so drawing captured frames is a plain copy
    private static func makeContext(width: Int, height: Int, colorSpace: CGColorSpace) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }
}

public final class ScrollingCaptureService {
    public static let shared = ScrollingCaptureService()

    /// The maximum allowed output height for scrolling captures (enforced at 20,000 px).
    public static let maxAllowedHeight: Int = 20_000

    public init() {}

    // MARK: - Overlap Detection

    /// Detects vertical scroll offset (pixels scrolled) between consecutive frames.
    /// Returns the number of new vertical pixels introduced in frame2, or nil if no valid shift found.
    public func detectVerticalOffset(between frame1: CGImage, and frame2: CGImage) -> Int {
        return detectVerticalOffset(between: FramePixels(frame1), and: FramePixels(frame2))
    }

    /// Same as above on pixel buffers fetched once, so a frame compared twice is copied only once
    func detectVerticalOffset(between frame1: FramePixels, and frame2: FramePixels) -> Int {
        guard frame1.width > 0 && frame1.height > 0 && frame2.width > 0 && frame2.height > 0 else {
            return frame2.height
        }
        guard frame1.width == frame2.width else { return frame2.height }
        let width = frame1.width
        let height = frame1.height

        guard let ptr1 = frame1.bytes, let ptr2 = frame2.bytes else {
            return height
        }

        let len1 = frame1.length
        let len2 = frame2.length
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
            var totalDiff: Int64 = 0
            var sampleCount = 0
            let rowStep = max(1, overlapHeight / 30)

            for y in stride(from: 0, to: overlapHeight, by: rowStep) {
                let rowIdx1 = (y + s) * bpr1
                let rowIdx2 = y * bpr2

                for x in stride(from: colStart, to: colEnd, by: colStep) {
                    let idx1 = rowIdx1 + x * 4
                    let idx2 = rowIdx2 + x * 4
                    guard idx1 + 2 < len1 && idx2 + 2 < len2 else { continue }
                    let d0 = abs(Int32(ptr1[idx1]) - Int32(ptr2[idx2]))
                    let d1 = abs(Int32(ptr1[idx1 + 1]) - Int32(ptr2[idx2 + 1]))
                    let d2 = abs(Int32(ptr1[idx1 + 2]) - Int32(ptr2[idx2 + 2]))
                    totalDiff += Int64(d0 + d1 + d2)
                    sampleCount += 1
                }
            }
            return sampleCount > 0 ? (Double(totalDiff) / Double(sampleCount)) : Double.greatestFiniteMagnitude
        }

        var bestShift = height
        var minDifference = Double.greatestFiniteMagnitude
        var maxDifference = 0.0

        // Coarse-to-fine search when maxShift is large for 3x faster alignment
        if maxShift > 30 {
            let step = 3
            var coarseBest = 1
            for shift in stride(from: 1, through: maxShift, by: step) {
                let avgDiff = calcDiff(forShift: shift)
                if avgDiff < minDifference {
                    minDifference = avgDiff
                    coarseBest = shift
                    bestShift = shift
                }
                if avgDiff > maxDifference {
                    maxDifference = avgDiff
                }
            }
            // Refine in a tight window around coarse best
            let refineMin = max(1, coarseBest - step)
            let refineMax = min(maxShift, coarseBest + step)
            for shift in refineMin...refineMax where shift != coarseBest {
                let avgDiff = calcDiff(forShift: shift)
                if avgDiff < minDifference {
                    minDifference = avgDiff
                    bestShift = shift
                }
                if avgDiff > maxDifference {
                    maxDifference = avgDiff
                }
            }
        } else {
            // Exact single-pixel precision search for small ranges
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
            let r1 = y * bpr1
            let r2 = y * bpr2
            for x in sampleCols {
                let i1 = r1 + x * 4
                let i2 = r2 + x * 4
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

        let stitcher = ScrollStitcher(firstFrame: firstFrame, maxHeight: maxHeight)
        var previous = FramePixels(firstFrame)
        for i in 1..<frames.count {
            if stitcher.isFull { break }
            autoreleasepool {
                let current = FramePixels(frames[i])
                let shift = detectVerticalOffset(between: previous, and: current)
                previous = current
                // Identical frame: skip duplicate
                guard shift > 0 else { return }
                stitcher.append(frames[i], newRows: shift)
            }
        }
        return stitcher.makeImage() ?? clampImageHeight(firstFrame, maxHeight: maxHeight)
    }

    /// Enforces height clamping on any single image at maxAllowedHeight (20,000 px).
    public func clampImageHeight(_ image: CGImage, maxHeight: Int = maxAllowedHeight) -> CGImage {
        guard image.height > maxHeight else { return image }
        let cropRect = CGRect(x: 0, y: 0, width: image.width, height: maxHeight)
        return image.cropping(to: cropRect) ?? image
    }
}
