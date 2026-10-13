import Carbon
import Cocoa
import Combine

public enum PostCaptureAction: String, CaseIterable, Identifiable {
    case saveToDisk = "saveToDisk"
    case copyToClipboard = "copyToClipboard"
    case both = "both"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .saveToDisk: return "Save to Disk Only"
        case .copyToClipboard: return "Copy to Clipboard Only"
        case .both: return "Save & Copy to Clipboard"
        }
    }
}

public enum ScrollingCaptureSpeed: String, CaseIterable, Identifiable {
    case slow = "slow"
    case normal = "normal"
    case fast = "fast"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }

    public var detailDescription: String {
        switch self {
        case .slow: return "Step: 45 px • Pause: 500 ms (Gentle, ideal for heavy web pages and smooth inertial settling)"
        case .normal: return "Step: 60 px • Pause: 350 ms (Balanced, recommended for editors and documents)"
        case .fast: return "Step: 90 px • Pause: 200 ms (Rapid capture for simple native windows)"
        }
    }

    /// Pause duration between scroll steps in microseconds for usleep
    public var stepDelayMicroseconds: useconds_t {
        switch self {
        case .slow: return 500_000
        case .normal: return 350_000
        case .fast: return 200_000
        }
    }

    /// Scroll delta in pixels per step
    public var scrollDeltaPixels: Int32 {
        switch self {
        case .slow: return 45
        case .normal: return 60
        case .fast: return 90
        }
    }
}

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    // Notification broadcast when hotkey configuration changes
    public static let hotkeyDidChangeNotification = Notification.Name("AppSettingsHotkeyDidChange")

    public enum Keys {
        public static let hotkeyKeyCode = "hotkeyKeyCode"
        public static let hotkeyModifiers = "hotkeyModifiers"
        public static let fullscreenShortcutKeyCode = "fullscreenShortcutKeyCode"
        public static let fullscreenShortcutModifiers = "fullscreenShortcutModifiers"
        public static let repeatShortcutKeyCode = "repeatShortcutKeyCode"
        public static let repeatShortcutModifiers = "repeatShortcutModifiers"
        public static let ocrShortcutKeyCode = "ocrShortcutKeyCode"
        public static let ocrShortcutModifiers = "ocrShortcutModifiers"
        public static let saveToDisk = "saveToDisk"
        public static let saveDirectoryPath = "saveDirectoryPath"
        public static let copyToClipboard = "copyToClipboard"
        public static let postCaptureAction = "postCaptureAction"
        public static let includeCursor = "includeCursor"
        public static let captureDelaySeconds = "captureDelaySeconds"
        public static let imageFormat = "imageFormat"
        public static let jpgQuality = "jpgQuality"
        public static let launchAtLogin = "launchAtLogin"
        public static let scrollingCaptureSpeed = "scrollingCaptureSpeed"
        public static let freezeScreenOnCapture = "freezeScreenOnCapture"
    }

    private let defaults: UserDefaults
    private var isSyncingActionFlags = false

    // MARK: - Hotkey Configurations

    @Published public var hotkeyKeyCode: UInt16 {
        didSet {
            defaults.set(Int(hotkeyKeyCode), forKey: Keys.hotkeyKeyCode)
            checkForShortcutConflicts()
            NotificationCenter.default.post(name: AppSettings.hotkeyDidChangeNotification, object: self)
        }
    }

    @Published public var hotkeyModifiers: UInt32 {
        didSet {
            defaults.set(Int(hotkeyModifiers), forKey: Keys.hotkeyModifiers)
            checkForShortcutConflicts()
            NotificationCenter.default.post(name: AppSettings.hotkeyDidChangeNotification, object: self)
        }
    }

    public var areaShortcutKeyCode: UInt16 {
        get { hotkeyKeyCode }
        set { hotkeyKeyCode = newValue }
    }

    public var areaShortcutModifiers: UInt32 {
        get { hotkeyModifiers }
        set { hotkeyModifiers = newValue }
    }

    @Published public var fullscreenShortcutKeyCode: UInt16 {
        didSet {
            defaults.set(Int(fullscreenShortcutKeyCode), forKey: Keys.fullscreenShortcutKeyCode)
            checkForShortcutConflicts()
            NotificationCenter.default.post(name: AppSettings.hotkeyDidChangeNotification, object: self)
        }
    }

    @Published public var fullscreenShortcutModifiers: UInt32 {
        didSet {
            defaults.set(Int(fullscreenShortcutModifiers), forKey: Keys.fullscreenShortcutModifiers)
            checkForShortcutConflicts()
            NotificationCenter.default.post(name: AppSettings.hotkeyDidChangeNotification, object: self)
        }
    }

    @Published public var repeatShortcutKeyCode: UInt16 {
        didSet {
            defaults.set(Int(repeatShortcutKeyCode), forKey: Keys.repeatShortcutKeyCode)
            checkForShortcutConflicts()
            NotificationCenter.default.post(name: AppSettings.hotkeyDidChangeNotification, object: self)
        }
    }

    @Published public var repeatShortcutModifiers: UInt32 {
        didSet {
            defaults.set(Int(repeatShortcutModifiers), forKey: Keys.repeatShortcutModifiers)
            checkForShortcutConflicts()
            NotificationCenter.default.post(name: AppSettings.hotkeyDidChangeNotification, object: self)
        }
    }

    @Published public var ocrShortcutKeyCode: UInt16 {
        didSet {
            defaults.set(Int(ocrShortcutKeyCode), forKey: Keys.ocrShortcutKeyCode)
            checkForShortcutConflicts()
            NotificationCenter.default.post(name: AppSettings.hotkeyDidChangeNotification, object: self)
        }
    }

    @Published public var ocrShortcutModifiers: UInt32 {
        didSet {
            defaults.set(Int(ocrShortcutModifiers), forKey: Keys.ocrShortcutModifiers)
            checkForShortcutConflicts()
            NotificationCenter.default.post(name: AppSettings.hotkeyDidChangeNotification, object: self)
        }
    }

    // MARK: - Post-Capture Action & Storage Toggles

    @Published public var postCaptureAction: PostCaptureAction {
        didSet {
            defaults.set(postCaptureAction.rawValue, forKey: Keys.postCaptureAction)
            guard !isSyncingActionFlags else { return }
            isSyncingActionFlags = true
            switch postCaptureAction {
            case .saveToDisk:
                saveToDisk = true
                copyToClipboard = false
            case .copyToClipboard:
                saveToDisk = false
                copyToClipboard = true
            case .both:
                saveToDisk = true
                copyToClipboard = true
            }
            isSyncingActionFlags = false
        }
    }

    @Published public var saveToDisk: Bool {
        didSet {
            defaults.set(saveToDisk, forKey: Keys.saveToDisk)
            syncPostCaptureActionFromFlags()
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
            syncPostCaptureActionFromFlags()
        }
    }

    private func syncPostCaptureActionFromFlags() {
        guard !isSyncingActionFlags else { return }
        let newAction: PostCaptureAction
        if saveToDisk && copyToClipboard {
            newAction = .both
        } else if copyToClipboard {
            newAction = .copyToClipboard
        } else {
            newAction = .saveToDisk
        }
        if postCaptureAction != newAction {
            isSyncingActionFlags = true
            postCaptureAction = newAction
            defaults.set(newAction.rawValue, forKey: Keys.postCaptureAction)
            isSyncingActionFlags = false
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

    @Published public var imageFormat: ImageFormat {
        didSet {
            defaults.set(imageFormat.rawValue, forKey: Keys.imageFormat)
        }
    }

    @Published public var jpgQuality: Int {
        didSet {
            let clamped = max(1, min(100, jpgQuality))
            if jpgQuality != clamped {
                jpgQuality = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.jpgQuality)
        }
    }

    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    @Published public var scrollingCaptureSpeed: ScrollingCaptureSpeed {
        didSet {
            defaults.set(scrollingCaptureSpeed.rawValue, forKey: Keys.scrollingCaptureSpeed)
        }
    }

    public var jpgCompressionFactor: Double {
        max(0.01, min(1.0, Double(jpgQuality) / 100.0))
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

        if defaults.object(forKey: Keys.fullscreenShortcutKeyCode) != nil {
            self.fullscreenShortcutKeyCode = UInt16(defaults.integer(forKey: Keys.fullscreenShortcutKeyCode))
        } else {
            self.fullscreenShortcutKeyCode = UInt16(kVK_ANSI_2)
        }

        if defaults.object(forKey: Keys.fullscreenShortcutModifiers) != nil {
            self.fullscreenShortcutModifiers = UInt32(defaults.integer(forKey: Keys.fullscreenShortcutModifiers))
        } else {
            self.fullscreenShortcutModifiers = defaultModifiers
        }

        if defaults.object(forKey: Keys.repeatShortcutKeyCode) != nil {
            self.repeatShortcutKeyCode = UInt16(defaults.integer(forKey: Keys.repeatShortcutKeyCode))
        } else {
            self.repeatShortcutKeyCode = UInt16(kVK_ANSI_R)
        }

        if defaults.object(forKey: Keys.repeatShortcutModifiers) != nil {
            self.repeatShortcutModifiers = UInt32(defaults.integer(forKey: Keys.repeatShortcutModifiers))
        } else {
            self.repeatShortcutModifiers = defaultModifiers
        }

        if defaults.object(forKey: Keys.ocrShortcutKeyCode) != nil {
            self.ocrShortcutKeyCode = UInt16(defaults.integer(forKey: Keys.ocrShortcutKeyCode))
        } else {
            self.ocrShortcutKeyCode = UInt16(kVK_ANSI_O)
        }

        if defaults.object(forKey: Keys.ocrShortcutModifiers) != nil {
            self.ocrShortcutModifiers = UInt32(defaults.integer(forKey: Keys.ocrShortcutModifiers))
        } else {
            self.ocrShortcutModifiers = defaultModifiers
        }

        let resolvedDefaultFolder = AppSettings.defaultSaveLocation()
        let configuredPath = defaults.string(forKey: Keys.saveDirectoryPath)
        let finalPath = (configuredPath != nil && !configuredPath!.isEmpty) ? configuredPath! : resolvedDefaultFolder
        self.saveDirectoryPath = finalPath

        if let actionRaw = defaults.string(forKey: Keys.postCaptureAction),
           let action = PostCaptureAction(rawValue: actionRaw) {
            self.postCaptureAction = action
            switch action {
            case .saveToDisk:
                self.saveToDisk = true
                self.copyToClipboard = false
            case .copyToClipboard:
                self.saveToDisk = false
                self.copyToClipboard = true
            case .both:
                self.saveToDisk = true
                self.copyToClipboard = true
            }
        } else {
            let savedDisk = defaults.object(forKey: Keys.saveToDisk) as? Bool ?? true
            let copiedClip = defaults.object(forKey: Keys.copyToClipboard) as? Bool ?? true
            self.saveToDisk = savedDisk
            self.copyToClipboard = copiedClip
            if savedDisk && copiedClip {
                self.postCaptureAction = .both
            } else if copiedClip {
                self.postCaptureAction = .copyToClipboard
            } else {
                self.postCaptureAction = .saveToDisk
            }
        }

        self.includeCursor = defaults.object(forKey: Keys.includeCursor) as? Bool ?? false
        self.captureDelaySeconds = defaults.object(forKey: Keys.captureDelaySeconds) as? Int ?? 0

        if let formatRaw = defaults.string(forKey: Keys.imageFormat),
           let format = ImageFormat(rawValue: formatRaw) {
            self.imageFormat = format
        } else {
            self.imageFormat = .png
        }

        if defaults.object(forKey: Keys.jpgQuality) != nil {
            self.jpgQuality = max(1, min(100, defaults.integer(forKey: Keys.jpgQuality)))
        } else {
            self.jpgQuality = 80
        }

        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false

        if let speedRaw = defaults.string(forKey: Keys.scrollingCaptureSpeed),
           let speed = ScrollingCaptureSpeed(rawValue: speedRaw) {
            self.scrollingCaptureSpeed = speed
        } else {
            self.scrollingCaptureSpeed = .normal
        }

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

    public var areaShortcutDisplayString: String {
        KeyCodes.shortcutString(keyCode: hotkeyKeyCode, carbonMods: hotkeyModifiers)
    }

    public var fullscreenShortcutDisplayString: String {
        KeyCodes.shortcutString(keyCode: fullscreenShortcutKeyCode, carbonMods: fullscreenShortcutModifiers)
    }

    public var repeatShortcutDisplayString: String {
        KeyCodes.shortcutString(keyCode: repeatShortcutKeyCode, carbonMods: repeatShortcutModifiers)
    }

    public var ocrShortcutDisplayString: String {
        KeyCodes.shortcutString(keyCode: ocrShortcutKeyCode, carbonMods: ocrShortcutModifiers)
    }

    public var hotkeyDisplayString: String {
        areaShortcutDisplayString
    }

    public var resolvedSaveDirectoryURL: URL {
        let path = (saveDirectoryPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        return url
    }

    public func checkForShortcutConflicts() {
        let shortcuts = [
            ("Area", hotkeyKeyCode, hotkeyModifiers),
            ("Fullscreen", fullscreenShortcutKeyCode, fullscreenShortcutModifiers),
            ("Repeat", repeatShortcutKeyCode, repeatShortcutModifiers),
            ("OCR", ocrShortcutKeyCode, ocrShortcutModifiers)
        ]

        for i in 0..<shortcuts.count {
            for j in (i + 1)..<shortcuts.count {
                if shortcuts[i].1 == shortcuts[j].1 && shortcuts[i].2 == shortcuts[j].2 {
                    isHotkeyConflict = true
                    hotkeyErrorMessage = "Shortcut conflict between \(shortcuts[i].0) and \(shortcuts[j].0)."
                    return
                }
            }
        }
        isHotkeyConflict = false
        hotkeyErrorMessage = nil
    }

    public func resetHotkeysToDefault() {
        hotkeyKeyCode = UInt16(kVK_ANSI_1)
        hotkeyModifiers = UInt32(cmdKey | shiftKey)
        fullscreenShortcutKeyCode = UInt16(kVK_ANSI_2)
        fullscreenShortcutModifiers = UInt32(cmdKey | shiftKey)
        repeatShortcutKeyCode = UInt16(kVK_ANSI_R)
        repeatShortcutModifiers = UInt32(cmdKey | shiftKey)
        ocrShortcutKeyCode = UInt16(kVK_ANSI_O)
        ocrShortcutModifiers = UInt32(cmdKey | shiftKey)
        checkForShortcutConflicts()
    }

    public func resetHotkeyToDefault() {
        resetHotkeysToDefault()
    }
}
