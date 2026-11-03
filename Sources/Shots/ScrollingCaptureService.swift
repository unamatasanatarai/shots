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
/// copied out immediately, so captured frames can be released as soon as they are compared.
/// Rows are appended to one contiguous BGRA buffer that becomes the final image's backing store
/// without another copy, so peak memory stays ~1x the stitched image (not slices + composite).
final class ScrollStitcher {
    private let width: Int
    private let maxHeight: Int
    private let colorSpace: CGColorSpace
    private let bytesPerRow: Int
    private var buffer: NSMutableData?
    private(set) var height = 0
    /// Bytes the stitched image may occupy: the height cap alone lets a full-width 6K region reach ~480 MB,
    /// before the encoded file and clipboard copies pile on
    static let byteBudget = 256 * 1024 * 1024

    var isFull: Bool { height >= maxHeight }

    init(firstFrame: CGImage, maxHeight: Int) {
        self.width = firstFrame.width
        self.bytesPerRow = firstFrame.width * 4
        let rowsInBudget = bytesPerRow > 0 ? Self.byteBudget / bytesPerRow : maxHeight
        self.maxHeight = max(min(firstFrame.height, maxHeight), min(maxHeight, rowsInBudget))
        // Reserve the whole budget once: growing in steps reallocates, briefly holding old and new copies
        // (~2x peak). Untouched pages of the reservation are never committed.
        self.buffer = NSMutableData(capacity: self.maxHeight * bytesPerRow) ?? NSMutableData()
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

    private static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    private func appendRows(of frame: CGImage, from sourceY: Int, count: Int) {
        guard let buffer = buffer, width > 0 else { return }
        let rows = min(count, maxHeight - height)
        guard rows > 0 else { return }
        let sliceWidth = min(width, frame.width)
        guard let crop = frame.cropping(to: CGRect(x: 0, y: sourceY, width: sliceWidth, height: rows)) else { return }

        // Grow the shared buffer and render the new rows straight into its tail
        let offset = buffer.length
        buffer.increaseLength(by: rows * bytesPerRow) // zero-filled
        let tail = buffer.mutableBytes.advanced(by: offset)
        guard let ctx = CGContext(
            data: tail, width: width, height: rows, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: Self.bitmapInfo
        ) else {
            buffer.length = offset
            return
        }
        if sliceWidth < width {
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: rows))
        }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: sliceWidth, height: rows))
        height += rows
    }

    /// Hands the buffer to the image; the stitcher cannot be appended to afterwards.
    func makeImage() -> CGImage? {
        guard height > 0, let buffer = buffer,
              let provider = CGDataProvider(data: buffer as CFData) else { return nil }
        self.buffer = nil
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: Self.bitmapInfo),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
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
    /// `expectedShift` (pixels the synthetic scroll should have moved) breaks ties on periodic content
    /// (grids, list separators), where several shifts line up equally well; nil keeps the smallest best shift.
    func detectVerticalOffset(between frame1: FramePixels, and frame2: FramePixels, expectedShift: Int? = nil) -> Int {
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

        // 1. Exact full-row matching: finds the shift for sparse content that a sampling grid misses
        if let exact = exactRowShift(
            ptr1: ptr1, bpr1: bpr1, len1: len1, ptr2: ptr2, bpr2: bpr2, len2: len2,
            height: height, colStart: colStart, colEnd: colEnd, maxShift: maxShift, expectedShift: expectedShift
        ) {
            return exact
        }

        // 2. Tolerant sampled matching (content re-rendered slightly differently between frames)

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

    /// Hashes each row's pixels in [colStart, colEnd) and flags rows that carry content
    /// (not a single flat colour), so blank background rows cannot vote for a shift
    private func rowSignatures(
        ptr: UnsafePointer<UInt8>, bpr: Int, len: Int, height: Int, colStart: Int, colEnd: Int
    ) -> (hashes: [Int], informative: [Bool])? {
        let byteStart = colStart * 4
        let byteCount = (colEnd - colStart) * 4
        guard byteCount > 0, (height - 1) * bpr + byteStart + byteCount <= len else { return nil }
        var hashes = [Int](repeating: 0, count: height)
        var informative = [Bool](repeating: false, count: height)
        let raw = UnsafeRawPointer(ptr)
        for y in 0..<height {
            let rowStart = y * bpr + byteStart
            var hasher = Hasher()
            hasher.combine(bytes: UnsafeRawBufferPointer(start: raw + rowStart, count: byteCount))
            hashes[y] = hasher.finalize()
            // A row is a single flat colour iff it equals itself shifted by one pixel
            informative[y] = byteCount > 4 && memcmp(raw + rowStart, raw + rowStart + 4, byteCount - 4) != 0
        }
        return (hashes, informative)
    }

    /// Smallest-ambiguity exact shift: the shift where (nearly) every content row of the overlap
    /// matches byte-for-byte. Returns nil when no shift matches well enough (caller falls back
    /// to the tolerant sampled search).
    private func exactRowShift(
        ptr1: UnsafePointer<UInt8>, bpr1: Int, len1: Int,
        ptr2: UnsafePointer<UInt8>, bpr2: Int, len2: Int,
        height: Int, colStart: Int, colEnd: Int, maxShift: Int, expectedShift: Int? = nil
    ) -> Int? {
        guard let sig1 = rowSignatures(ptr: ptr1, bpr: bpr1, len: len1, height: height, colStart: colStart, colEnd: colEnd),
              let sig2 = rowSignatures(ptr: ptr2, bpr: bpr2, len: len2, height: height, colStart: colStart, colEnd: colEnd) else {
            return nil
        }
        // Flat frames (no content rows at all) carry no alignment information
        guard sig1.informative.contains(true) || sig2.informative.contains(true) else { return nil }

        // Every shift where (nearly) all content rows of the overlap line up, with its match count
        var candidates: [(shift: Int, matches: Int)] = []
        sig1.hashes.withUnsafeBufferPointer { h1 in
        sig2.hashes.withUnsafeBufferPointer { h2 in
        sig1.informative.withUnsafeBufferPointer { i1 in
        sig2.informative.withUnsafeBufferPointer { i2 in
            // Shift 0 too: the byte-identity check fails on any animated pixel (blinking caret, spinner,
            // flashing overlay scrollbar), yet the page did not move
            for shift in 0...maxShift {
                var considered = 0
                var matches = 0
                var y = 0
                let overlap = height - shift
                while y < overlap {
                    let a = y + shift
                    if i1[a] || i2[y] {
                        considered += 1
                        if h1[a] == h2[y] { matches += 1 }
                    }
                    y += 1
                }
                // Require at least two content rows and >= 95% of the content rows to line up
                guard considered >= 2, matches * 100 >= considered * 95 else { continue }
                candidates.append((shift, matches))
            }
        }
        }
        }
        }
        // No movement wins when it explains at least as much content as any real shift: at the bottom of a
        // periodic page (grid, ruled rows) every period multiple lines up too, but the page did not move
        let bestPositiveMatches = candidates.filter { $0.shift > 0 }.map(\.matches).max() ?? 0
        if let still = candidates.first(where: { $0.shift == 0 }), still.matches >= bestPositiveMatches {
            return 0
        }
        if let expected = expectedShift, expected > 0 {
            // The scroll that was actually posted decides between equally good periodic alignments, but only
            // close to it: a shorter final scroll must not be pulled to a period multiple near `expected`
            // (Match counts are not compared across shifts: a smaller shift has more overlap, so more matches.)
            let near = candidates.filter { $0.shift > 0 && abs($0.shift - expected) <= expected / 2 }
            if let pick = near.min(by: { a, b in
                let da = abs(a.shift - expected), db = abs(b.shift - expected)
                return da != db ? da < db : a.matches > b.matches
            }) {
                return pick.shift
            }
        }
        // Prefer the alignment that explains the most content (smallest shift on ties)
        var best: (shift: Int, matches: Int)?
        for c in candidates where c.shift > 0 && c.matches > (best?.matches ?? 0) { best = c }
        return best?.shift
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
        // Compare every row in full: sparse content (a few words on a plain background) that
        // moved would slip through a sampling grid and the scrolled frame would be dropped
        let rowBytes = width * 4
        guard bpr1 >= rowBytes && bpr2 >= rowBytes else { return false }
        guard (height - 1) * bpr1 + rowBytes <= len1 && (height - 1) * bpr2 + rowBytes <= len2 else { return false }
        for y in 0..<height {
            if memcmp(ptr1 + y * bpr1, ptr2 + y * bpr2, rowBytes) != 0 {
                return false
            }
        }
        return true
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
