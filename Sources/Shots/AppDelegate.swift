import Cocoa

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce accessory / agent mode: no icon in macOS Dock or Cmd+Tab switcher
        NSApp.setActivationPolicy(.accessory)

        // Preflight Screen Recording TCC permission
        _ = CGPreflightScreenCaptureAccess()

        // Preflight Accessibility permission (required for consuming CGEventTap
        // that swallows mouse events during live region selection)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // Eagerly initialize persistent configuration
        _ = AppSettings.shared

        // Wire global hardware hotkey triggers to capture actions
        HotKeyManager.shared.onAreaCaptureTrigger = {
            CaptureManager.shared.startRegionCapture()
        }
        HotKeyManager.shared.onFullscreenCaptureTrigger = {
            CaptureManager.shared.captureFullscreen()
        }
        HotKeyManager.shared.onRepeatCaptureTrigger = {
            CaptureManager.shared.repeatPreviousScreenshot()
        }
        HotKeyManager.shared.onOCRCaptureTrigger = {
            CaptureManager.shared.startOCRRecognition()
        }
        HotKeyManager.shared.onScrollingCaptureTrigger = {
            CaptureManager.shared.startScrollingCapture()
        }
        HotKeyManager.shared.onTrigger = {
            CaptureManager.shared.startRegionCapture()
        }

        // Initialize status bar controller and dynamic menu
        statusBarController = StatusBarController()

        // Handle CLI or initial test arguments
        if CommandLine.arguments.contains("--test-impact") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                ImpactLauncher.shared.openTestImage()
            }
        } else if let impactIdx = CommandLine.arguments.firstIndex(of: "--impact"),
                  impactIdx + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[impactIdx + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                ImpactLauncher.shared.openImageFile(url: URL(fileURLWithPath: path))
            }
        }

        NSLog("Shots app initialized successfully. Global hotkey active: %@", AppSettings.shared.hotkeyDisplayString)
    }

    public func application(_ application: NSApplication, openFile filename: String) -> Bool {
        ImpactLauncher.shared.openImageFile(url: URL(fileURLWithPath: filename))
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterHotkey()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Run continuously in menu bar status item area
        return false
    }
}
