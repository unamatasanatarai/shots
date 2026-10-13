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
        let targetScreen: NSScreen
        if let screen = screen {
            targetScreen = screen
        } else {
            let mouseLoc = NSEvent.mouseLocation
            targetScreen = NSScreen.screens.first { $0.frame.contains(mouseLoc) }
                ?? NSScreen.main
                ?? NSScreen.screens.first
                ?? NSScreen()
        }

        guard let screenNumber = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            NSLog("Could not obtain display ID for screen; using fallback display ID")
            captureFallback()
            return
        }

        guard let cgImage = CGDisplayCreateImage(screenNumber) else {
            NSLog("CGDisplayCreateImage failed for display ID %u; falling back", screenNumber)
            captureFallback()
            return
        }

        processCapturedImage(cgImage)
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let dateString = formatter.string(from: Date())
        let baseFilename = "Screenshot \(dateString)"

        let folderURL = settings.resolvedSaveDirectoryURL
        var destinationURL = folderURL.appendingPathComponent("\(baseFilename).png")

        // Handle collision within the same second
        var collisionIndex = 1
        while FileManager.default.fileExists(atPath: destinationURL.path) {
            destinationURL = folderURL.appendingPathComponent("\(baseFilename) \(collisionIndex).png")
            collisionIndex += 1
        }

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
