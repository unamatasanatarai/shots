import Cocoa
import CoreGraphics

public final class CaptureManager {
    public static let shared = CaptureManager()

    private init() {}

    // MARK: - Capture Triggers

    public func startRegionCapture() {
        RegionSelectionCoordinator.shared.startSelection { [weak self] capturedImage in
            guard let image = capturedImage else { return }
            self?.processCapturedImage(image)
        }
    }

    public func captureFullscreen(screen: NSScreen? = nil) {
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

        // Perform encoding and I/O off the main RunLoop to maintain ultra-low latency
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 1. Lossless PNG rasterization via SaveService
            guard let pngData = saveService.encodePNG(image: cgImage) else {
                NSLog("Failed to encode bitmap into lossless PNG format")
                return
            }

            var savedFileURL: URL?

            // 2. Disk Persistence
            if settings.saveToDisk {
                savedFileURL = self.savePNGToDisk(data: pngData, settings: settings)
            }

            // 3. System Pasteboard Synchronization
            if settings.copyToClipboard {
                DispatchQueue.main.async {
                    saveService.copyToPasteboard(image: cgImage, pngData: pngData, fileURL: savedFileURL)
                }
            }
        }
    }

    // MARK: - File Serialization Helper

    private func savePNGToDisk(data: Data, settings: AppSettings) -> URL? {
        let folderURL = settings.resolvedSaveDirectoryURL
        let destinationURL = SaveService.shared.resolveUniqueDestinationURL(in: folderURL, format: .png)

        do {
            try SaveService.shared.saveImageData(data, to: folderURL, filename: destinationURL.lastPathComponent)
            NSLog("Lossless screenshot saved to disk: %@", destinationURL.path)
            return destinationURL
        } catch {
            NSLog("Failed to persist screenshot to disk (%@): %@", destinationURL.path, error.localizedDescription)
            return nil
        }
    }
}
