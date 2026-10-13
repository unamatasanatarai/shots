import Carbon
import Cocoa
import Combine

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    // Notification broadcast when hotkey configuration changes
    public static let hotkeyDidChangeNotification = Notification.Name("AppSettingsHotkeyDidChange")

    public enum Keys {
        public static let hotkeyKeyCode = "hotkeyKeyCode"
        public static let hotkeyModifiers = "hotkeyModifiers"
        public static let saveToDisk = "saveToDisk"
        public static let saveDirectoryPath = "saveDirectoryPath"
        public static let copyToClipboard = "copyToClipboard"
        public static let includeCursor = "includeCursor"
        public static let captureDelaySeconds = "captureDelaySeconds"
        public static let freezeScreenOnCapture = "freezeScreenOnCapture"
    }

    private let defaults: UserDefaults

    // MARK: - Hotkey Configuration

    @Published public var hotkeyKeyCode: UInt16 {
        didSet {
            defaults.set(Int(hotkeyKeyCode), forKey: Keys.hotkeyKeyCode)
            NotificationCenter.default.post(name: AppSettings.hotkeyDidChangeNotification, object: self)
        }
    }

    @Published public var hotkeyModifiers: UInt32 {
        didSet {
            defaults.set(Int(hotkeyModifiers), forKey: Keys.hotkeyModifiers)
            NotificationCenter.default.post(name: AppSettings.hotkeyDidChangeNotification, object: self)
        }
    }

    // MARK: - Storage and Clipboard Toggles

    @Published public var saveToDisk: Bool {
        didSet {
            defaults.set(saveToDisk, forKey: Keys.saveToDisk)
        }
    }

    @Published public var saveDirectoryPath: String {
        didSet {
            defaults.set(saveDirectoryPath, forKey: Keys.saveDirectoryPath)
        }
    }

    @Published public var copyToClipboard: Bool {
        didSet {
            defaults.set(copyToClipboard, forKey: Keys.copyToClipboard)
        }
    }

    @Published public var includeCursor: Bool {
        didSet {
            defaults.set(includeCursor, forKey: Keys.includeCursor)
        }
    }

    @Published public var captureDelaySeconds: Int {
        didSet {
            defaults.set(captureDelaySeconds, forKey: Keys.captureDelaySeconds)
        }
    }


    // MARK: - Validation & Conflict States

    @Published public var isHotkeyConflict: Bool = false
    @Published public var hotkeyErrorMessage: String? = nil

    // MARK: - Initialization

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Default: Command + Shift + 1 (keyCode 18)
        let defaultKeyCode = UInt16(kVK_ANSI_1)
        let defaultModifiers = UInt32(cmdKey | shiftKey)

        if defaults.object(forKey: Keys.hotkeyKeyCode) != nil {
            self.hotkeyKeyCode = UInt16(defaults.integer(forKey: Keys.hotkeyKeyCode))
        } else {
            self.hotkeyKeyCode = defaultKeyCode
        }

        if defaults.object(forKey: Keys.hotkeyModifiers) != nil {
            self.hotkeyModifiers = UInt32(defaults.integer(forKey: Keys.hotkeyModifiers))
        } else {
            self.hotkeyModifiers = defaultModifiers
        }

        self.saveToDisk = defaults.object(forKey: Keys.saveToDisk) as? Bool ?? true

        let resolvedDefaultFolder = AppSettings.defaultSaveLocation()
        let configuredPath = defaults.string(forKey: Keys.saveDirectoryPath)
        let finalPath = (configuredPath != nil && !configuredPath!.isEmpty) ? configuredPath! : resolvedDefaultFolder
        self.saveDirectoryPath = finalPath

        self.copyToClipboard = defaults.object(forKey: Keys.copyToClipboard) as? Bool ?? true
        self.includeCursor = defaults.object(forKey: Keys.includeCursor) as? Bool ?? false
        self.captureDelaySeconds = defaults.object(forKey: Keys.captureDelaySeconds) as? Int ?? 0
        defaults.removeObject(forKey: Keys.freezeScreenOnCapture)

        // Ensure default directory is created immediately if missing
        _ = self.resolvedSaveDirectoryURL
    }

    // MARK: - Helpers

    /// Resolves default save location: queries system screencapture preferences if available, otherwise ~/Pictures/shots.
    public static func defaultSaveLocation() -> String {
        // 1. Try reading system preferences from com.apple.screencapture
        if let systemLoc = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !systemLoc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (systemLoc as NSString).expandingTildeInPath
            return expanded
        }
        if let screencaptureDefaults = UserDefaults(suiteName: "com.apple.screencapture"),
           let systemLoc = screencaptureDefaults.string(forKey: "location"),
           !systemLoc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (systemLoc as NSString).expandingTildeInPath
            return expanded
        }

        // 2. Otherwise default to ~/Pictures/shots
        if let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            return picturesURL.appendingPathComponent("shots").path
        }
        return ("~/Pictures/shots" as NSString).expandingTildeInPath
    }

    public var hotkeyDisplayString: String {
        KeyCodes.shortcutString(keyCode: hotkeyKeyCode, carbonMods: hotkeyModifiers)
    }

    public var resolvedSaveDirectoryURL: URL {
        let path = (saveDirectoryPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        return url
    }

    public func resetHotkeyToDefault() {
        hotkeyKeyCode = UInt16(kVK_ANSI_1)
        hotkeyModifiers = UInt32(cmdKey | shiftKey)
    }
}
