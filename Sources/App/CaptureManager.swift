import Cocoa
import CoreGraphics

public struct LastCaptureRecord: Equatable {
    public enum Mode: Equatable {
        case fullscreen
        case region(rect: NSRect, screenFrame: NSRect, displayID: CGDirectDisplayID)
    }

    public let mode: Mode
    public let timestamp: Date

    public init(mode: Mode, timestamp: Date = Date()) {
        self.mode = mode
        self.timestamp = timestamp
    }
}

public final class CaptureManager {
    public static let shared = CaptureManager()

    public var lastCapture: LastCaptureRecord?

    private init() {}

    // MARK: - Capture Triggers

    public func startRegionCapture(delay: Int? = nil) {
        let delaySeconds = delay ?? AppSettings.shared.captureDelaySeconds
        if delaySeconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(delaySeconds)) { [weak self] in
                self?.executeRegionCapture()
            }
        } else {
            executeRegionCapture()
        }
    }

    private func executeRegionCapture() {
        RegionSelectionCoordinator.shared.startSelection { [weak self] capturedImage in
            guard let image = capturedImage else { return }
            self?.processCapturedImage(image)
        }
    }

    public func startOCRRecognition(delay: Int? = nil, completion: ((RecognitionItem?) -> Void)? = nil) {
        let delaySeconds = delay ?? AppSettings.shared.captureDelaySeconds
        if delaySeconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(delaySeconds)) { [weak self] in
                self?.executeOCRRecognition(completion: completion)
            }
        } else {
            executeOCRRecognition(completion: completion)
        }
    }

    private func executeOCRRecognition(completion: ((RecognitionItem?) -> Void)? = nil) {
        RegionSelectionCoordinator.shared.startSelection { capturedImage in
            guard let image = capturedImage else {
                completion?(nil)
                return
            }
            RecognitionService.shared.recognizeUnifiedAsync(in: image) { result in
                switch result {
                case .success(let item):
                    if let recognized = item {
                        RecognitionService.shared.copyPayloadToPasteboard(recognized)
                        OCRNotificationController.shared.show(snippet: recognized.payload)
                        NSLog("OCR Recognition succeeded (%@): %@", recognized.type.rawValue, recognized.payload)
                    } else {
                        NSSound.beep()
                    }
                    completion?(item)
                case .failure(let err):
                    NSLog("OCR Recognition error: %@", err.localizedDescription)
                    NSSound.beep()
                    completion?(nil)
                }
            }
        }
    }

    // MARK: - Scrolling Capture

    public func startScrollingCapture(delay: Int? = nil, completion: ((CGImage?) -> Void)? = nil) {
        let delaySeconds = delay ?? AppSettings.shared.captureDelaySeconds
        if delaySeconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(delaySeconds)) { [weak self] in
                self?.executeScrollingCapture(completion: completion)
            }
        } else {
            executeScrollingCapture(completion: completion)
        }
    }

    private func executeScrollingCapture(completion: ((CGImage?) -> Void)? = nil) {
        AutoscrollCaptureCoordinator.shared.startAutoscrollCapture(completion: completion)
    }

    @discardableResult
    public func processScrollingFrames(_ frames: [CGImage]) -> CGImage? {
        guard let stitched = ScrollingCaptureService.shared.stitchFrames(frames) else {
            return nil
        }
        processCapturedImage(stitched)
        return stitched
    }

    public func captureFullscreen(screen: NSScreen? = nil, delay: Int? = nil) {
        let delaySeconds = delay ?? AppSettings.shared.captureDelaySeconds
        if delaySeconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(delaySeconds)) { [weak self] in
                self?.executeFullscreenCapture(screen: screen)
            }
        } else {
            executeFullscreenCapture(screen: screen)
        }
    }

    public func repeatPreviousScreenshot() {
        guard let last = lastCapture else {
            NSSound.beep()
            return
        }

        let delaySeconds = AppSettings.shared.captureDelaySeconds
        if delaySeconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(delaySeconds)) { [weak self] in
                self?.executeRepeatCapture(last)
            }
        } else {
            executeRepeatCapture(last)
        }
    }

    private func executeRepeatCapture(_ record: LastCaptureRecord) {
        switch record.mode {
        case .fullscreen:
            executeFullscreenCapture(screen: nil)

        case .region(let selRect, let screenFrame, let displayID):
            guard let fullImage = CGDisplayCreateImage(displayID) else {
                NSLog("Failed to capture display for repeated region")
                NSSound.beep()
                return
            }

            var image = CaptureService.shared.cropImage(fullImage, to: selRect, in: screenFrame.size) ?? fullImage
            if AppSettings.shared.includeCursor {
                let screen = NSScreen.screens.first {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
                } ?? NSScreen.main ?? NSScreen()
                image = CaptureService.shared.compositeCursor(on: image, screen: screen, cropRect: selRect) ?? image
            }
            processCapturedImage(image)
        }
    }

    private func executeFullscreenCapture(screen: NSScreen? = nil) {
        self.lastCapture = LastCaptureRecord(mode: .fullscreen)
        if let explicitScreen = screen {
            let displayID = CaptureService.shared.displayID(for: explicitScreen) ?? CGMainDisplayID()
            if var image = CaptureService.shared.captureFullscreen(displayID: displayID) {
                if AppSettings.shared.includeCursor {
                    image = CaptureService.shared.compositeCursor(on: image, screen: explicitScreen) ?? image
                }
                processCapturedImage(image)
            } else {
                captureFallback()
            }
        } else {
            guard let result = CaptureService.shared.captureActiveFullscreen(),
                  var image = result.image else {
                captureFallback()
                return
            }
            if AppSettings.shared.includeCursor {
                image = CaptureService.shared.compositeCursor(on: image, screen: result.screen) ?? image
            }
            processCapturedImage(image)
        }
    }

    private func captureFallback() {
        let displayID = CGMainDisplayID()
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            NSLog("Fallback CGDisplayCreateImage failed for main display ID")
            NSSound.beep()
            return
        }
        processCapturedImage(cgImage)
    }

    // MARK: - Image Processing & Fan-out Pipeline

    public func processCapturedImage(_ cgImage: CGImage) {
        let settings = AppSettings.shared
        let saveService = SaveService.shared
        let format = settings.imageFormat

        // Automatically open the editor with the captured screenshot
        DispatchQueue.main.async {
            EditorCoordinator.shared.openEditor(with: cgImage)
        }

        // Perform encoding and I/O off the main RunLoop to maintain ultra-low latency
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 1. Format-aware image encoding (PNG / JPG)
            guard let encodedData = saveService.encodeImage(cgImage, format: format, quality: settings.jpgCompressionFactor) else {
                NSLog("Failed to encode bitmap into format: %@", format.rawValue)
                return
            }

            var savedFileURL: URL?

            // 2. Disk Persistence
            if settings.saveToDisk {
                savedFileURL = self.saveImageToDisk(data: encodedData, format: format, settings: settings)
            }

            // 3. System Pasteboard Synchronization
            if settings.copyToClipboard {
                DispatchQueue.main.async {
                    saveService.copyToPasteboard(image: cgImage, fileURL: savedFileURL)
                }
            }
        }
    }

    // MARK: - File Serialization Helper

    private func saveImageToDisk(data: Data, format: ImageFormat, settings: AppSettings) -> URL? {
        let folderURL = settings.resolvedSaveDirectoryURL
        let destinationURL = SaveService.shared.resolveUniqueDestinationURL(in: folderURL, format: format)

        do {
            try SaveService.shared.saveImageData(data, to: folderURL, filename: destinationURL.lastPathComponent)
            ScreenshotHistoryService.shared.recordNewScreenshot(fileURL: destinationURL)
            NSLog("Screenshot saved to disk: %@", destinationURL.path)
            return destinationURL
        } catch {
            NSLog("Failed to persist screenshot to disk (%@): %@", destinationURL.path, error.localizedDescription)
            return nil
        }
    }
}
