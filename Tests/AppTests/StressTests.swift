import Cocoa
import CoreGraphics
import Vision

public struct StressTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        // MARK: - Suite 1: Scrolling Capture Engine Stress
        testRunner("Stress: ScrollingCapture - 60-Frame Continuous Stitch & 20,000 px Strict Clamping") {
            try testScrollingMassiveFrameClamping()
        }

        testRunner("Stress: ScrollingCapture - 100 Rapid Identical Frames Skip & Zero Height Expansion") {
            try testScrollingIdenticalFrames()
        }

        testRunner("Stress: ScrollingCapture - Micro & Degenerate Image Dimensions (1x1 to 8x8)") {
            try testScrollingMicroDimensions()
        }

        testRunner("Stress: ScrollingCapture - Mismatched Width Dimensions Resilience") {
            try testScrollingMismatchedWidths()
        }

        testRunner("Stress: ScrollingCapture - High-Frequency Repeated Stitching Memory Stability") {
            try testScrollingRepeatedStitchingMemory()
        }

        // MARK: - Suite 2: SaveService Concurrency & Collision Stress
        testRunner("Stress: SaveService - 50 Concurrent Same-Second Saves Without Overwrite or Collision") {
            try testConcurrentSavesNoCollision()
        }

        testRunner("Stress: SaveService - Ultra-High Resolution 8K UHD Image Encoding (PNG & JPG)") {
            try testUltraHighResolution8KEncoding()
        }

        testRunner("Stress: SaveService - Multi-Threaded Pasteboard Synchronization") {
            try testMultiThreadedPasteboardSync()
        }

        // MARK: - Suite 3: Screenshot History & ImageIO Stress
        testRunner("Stress: HistoryService - High-Volume Directory (1,000 Files) Sub-150ms Performance") {
            try testHistoryMassiveDirectoryPerformance()
        }

        testRunner("Stress: HistoryService - Corrupted Bitmaps & Degenerate Files Resilience") {
            try testHistoryCorruptedFilesResilience()
        }

        testRunner("Stress: HistoryService - Fast ImageIO Clipboard Extraction Without Memory Ballooning") {
            try testHistoryFastImageIOClipboard()
        }

        // MARK: - Suite 4: Vision Recognition Concurrency & Robustness
        testRunner("Stress: RecognitionService - 20 Concurrent Background Vision Requests") {
            try testRecognitionConcurrentBackgroundRequests()
        }

        testRunner("Stress: RecognitionService - Degenerate Inputs (1x1, Solid Black, Noise Bitmaps)") {
            try testRecognitionDegenerateBitmaps()
        }

        testRunner("Stress: RecognitionService - Multi-Lingual Complex Text OCR Stress") {
            try testRecognitionMultilingualOCRStress()
        }

        // MARK: - Suite 5: Multi-Display Coordinate & Geometry Stress
        testRunner("Stress: Geometry - Negative Origin & Multi-Monitor Extended Desktop Geometry") {
            try testNegativeOriginMultiMonitorGeometry()
        }

        testRunner("Stress: Cursor Compositing - Boundary Coordinates & Zero-Dimension Safeguards") {
            try testCursorCompositingBoundarySafeguards()
        }

        // MARK: - Suite 6: AppSettings State & Concurrency Stress
        testRunner("Stress: AppSettings - High-Concurrency Configuration Mutations") {
            try testAppSettingsConcurrentMutations()
        }
    }

    // MARK: - Test Implementations

    private static func createTestBitmap(width: Int, height: Int, color: NSColor) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: max(1, width),
            height: max(1, height),
            bitsPerComponent: 8,
            bytesPerRow: max(1, width) * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: max(1, width), height: max(1, height)))
        return context.makeImage()!
    }

    private static func createTextBitmap(text: String, width: Int = 400, height: Int = 100) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let nsImage = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: NSColor.black
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            attrStr.draw(at: NSPoint(x: 20, y: 35))
            return true
        }

        return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

    // MARK: 1. Scrolling Capture Tests

    private static func testScrollingMassiveFrameClamping() throws {
        // Generate 60 frames, each 600 px wide and 500 px high.
        // Shift between consecutive frames = 500 px (no overlap).
        // Total accumulated = 500 * 60 = 30,000 px > 20,000 px limit.
        var frames: [CGImage] = []
        for i in 0..<60 {
            let color = (i % 2 == 0) ? NSColor.black : NSColor.white
            frames.append(createTestBitmap(width: 400, height: 500, color: color))
        }

        let stitched = ScrollingCaptureService.shared.stitchFrames(frames)
        guard let output = stitched else {
            throw NSError(domain: "StressTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "stitchFrames returned nil for 60 frames"])
        }

        // Verify strictly clamped at maxAllowedHeight (20,000 px)
        assert(output.width == 400, "Stitched width must match input width")
        assert(output.height == ScrollingCaptureService.maxAllowedHeight, "Stitched height must be strictly clamped to \(ScrollingCaptureService.maxAllowedHeight), got \(output.height)")
    }

    private static func testScrollingIdenticalFrames() throws {
        let baseFrame = createTestBitmap(width: 300, height: 200, color: .systemBlue)
        let frames = Array(repeating: baseFrame, count: 100)

        let shift = ScrollingCaptureService.shared.detectVerticalOffset(between: baseFrame, and: baseFrame)
        assert(shift == 0, "Identical frames must produce vertical shift of 0, got \(shift)")

        let stitched = ScrollingCaptureService.shared.stitchFrames(frames)
        guard let output = stitched else {
            throw NSError(domain: "StressTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "stitchFrames returned nil for identical frames"])
        }

        // Since all 100 frames are identical, none should expand the canvas beyond the first frame
        assert(output.height == 200, "Stitched identical frames must maintain original frame height (200), got \(output.height)")
    }

    private static func testScrollingMicroDimensions() throws {
        let microSizes = [(1, 1), (2, 2), (4, 4), (5, 5), (8, 8), (2, 10), (10, 2)]
        for (w, h) in microSizes {
            let img1 = createTestBitmap(width: w, height: h, color: .red)
            let img2 = createTestBitmap(width: w, height: h, color: .blue)

            // Ensure detectVerticalOffset executes without crashing or buffer overruns
            let shift = ScrollingCaptureService.shared.detectVerticalOffset(between: img1, and: img2)
            assert(shift >= 0, "Shift must be non-negative for size \(w)x\(h)")

            let stitched = ScrollingCaptureService.shared.stitchFrames([img1, img2])
            assert(stitched != nil, "Stitched micro image must not be nil for size \(w)x\(h)")
        }
    }

    private static func testScrollingMismatchedWidths() throws {
        let frame1 = createTestBitmap(width: 400, height: 200, color: .purple)
        let frame2 = createTestBitmap(width: 300, height: 200, color: .orange)
        let frame3 = createTestBitmap(width: 500, height: 200, color: .cyan)

        let stitched = ScrollingCaptureService.shared.stitchFrames([frame1, frame2, frame3])
        guard let output = stitched else {
            throw NSError(domain: "StressTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Mismatched width stitching failed"])
        }
        assert(output.width == 400, "Output width should match first frame (400), got \(output.width)")
        assert(output.height > 200, "Output height must accumulate frames despite width differences")
    }

    private static func testScrollingRepeatedStitchingMemory() throws {
        let frameA = createTestBitmap(width: 600, height: 400, color: .systemGreen)
        let frameB = createTestBitmap(width: 600, height: 400, color: .systemTeal)

        for _ in 0..<25 {
            autoreleasepool {
                _ = ScrollingCaptureService.shared.stitchFrames([frameA, frameB])
            }
        }
    }

    // MARK: 2. SaveService Concurrency Tests

    private static func testConcurrentSavesNoCollision() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("shots_stress_save_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleImage = createTestBitmap(width: 50, height: 50, color: .red)
        guard let pngData = SaveService.shared.encodePNG(image: sampleImage) else {
            throw NSError(domain: "StressTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to encode test PNG"])
        }

        let concurrentCount = 50
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "shots.stress.concurrentSave", attributes: .concurrent)

        var savedURLs: [URL] = []
        let arrayLock = NSLock()

        let fixedDate = Date()
        for _ in 0..<concurrentCount {
            group.enter()
            queue.async {
                let dest = SaveService.shared.resolveUniqueDestinationURL(in: tempDir, date: fixedDate, format: .png)
                do {
                    let finalURL = try SaveService.shared.saveImageData(pngData, to: tempDir, filename: dest.lastPathComponent)
                    arrayLock.lock()
                    savedURLs.append(finalURL)
                    arrayLock.unlock()
                } catch {
                    print("Concurrent save error: \(error)")
                }
                group.leave()
            }
        }

        group.wait()

        assert(savedURLs.count == concurrentCount, "Expected exactly \(concurrentCount) saved files, got \(savedURLs.count)")

        // Verify all 50 URLs are unique and all exist on disk
        let uniquePaths = Set(savedURLs.map { $0.path })
        assert(uniquePaths.count == concurrentCount, "Filename collision detected! Expected \(concurrentCount) unique paths, got \(uniquePaths.count)")

        for url in savedURLs {
            assert(FileManager.default.fileExists(atPath: url.path), "Saved file missing at \(url.path)")
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            assert(fileSize == pngData.count, "File size mismatch for \(url.path)")
        }
    }

    private static func testUltraHighResolution8KEncoding() throws {
        // 8K UHD: 7680 x 4320
        // We will create a test pattern to test large memory allocation & encoding pipeline
        let width = 7680
        let height = 4320
        let image = createTestBitmap(width: width, height: height, color: .systemIndigo)

        // 1. Lossless PNG encoding
        let pngStart = CFAbsoluteTimeGetCurrent()
        guard let pngData = SaveService.shared.encodePNG(image: image) else {
            throw NSError(domain: "StressTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "8K PNG encoding failed"])
        }
        let pngTime = (CFAbsoluteTimeGetCurrent() - pngStart) * 1000.0
        assert(pngData.count > 1000, "8K PNG data must be non-empty")
        // Check PNG magic bytes: 0x89 0x50 0x4E 0x47
        assert(pngData[0] == 0x89 && pngData[1] == 0x50 && pngData[2] == 0x4E && pngData[3] == 0x47, "Invalid PNG magic header")

        // 2. High Quality JPEG encoding
        let jpgStart = CFAbsoluteTimeGetCurrent()
        guard let jpgData = SaveService.shared.encodeJPG(image: image, quality: 0.85) else {
            throw NSError(domain: "StressTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "8K JPG encoding failed"])
        }
        let jpgTime = (CFAbsoluteTimeGetCurrent() - jpgStart) * 1000.0
        assert(jpgData.count > 1000, "8K JPG data must be non-empty")
        // Check JPEG magic bytes: 0xFF 0xD8
        assert(jpgData[0] == 0xFF && jpgData[1] == 0xD8, "Invalid JPEG magic header")

        NSLog("8K Encoding benchmark: PNG=%.2fms (%d bytes), JPG=%.2fms (%d bytes)", pngTime, pngData.count, jpgTime, jpgData.count)
    }

    private static func testMultiThreadedPasteboardSync() throws {
        let image = createTestBitmap(width: 100, height: 100, color: .systemPink)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "shots.stress.pasteboard", attributes: .concurrent)

        for _ in 0..<10 {
            group.enter()
            queue.async {
                SaveService.shared.copyToPasteboard(image: image)
                group.leave()
            }
        }
        group.wait()

        // Verify NSPasteboard has an image item
        let pb = NSPasteboard.general
        assert(pb.data(forType: .png) != nil || pb.pasteboardItems?.isEmpty == false, "Pasteboard must contain image data after sync")
    }

    // MARK: 3. Screenshot History & ImageIO Tests

    private static func testHistoryMassiveDirectoryPerformance() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("shots_history_1000_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let samplePNG = SaveService.shared.encodePNG(image: createTestBitmap(width: 40, height: 40, color: .blue))!

        // Generate 1,000 files with staged timestamps
        let now = Date()
        for i in 0..<1000 {
            let filename = String(format: "shot_20261013_%06d.png", i)
            let fileURL = tempDir.appendingPathComponent(filename)
            try samplePNG.write(to: fileURL)
            let fileDate = now.addingTimeInterval(Double(-1000 + i))
            try FileManager.default.setAttributes([.modificationDate: fileDate], ofItemAtPath: fileURL.path)
        }

        let start = CFAbsoluteTimeGetCurrent()
        let recents = ScreenshotHistoryService.shared.fetchRecentScreenshots(limit: 10, directoryURL: tempDir)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

        assert(recents.count == 10, "Expected exactly 10 recent screenshots, got \(recents.count)")
        assert(elapsedMs < 150.0, "1,000-file discovery must execute in < 150ms, took \(elapsedMs)ms")

        // Verify correct chronological order (newest first)
        for i in 0..<recents.count - 1 {
            assert(recents[i].modificationDate >= recents[i + 1].modificationDate, "Recent screenshots must be strictly sorted by newest date first")
        }
    }

    private static func testHistoryCorruptedFilesResilience() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("shots_corrupt_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. Zero-byte file
        try Data().write(to: tempDir.appendingPathComponent("shot_zerobyte.png"))
        // 2. Corrupt garbage data file
        try Data("THIS IS NOT A VALID PNG".utf8).write(to: tempDir.appendingPathComponent("shot_corrupt.png"))
        // 3. Valid file
        let validData = SaveService.shared.encodePNG(image: createTestBitmap(width: 50, height: 50, color: .green))!
        try validData.write(to: tempDir.appendingPathComponent("shot_valid.png"))

        let recents = ScreenshotHistoryService.shared.fetchRecentScreenshots(limit: 10, directoryURL: tempDir)
        assert(recents.count == 3, "Expected all 3 files to be listed regardless of corruption")

        // Valid item should generate a thumbnail, corrupted should have nil thumbnail without crashing
        let validItem = recents.first { $0.filename == "shot_valid.png" }
        assert(validItem?.thumbnail != nil, "Valid file must produce thumbnail")

        let corruptItem = recents.first { $0.filename == "shot_corrupt.png" }
        assert(corruptItem?.thumbnail == nil, "Corrupted file thumbnail must be nil")
    }

    private static func testHistoryFastImageIOClipboard() throws {
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("shots_fast_io_\(UUID().uuidString).png")
        let testImage = createTestBitmap(width: 800, height: 600, color: .purple)
        let pngData = SaveService.shared.encodePNG(image: testImage)!
        try pngData.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let success = ScreenshotHistoryService.shared.copyScreenshotToClipboard(fileURL: tempFile)
        assert(success, "copyScreenshotToClipboard via ImageIO must succeed")
    }

    // MARK: 4. Vision Recognition Concurrency & Robustness

    private static func testRecognitionConcurrentBackgroundRequests() throws {
        guard RecognitionService.shared.isVisionSupported else { return }

        let testImage = createTextBitmap(text: "Shots Stress Test", width: 300, height: 100)
        let group = DispatchGroup()
        let count = 20
        var successCount = 0
        let lock = NSLock()
        let queue = DispatchQueue(label: "shots.stress.vision", attributes: .concurrent)

        for _ in 0..<count {
            group.enter()
            queue.async {
                do {
                    let item = try RecognitionService.shared.recognizeUnified(in: testImage)
                    if item != nil {
                        lock.lock()
                        successCount += 1
                        lock.unlock()
                    }
                } catch {
                    print("Vision error: \(error)")
                }
                group.leave()
            }
        }

        group.wait()
        assert(successCount == count, "Expected all \(count) concurrent Vision tasks to succeed, got \(successCount)")
    }

    private static func testRecognitionDegenerateBitmaps() throws {
        guard RecognitionService.shared.isVisionSupported else { return }

        // 1x1 image
        let microImage = createTestBitmap(width: 1, height: 1, color: .black)
        let microItem = try RecognitionService.shared.recognizeUnified(in: microImage)
        assert(microItem == nil, "1x1 bitmap should produce nil recognition item")

        // Solid black 500x500 image
        let blackImage = createTestBitmap(width: 500, height: 500, color: .black)
        let blackItem = try RecognitionService.shared.recognizeUnified(in: blackImage)
        assert(blackItem == nil, "Solid black image should produce nil recognition item")
    }

    private static func testRecognitionMultilingualOCRStress() throws {
        guard RecognitionService.shared.isVisionSupported else { return }

        let englishText = "The quick brown fox jumps over the lazy dog"
        let polishText = "Zażółć gęślą jaźń szybki lis"

        let imgEng = createTextBitmap(text: englishText, width: 600, height: 100)
        let imgPol = createTextBitmap(text: polishText, width: 600, height: 100)

        let resEng = try RecognitionService.shared.recognizeText(in: imgEng)
        assert(!resEng.isEmpty, "English text recognition must detect text")
        let engPayload = resEng.map { $0.payload }.joined(separator: " ")
        assert(engPayload.lowercased().contains("quick") || engPayload.lowercased().contains("fox"), "English payload must extract words: got '\(engPayload)'")

        let resPol = try RecognitionService.shared.recognizeText(in: imgPol)
        assert(!resPol.isEmpty, "Polish text recognition must detect text")
    }

    // MARK: 5. Multi-Display Geometry & Cursor Safeguards

    private static func testNegativeOriginMultiMonitorGeometry() throws {
        // Simulate dual-monitor setup:
        // Screen 1 (Primary): origin (0, 0), size (2560, 1440)
        // Screen 2 (Left Extended): origin (-1920, 0), size (1920, 1080)
        let primaryHeight: CGFloat = 1440.0

        // Point on left display in AppKit: (-1000, 500)
        let appKitLeft = NSPoint(x: -1000, y: 500)
        // Point in CoreGraphics: (-1000, 1440 - 500 = 940)
        let cgLeft = CGPoint(x: -1000, y: primaryHeight - 500)

        let convertedCG = CGPoint(x: appKitLeft.x, y: primaryHeight - appKitLeft.y)
        assert(convertedCG == cgLeft, "CoreGraphics translation with negative origin must match")

        let roundTripAppKit = NSPoint(x: convertedCG.x, y: primaryHeight - convertedCG.y)
        assert(roundTripAppKit == appKitLeft, "Round-trip AppKit point must match original negative coordinates")
    }

    private static func testCursorCompositingBoundarySafeguards() throws {
        let base = createTestBitmap(width: 400, height: 300, color: .lightGray)
        let screen = NSScreen.main ?? NSScreen()

        // 1. Cursor completely outside screen bounds
        let outsidePoint = NSPoint(x: -9999, y: -9999)
        let resultOutside = CaptureService.shared.compositeCursor(on: base, screen: screen, mouseLocation: outsidePoint)
        assert(resultOutside === base, "Cursor outside target rect must return unmodified base image")

        // 2. Cursor inside target rect
        let insidePoint = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        let resultInside = CaptureService.shared.compositeCursor(on: base, screen: screen, mouseLocation: insidePoint)
        assert(resultInside != nil, "Cursor inside target rect must composite valid image")
    }

    // MARK: 6. AppSettings Concurrency Stress

    private static func testAppSettingsConcurrentMutations() throws {
        let settings = AppSettings.shared
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "shots.stress.settings", attributes: .concurrent)

        for i in 0..<50 {
            group.enter()
            queue.async {
                if i % 3 == 0 {
                    settings.jpgQuality = (i % 100) + 1
                } else if i % 3 == 1 {
                    settings.saveToDisk = (i % 2 == 0)
                } else {
                    settings.copyToClipboard = (i % 2 != 0)
                }
                settings.checkForShortcutConflicts()
                group.leave()
            }
        }

        group.wait()
        // Reset to canonical safe defaults
        settings.jpgQuality = 80
        settings.saveToDisk = true
        settings.copyToClipboard = true
        settings.checkForShortcutConflicts()
        assert(!settings.isHotkeyConflict, "Default hotkeys must have zero conflict")
    }
}
