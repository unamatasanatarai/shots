import Foundation
import ServiceManagement

public final class LaunchAtLoginService {
    public static let shared = LaunchAtLoginService()

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

    @discardableResult
    public func setLaunchAtLogin(enabled: Bool) -> Bool {
        AppSettings.shared.launchAtLogin = enabled

        if #available(macOS 13.0, *) {
            do {
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
            } catch {
                NSLog("LaunchAtLoginService: failed to update SMAppService: %@", error.localizedDescription)
                return false
            }
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
