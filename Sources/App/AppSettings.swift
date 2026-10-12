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

        let defaultFolder = (FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Screenshots").path)
            ?? ("~/Pictures/Screenshots" as NSString).expandingTildeInPath
        self.saveDirectoryPath = defaults.string(forKey: Keys.saveDirectoryPath) ?? defaultFolder

        self.copyToClipboard = defaults.object(forKey: Keys.copyToClipboard) as? Bool ?? true
        defaults.removeObject(forKey: Keys.freezeScreenOnCapture)
    }

    // MARK: - Helpers

    public var hotkeyDisplayString: String {
        KeyCodes.shortcutString(keyCode: hotkeyKeyCode, carbonMods: hotkeyModifiers)
    }

    public var resolvedSaveDirectoryURL: URL {
        let path = (saveDirectoryPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    public func resetHotkeyToDefault() {
        hotkeyKeyCode = UInt16(kVK_ANSI_1)
        hotkeyModifiers = UInt32(cmdKey | shiftKey)
    }
}
