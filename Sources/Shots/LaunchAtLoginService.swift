import Foundation
import ServiceManagement

public final class LaunchAtLoginService {
    public static let shared = LaunchAtLoginService()

    /// Test hook: replaces the system login-item call. Returns success or throws.
    var backendOverride: ((Bool) throws -> Bool)?

    public var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                let status = SMAppService.mainApp.status
                if status == .enabled {
                    return true
                }
            }
            return AppSettings.shared.launchAtLogin
        }
        set {
            _ = setLaunchAtLogin(enabled: newValue)
        }
    }

    /// Registers/unregisters the login item. The preference is persisted only when the system call
    /// succeeds, so a failed registration never leaves the toggle claiming "on".
    @discardableResult
    public func setLaunchAtLogin(enabled: Bool) -> Bool {
        let succeeded: Bool
        do {
            succeeded = try (backendOverride ?? Self.systemSetLaunchAtLogin)(enabled)
        } catch {
            NSLog("LaunchAtLoginService: failed to update login item: %@", error.localizedDescription)
            succeeded = false
        }

        if succeeded {
            AppSettings.shared.launchAtLogin = enabled
        }
        return succeeded
    }

    /// Makes the stored preference match the system: the user can remove the login item in System Settings,
    /// or leave it awaiting approval, while the stored flag still says "on" (macOS 13+; older systems have no
    /// status API)
    public func reconcileWithSystem() {
        guard backendOverride == nil else { return }
        if #available(macOS 13.0, *) {
            let actual = SMAppService.mainApp.status == .enabled
            if AppSettings.shared.launchAtLogin != actual {
                AppSettings.shared.launchAtLogin = actual
            }
        }
    }

    private static func systemSetLaunchAtLogin(_ enabled: Bool) throws -> Bool {
        if #available(macOS 13.0, *) {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } else {
            #if !targetEnvironment(simulator)
            if let bundleID = Bundle.main.bundleIdentifier {
                return SMLoginItemSetEnabled(bundleID as CFString, enabled)
            }
            #endif
            return true
        }
    }
}
