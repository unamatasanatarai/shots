import Cocoa
import CoreGraphics

public final class CaptureManager {
    public static let shared = CaptureManager()

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

    private func executeFullscreenCapture(screen: NSScreen? = nil) {
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

        // Perform encoding and I/O off the main RunLoop to maintain ultra-low latency
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 1. Format-aware image encoding (PNG / JPG)
            guard let encodedData = saveService.encodeImage(cgImage, format: format) else {
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
            NSLog("Screenshot saved to disk: %@", destinationURL.path)
            return destinationURL
        } catch {
            NSLog("Failed to persist screenshot to disk (%@): %@", destinationURL.path, error.localizedDescription)
            return nil
        }
    }
}
