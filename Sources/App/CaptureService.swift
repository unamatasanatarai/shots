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
}
