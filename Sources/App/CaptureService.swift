import Cocoa
import CoreGraphics

public final class CaptureService {
    public static let shared = CaptureService()

    public init() {}

    // MARK: - Active Screen & Display Resolution

    /// Determines the active screen based on the current mouse location, falling back to NSScreen.main or screens.first.
    public func activeScreen() -> NSScreen? {
        let mouseLoc = NSEvent.mouseLocation
        if let screenWithMouse = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) {
            return screenWithMouse
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Retrieves the CGDirectDisplayID for an NSScreen.
    public func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    // MARK: - Multi-Display Coordinate Translation

    /// Converts an AppKit screen point (origin bottom-left of primary screen) to CoreGraphics coordinates (origin top-left of primary display).
    public func coreGraphicsPoint(from appKitPoint: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: appKitPoint.x, y: primaryHeight - appKitPoint.y)
    }

    /// Converts a CoreGraphics point (origin top-left of primary display) to AppKit screen coordinates.
    public func appKitPoint(from cgPoint: CGPoint) -> NSPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSPoint(x: cgPoint.x, y: primaryHeight - cgPoint.y)
    }

    /// Finds which NSScreen contains the given AppKit point across all connected displays.
    public func screen(containing appKitPoint: NSPoint) -> NSScreen? {
        return NSScreen.screens.first(where: { $0.frame.contains(appKitPoint) })
    }

    /// Finds which NSScreen contains the given CoreGraphics point across all connected displays.
    public func screen(containingCGPoint cgPoint: CGPoint) -> NSScreen? {
        let appKitPt = appKitPoint(from: cgPoint)
        return screen(containing: appKitPt)
    }

    // MARK: - Fullscreen Capture

    /// Captures the full display corresponding to the given display ID.
    public func captureFullscreen(displayID: CGDirectDisplayID) -> CGImage? {
        return CGDisplayCreateImage(displayID)
    }

    /// Captures the entire active display (where the mouse cursor is located).
    public func captureActiveFullscreen() -> (image: CGImage?, screen: NSScreen, displayID: CGDirectDisplayID)? {
        guard let screen = activeScreen() else {
            let mainDisplayID = CGMainDisplayID()
            let image = CGDisplayCreateImage(mainDisplayID)
            return (image, NSScreen.main ?? NSScreen(), mainDisplayID)
        }

        let targetDisplayID = displayID(for: screen) ?? CGMainDisplayID()
        let image = CGDisplayCreateImage(targetDisplayID) ?? CGDisplayCreateImage(CGMainDisplayID())
        return (image, screen, targetDisplayID)
    }

    // MARK: - Area & Region Cropping

    /// Normalizes two arbitrary points into a positive width/height NSRect.
    public func normalizedRect(from p1: NSPoint, to p2: NSPoint) -> NSRect {
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        let width = abs(p2.x - p1.x)
        let height = abs(p2.y - p1.y)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Crops a full display CGImage to the selected screen region, handling Retina scale and coordinate flipping.
    public func cropImage(_ image: CGImage, to selRect: NSRect, in viewSize: NSSize) -> CGImage? {
        guard viewSize.width > 0 && viewSize.height > 0 else { return nil }

        let scaleX = CGFloat(image.width) / viewSize.width
        let scaleY = CGFloat(image.height) / viewSize.height

        let cropX = selRect.minX * scaleX
        let cropY = (viewSize.height - selRect.maxY) * scaleY
        let cropW = selRect.width * scaleX
        let cropH = selRect.height * scaleY

        let cropRect = CGRect(
            x: max(0, cropX),
            y: max(0, cropY),
            width: min(cropW, CGFloat(image.width) - cropX),
            height: min(cropH, CGFloat(image.height) - cropY)
        )

        guard cropRect.width > 0 && cropRect.height > 0 else { return nil }
        return image.cropping(to: cropRect)
    }
}
