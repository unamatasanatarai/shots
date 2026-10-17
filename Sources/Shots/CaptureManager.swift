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

    private let lock = NSLock()
    private var _lastCapture: LastCaptureRecord?

    public var lastCapture: LastCaptureRecord? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _lastCapture
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _lastCapture = newValue
        }
    }

    private init() {}

    // MARK: - Capture Triggers

    public func startRegionCapture(delay: Int? = nil) {
        guard PermissionsManager.shared.ensurePermissions(for: "Area Screenshot") else { return }
        let delaySeconds = delay ?? AppSettings.shared.captureDelaySeconds
        executeRegionCapture(delaySeconds: delaySeconds)
    }

    private func executeRegionCapture(delaySeconds: Int = 0) {
        guard PermissionsManager.shared.ensurePermissions(for: "Area Screenshot") else { return }
        RegionSelectionCoordinator.shared.startSelection(mode: .area, delaySeconds: delaySeconds) { [weak self] capturedImage in
            guard let image = capturedImage else { return }
            self?.processCapturedImage(image)
        }
    }

    public func startOCRRecognition(delay: Int? = nil, completion: ((RecognitionItem?) -> Void)? = nil) {
        guard PermissionsManager.shared.ensurePermissions(for: "OCR Recognition") else {
            completion?(nil)
            return
        }
        executeOCRRecognition(completion: completion)
    }

    private func executeOCRRecognition(completion: ((RecognitionItem?) -> Void)? = nil) {
        guard PermissionsManager.shared.ensurePermissions(for: "OCR Recognition") else {
            completion?(nil)
            return
        }
        RegionSelectionCoordinator.shared.startSelection(mode: .ocr) { capturedImage in
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
                    }
                    completion?(item)
                case .failure(let err):
                    NSLog("OCR Recognition error: %@", err.localizedDescription)
                    completion?(nil)
                }
            }
        }
    }

    // MARK: - Screen Ruler & Color Picker

    public func startRuler(delay: Int? = nil, completion: ((String?) -> Void)? = nil) {
        guard PermissionsManager.shared.ensurePermissions(for: "Screen Ruler") else {
            completion?(nil)
            return
        }
        executeRuler(completion: completion)
    }

    private func executeRuler(completion: ((String?) -> Void)? = nil) {
        guard PermissionsManager.shared.ensurePermissions(for: "Screen Ruler") else {
            completion?(nil)
            return
        }
        RegionSelectionCoordinator.shared.startRuler(completion: completion)
    }

    public func startColorPicker(delay: Int? = nil, completion: ((String?) -> Void)? = nil) {
        guard PermissionsManager.shared.ensurePermissions(for: "Color Picker") else {
            completion?(nil)
            return
        }
        executeColorPicker(completion: completion)
    }

    private func executeColorPicker(completion: ((String?) -> Void)? = nil) {
        guard PermissionsManager.shared.ensurePermissions(for: "Color Picker") else {
            completion?(nil)
            return
        }
        RegionSelectionCoordinator.shared.startColorPicker(completion: completion)
    }

    // MARK: - Scrolling Capture

    public func startScrollingCapture(delay: Int? = nil, completion: ((CGImage?) -> Void)? = nil) {
        guard PermissionsManager.shared.ensurePermissions(for: "Scrolling Capture") else {
            completion?(nil)
            return
        }
        executeScrollingCapture(completion: completion)
    }

    private func executeScrollingCapture(completion: ((CGImage?) -> Void)? = nil) {
        guard PermissionsManager.shared.ensurePermissions(for: "Scrolling Capture") else {
            completion?(nil)
            return
        }
        AutoscrollCaptureCoordinator.shared.startAutoscrollCapture(completion: completion)
    }

    @discardableResult
    public func processScrollingFrames(_ frames: [CGImage], dispatch: Bool = false) -> CGImage? {
        guard let stitched = ScrollingCaptureService.shared.stitchFrames(frames) else {
            return nil
        }
        if dispatch {
            processCapturedImage(stitched)
        }
        return stitched
    }

    public func captureFullscreen(screen: NSScreen? = nil, delay: Int? = nil) {
        guard PermissionsManager.shared.ensurePermissions(for: "Fullscreen Screenshot") else { return }
        let delaySeconds = delay ?? AppSettings.shared.captureDelaySeconds
        if delaySeconds > 0 {
            let targetScreen = screen ?? CaptureService.shared.activeScreen() ?? NSScreen.main
            CountdownHUDController.shared.startCountdown(seconds: delaySeconds, screen: targetScreen) { [weak self] in
                self?.executeFullscreenCapture(screen: screen)
            }
        } else {
            executeFullscreenCapture(screen: screen)
        }
    }

    public func repeatPreviousScreenshot() {
        guard PermissionsManager.shared.ensurePermissions(for: "Repeat Screenshot") else { return }
        guard let last = lastCapture else {
            return
        }

        let delaySeconds = AppSettings.shared.captureDelaySeconds
        if delaySeconds > 0 {
            let targetScreen: NSScreen? = {
                switch last.mode {
                case .fullscreen:
                    return CaptureService.shared.activeScreen() ?? NSScreen.main
                case .region(_, let screenFrame, _):
                    return NSScreen.screens.first { $0.frame == screenFrame } ?? NSScreen.main
                }
            }()
            CountdownHUDController.shared.startCountdown(seconds: delaySeconds, screen: targetScreen) { [weak self] in
                self?.executeRepeatCapture(last)
            }
        } else {
            executeRepeatCapture(last)
        }
    }

    private func executeRepeatCapture(_ record: LastCaptureRecord) {
        guard PermissionsManager.shared.ensurePermissions(for: "Repeat Screenshot") else { return }
        switch record.mode {
        case .fullscreen:
            executeFullscreenCapture(screen: nil)

        case .region(let selRect, let screenFrame, let displayID):
            guard let fullImage = CGDisplayCreateImage(displayID) else {
                NSLog("Failed to capture display for repeated region")
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
        guard PermissionsManager.shared.ensurePermissions(for: "Fullscreen Screenshot") else { return }
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
            return
        }
        processCapturedImage(cgImage)
    }

    // MARK: - Image Processing & Fan-out Pipeline

    public func processCapturedImage(_ cgImage: CGImage) {
        let settings = AppSettings.shared
        let saveService = SaveService.shared
        let format = settings.imageFormat

        // Perform encoding, save to destination, and launch Impact with the fresh file
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 1. Format-aware image encoding (PNG / JPG)
            guard let encodedData = saveService.encodeImage(cgImage, format: format, quality: settings.jpgCompressionFactor) else {
                NSLog("Failed to encode bitmap into format: %@", format.rawValue)
                return
            }

            // 2. Disk Persistence: save to destination folder
            let savedFileURL = self.saveImageToDisk(data: encodedData, format: format, settings: settings)

            // 3. Launch Impact with the freshly saved file (or fallback to memory image if disk save failed)
            DispatchQueue.main.async {
                if let fileURL = savedFileURL {
                    ImpactLauncher.shared.openImageFile(url: fileURL)
                } else {
                    ImpactLauncher.shared.openImpact(with: cgImage)
                }
            }

            // 4. System Pasteboard Synchronization
            if settings.copyToClipboard {
                DispatchQueue.main.async {
                    saveService.copyToPasteboard(image: cgImage, pngData: format == .png ? encodedData : nil, fileURL: savedFileURL)
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
