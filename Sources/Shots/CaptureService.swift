import Cocoa
import CoreGraphics

public final class CaptureService {
    public static let shared = CaptureService()
    private static let colorSpaceSRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

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

    // MARK: - Region Capture

    /// Captures only the selected region of a display (selRect in view coordinates, origin bottom-left).
    /// Unlike capturing the full display and cropping, no full-display buffer is allocated or kept alive
    /// by the cropped image. Falls back to crop-from-full-display if the region capture fails.
    public func captureRegion(displayID: CGDirectDisplayID, selRect: NSRect, in viewSize: NSSize) -> CGImage? {
        guard viewSize.width > 0 && viewSize.height > 0 && selRect.width > 0 && selRect.height > 0 else { return nil }
        // Display space: points relative to the display, origin top-left
        let displayRect = CGRect(
            x: selRect.minX,
            y: viewSize.height - selRect.maxY,
            width: selRect.width,
            height: selRect.height
        ).intersection(CGRect(origin: .zero, size: viewSize))
        guard !displayRect.isNull && displayRect.width > 0 && displayRect.height > 0 else { return nil }
        // Whole points are captured; trackpad selections can be fractional, so the result is then cropped to
        // the exact pixels the full-display crop would give (the crop only retains this small capture)
        let pointRect = displayRect.integral
        if let captured = CGDisplayCreateImage(displayID, rect: pointRect) {
            guard pointRect != displayRect else { return captured }
            let scaleX = CGFloat(captured.width) / pointRect.width
            let scaleY = CGFloat(captured.height) / pointRect.height
            let pixelRect = CGRect(
                x: (displayRect.minX - pointRect.minX) * scaleX,
                y: (displayRect.minY - pointRect.minY) * scaleY,
                width: displayRect.width * scaleX,
                height: displayRect.height * scaleY
            )
            return captured.cropping(to: pixelRect) ?? captured
        }
        return CGDisplayCreateImage(displayID).flatMap { cropImage($0, to: selRect, in: viewSize) }
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
        guard viewSize.width > 0 && viewSize.height > 0 && selRect.width > 0 && selRect.height > 0 else { return nil }

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

    // MARK: - Cursor Compositing

    /// Overlays the mouse cursor onto a captured CGImage if within bounds, respecting screen coordinates and Retina scale.
    public func compositeCursor(
        on baseImage: CGImage,
        screen: NSScreen,
        cropRect: NSRect? = nil,
        mouseLocation: NSPoint = NSEvent.mouseLocation,
        cursor: NSCursor = NSCursor.current
    ) -> CGImage? {
        let effectiveCursor = (cursor.image.size.width <= 1 && cursor.image.size.height <= 1) ? NSCursor.arrow : cursor
        guard effectiveCursor.image.size.width > 0 && effectiveCursor.image.size.height > 0 else {
            return baseImage
        }

        let screenFrame = screen.frame
        let targetLogicalRect = cropRect.map {
            NSRect(
                x: screenFrame.origin.x + $0.origin.x,
                y: screenFrame.origin.y + $0.origin.y,
                width: $0.width,
                height: $0.height
            )
        } ?? screenFrame

        // Check if cursor location is inside the captured rectangle
        guard targetLogicalRect.contains(mouseLocation) else {
            return baseImage
        }

        let width = baseImage.width
        let height = baseImage.height
        // Keep the capture's color space and native BGRA layout: drawing the base is then a plain copy
        let colorSpace = baseImage.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CaptureService.colorSpaceSRGB
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return baseImage
        }

        // Draw the base image
        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Compute cursor position in target pixel coordinates
        let scaleX = CGFloat(width) / targetLogicalRect.width
        let scaleY = CGFloat(height) / targetLogicalRect.height

        let cursorImage = effectiveCursor.image
        let hotSpot = effectiveCursor.hotSpot

        // Logical position relative to bottom-left of targetLogicalRect
        let cursorLogicalX = (mouseLocation.x - targetLogicalRect.origin.x) - hotSpot.x
        let cursorLogicalY = (mouseLocation.y - targetLogicalRect.origin.y) - (cursorImage.size.height - hotSpot.y)

        let cursorPixelRect = CGRect(
            x: cursorLogicalX * scaleX,
            y: cursorLogicalY * scaleY,
            width: cursorImage.size.width * scaleX,
            height: cursorImage.size.height * scaleY
        )

        if let cursorCGImage = cursorImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cursorCGImage, in: cursorPixelRect)
        }

        return context.makeImage() ?? baseImage
    }
}
