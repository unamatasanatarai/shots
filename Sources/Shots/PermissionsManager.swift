import Cocoa
import CoreGraphics
import ApplicationServices

/// Centralized manager for macOS system permissions required by Shots tools.
/// Both Screen Recording (CGPreflightScreenCaptureAccess) and Accessibility (AXIsProcessTrusted)
/// must be granted before any tool (screenshot, area screenshot, ruler, color picker, OCR, scrolling) can be used.
public final class PermissionsManager {
    public static let shared = PermissionsManager()

    /// Testing overrides to deterministically simulate permission states in unit tests
    public var screenRecordingOverride: Bool?
    public var accessibilityOverride: Bool?
    public var showAlerts: Bool = true

    public private(set) var promptCallCount: Int = 0
    public private(set) var lastPromptedTool: String?

    private var isAlertShowing: Bool = false

    public init() {
        // Automatically suppress modal alerts in test runner environments
        if ProcessInfo.processInfo.processName.contains("RunSwiftTests") ||
           CommandLine.arguments.contains(where: { $0.contains("RunSwiftTests") }) {
            showAlerts = false
        }
    }

    // MARK: - Permission Queries

    public var isScreenRecordingGranted: Bool {
        if let override = screenRecordingOverride {
            return override
        }
        return CGPreflightScreenCaptureAccess()
    }

    public var isAccessibilityGranted: Bool {
        if let override = accessibilityOverride {
            return override
        }
        return AXIsProcessTrusted()
    }

    /// True strictly when BOTH Screen Recording and Accessibility permissions are granted
    public var hasRequiredPermissions: Bool {
        return isScreenRecordingGranted && isAccessibilityGranted
    }

    public var missingPermissions: [String] {
        var missing: [String] = []
        if !isScreenRecordingGranted {
            missing.append("Screen Recording")
        }
        if !isAccessibilityGranted {
            missing.append("Accessibility")
        }
        return missing
    }

    public var missingPermissionsDescription: String {
        return missingPermissions.joined(separator: " and ")
    }

    // MARK: - Launch & Request Handlers

    /// Preflight and trigger native system permission dialogs on launch if not granted
    public func checkAndRequestOnLaunch() {
        if !isScreenRecordingGranted {
            requestScreenRecordingAccess()
        }
        if !isAccessibilityGranted {
            requestAccessibilityAccess()
        }
    }

    /// Triggers macOS system prompt for Screen Recording access
    public func requestScreenRecordingAccess() {
        _ = CGRequestScreenCaptureAccess()
    }

    /// Triggers macOS system prompt for Accessibility access
    public func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openSystemSettingsForMissingPermissions() {
        if !isScreenRecordingGranted {
            requestScreenRecordingAccess()
            openScreenRecordingSettings()
        }
        if !isAccessibilityGranted {
            requestAccessibilityAccess()
            openAccessibilitySettings()
        }
    }

    // MARK: - Tool Usage Gate

    /// Verifies that both Screen Recording and Accessibility permissions are granted.
    /// If not granted, blocks tool execution, logs the blockage, and displays a permission alert.
    /// Returns `true` if all permissions are granted, `false` otherwise.
    @discardableResult
    public func ensurePermissions(for toolName: String) -> Bool {
        if hasRequiredPermissions {
            return true
        }

        promptCallCount += 1
        lastPromptedTool = toolName

        NSLog("Shots: Tool usage blocked for '%@'. Both Screen Recording and Accessibility permissions must be granted. (Screen Recording: %d, Accessibility: %d)",
              toolName, isScreenRecordingGranted ? 1 : 0, isAccessibilityGranted ? 1 : 0)

        if showAlerts {
            if Thread.isMainThread {
                presentPermissionsAlert(for: toolName)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.presentPermissionsAlert(for: toolName)
                }
            }
        }

        return false
    }

    public func presentPermissionsAlert(for toolName: String) {
        guard !isAlertShowing else { return }
        isAlertShowing = true
        defer { isAlertShowing = false }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Permissions Required"

        let screenStatus = isScreenRecordingGranted ? "Granted ✅" : "Missing ❌"
        let axStatus = isAccessibilityGranted ? "Granted ✅" : "Missing ❌"

        alert.informativeText = """
        To use \(toolName), Shots requires both Screen Recording and Accessibility permissions:

        • Screen Recording: \(screenStatus)
        • Accessibility: \(axStatus)

        Both permissions must be granted in macOS System Settings before any tools can be used.
        """

        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Open Preferences...")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            openSystemSettingsForMissingPermissions()
        case .alertSecondButtonReturn:
            PreferencesWindowController.shared.showWindow()
        default:
            break
        }
    }

    /// Reset any test overrides and prompt counters
    public func resetTestingState() {
        screenRecordingOverride = nil
        accessibilityOverride = nil
        promptCallCount = 0
        lastPromptedTool = nil
        isAlertShowing = false
    }
}
