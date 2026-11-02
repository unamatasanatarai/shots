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
        case .slow: return "Step: 60 px • Pause: 350 ms (Gentle, ideal for heavy web pages and smooth inertial settling)"
        case .normal: return "Step: 90 px • Pause: 200 ms (Balanced, recommended for editors and documents)"
        case .fast: return "Step: 120 px • Pause: 100 ms (Ultra-rapid capture for fast scrolling feeds and native windows)"
        }
    }

    /// Pause duration between scroll steps in microseconds for usleep
    public var stepDelayMicroseconds: useconds_t {
        switch self {
        case .slow: return 350_000
        case .normal: return 200_000
        case .fast: return 100_000
        }
    }

    /// Scroll delta in pixels per step
    public var scrollDeltaPixels: Int32 {
        switch self {
        case .slow: return 60
        case .normal: return 90
        case .fast: return 120
        }
    }

    /// Scroll delta adapted to the selected region: at most half its height, so consecutive
    /// frames always overlap enough to stitch (a 50pt-tall region scrolls 25pt per step)
    public func scrollDeltaPixels(forRegionHeight regionHeight: CGFloat) -> Int32 {
        let halfRegion = Int32(max(4.0, (regionHeight / 2.0).rounded(.down)))
        return min(scrollDeltaPixels, halfRegion)
    }
}

/// Immutable copy of the settings the capture pipeline reads off the main thread.
public struct CaptureSettingsSnapshot: Equatable {
    public var saveDirectoryPath: String
    public var imageFormat: ImageFormat
    public var copyToClipboard: Bool
    public var jpgQuality: Int
    public var scrollingCaptureSpeed: ScrollingCaptureSpeed

    public var jpgCompressionFactor: Double {
        max(0.01, min(1.0, Double(jpgQuality) / 100.0))
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
        public static let scrollingShortcutKeyCode = "scrollingShortcutKeyCode"
        public static let scrollingShortcutModifiers = "scrollingShortcutModifiers"
        public static let rulerShortcutKeyCode = "rulerShortcutKeyCode"
        public static let rulerShortcutModifiers = "rulerShortcutModifiers"
        public static let colorPickerShortcutKeyCode = "colorPickerShortcutKeyCode"
        public static let colorPickerShortcutModifiers = "colorPickerShortcutModifiers"
        public static let globalHotkeysEnabled = "globalHotkeysEnabled"
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
    }

    private let defaults: UserDefaults
    private var isSyncingActionFlags = false

    // MARK: - Thread-safe mirror
    // @Published storage is main-thread only. Values the capture pipeline needs on background
    // queues (save folder, format, quality, clipboard flag, scroll speed) are mirrored here
    // under a lock, together with the resolved save-folder URL cache.
    private let threadSafeLock = NSLock()
    private var _snapshot = CaptureSettingsSnapshot(
        saveDirectoryPath: "", imageFormat: .png, copyToClipboard: true, jpgQuality: 80, scrollingCaptureSpeed: .normal
    )
    private var _cachedSaveDirectoryURL: URL?

    private func updateSnapshot(_ mutate: (inout CaptureSettingsSnapshot) -> Void) {
        threadSafeLock.lock()
        let oldPath = _snapshot.saveDirectoryPath
        mutate(&_snapshot)
        if _snapshot.saveDirectoryPath != oldPath {
            _cachedSaveDirectoryURL = nil
        }
        threadSafeLock.unlock()
    }

    /// Thread-safe copy of the capture-related settings; safe to call from any queue.
    public var captureSnapshot: CaptureSettingsSnapshot {
        threadSafeLock.lock()
        defer { threadSafeLock.unlock() }
        return _snapshot
    }

    /// Decodes a stored key code, falling back when the stored integer is out of UInt16 range
    /// (a corrupt or hand-edited plist must not trap at launch).
    static func storedKeyCode(_ defaults: UserDefaults, key: String, fallback: UInt16) -> UInt16 {
        UInt16(exactly: defaults.integer(forKey: key)) ?? fallback
    }

    /// Carbon modifier bits the shortcut recorder can produce (see KeyCodes.carbonModifiers).
    static let validModifierMask = UInt32(cmdKey | shiftKey | optionKey | controlKey)

    /// Decodes stored Carbon modifiers, falling back when the stored integer is out of UInt32 range
    /// or carries bits that are not shortcut modifiers.
    static func storedModifiers(_ defaults: UserDefaults, key: String, fallback: UInt32) -> UInt32 {
        guard let value = UInt32(exactly: defaults.integer(forKey: key)),
              value & ~validModifierMask == 0 else {
            return fallback
        }
        return value
    }

    // MARK: - Hotkey Configurations

    private var hotkeyBatchDepth = 0
    private var hotkeyBatchDirty = false

    /// Validates and broadcasts a hotkey change, or defers it while a batch update is running
    private func hotkeyConfigurationDidChange() {
        if hotkeyBatchDepth > 0 {
            hotkeyBatchDirty = true
            return
        }
        checkForShortcutConflicts()
        NotificationCenter.default.post(name: AppSettings.hotkeyDidChangeNotification, object: self)
    }

    /// Applies several hotkey changes with a single conflict check and a single change notification
    /// (so observers such as HotkeyManager re-register all hotkeys once, not once per property)
    public func performHotkeyBatchUpdate(_ updates: () -> Void) {
        hotkeyBatchDepth += 1
        updates()
        hotkeyBatchDepth -= 1
        guard hotkeyBatchDepth == 0 else { return }
        let dirty = hotkeyBatchDirty
        hotkeyBatchDirty = false
        checkForShortcutConflicts()
        if dirty {
            NotificationCenter.default.post(name: AppSettings.hotkeyDidChangeNotification, object: self)
        }
    }

    @Published public var globalHotkeysEnabled: Bool {
        didSet {
            defaults.set(globalHotkeysEnabled, forKey: Keys.globalHotkeysEnabled)
            hotkeyConfigurationDidChange()
        }
    }

    @Published public var hotkeyKeyCode: UInt16 {
        didSet {
            defaults.set(Int(hotkeyKeyCode), forKey: Keys.hotkeyKeyCode)
            hotkeyConfigurationDidChange()
        }
    }

    @Published public var hotkeyModifiers: UInt32 {
        didSet {
            defaults.set(Int(hotkeyModifiers), forKey: Keys.hotkeyModifiers)
            hotkeyConfigurationDidChange()
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
            hotkeyConfigurationDidChange()
        }
    }

    @Published public var fullscreenShortcutModifiers: UInt32 {
        didSet {
            defaults.set(Int(fullscreenShortcutModifiers), forKey: Keys.fullscreenShortcutModifiers)
            hotkeyConfigurationDidChange()
        }
    }

    @Published public var repeatShortcutKeyCode: UInt16 {
        didSet {
            defaults.set(Int(repeatShortcutKeyCode), forKey: Keys.repeatShortcutKeyCode)
            hotkeyConfigurationDidChange()
        }
    }

    @Published public var repeatShortcutModifiers: UInt32 {
        didSet {
            defaults.set(Int(repeatShortcutModifiers), forKey: Keys.repeatShortcutModifiers)
            hotkeyConfigurationDidChange()
        }
    }

    @Published public var ocrShortcutKeyCode: UInt16 {
        didSet {
            defaults.set(Int(ocrShortcutKeyCode), forKey: Keys.ocrShortcutKeyCode)
            hotkeyConfigurationDidChange()
        }
    }

    @Published public var ocrShortcutModifiers: UInt32 {
        didSet {
            defaults.set(Int(ocrShortcutModifiers), forKey: Keys.ocrShortcutModifiers)
            hotkeyConfigurationDidChange()
        }
    }

    @Published public var scrollingShortcutKeyCode: UInt16 {
        didSet {
            defaults.set(Int(scrollingShortcutKeyCode), forKey: Keys.scrollingShortcutKeyCode)
            hotkeyConfigurationDidChange()
        }
    }

    @Published public var scrollingShortcutModifiers: UInt32 {
        didSet {
            defaults.set(Int(scrollingShortcutModifiers), forKey: Keys.scrollingShortcutModifiers)
            hotkeyConfigurationDidChange()
        }
    }

    @Published public var rulerShortcutKeyCode: UInt16 {
        didSet {
            defaults.set(Int(rulerShortcutKeyCode), forKey: Keys.rulerShortcutKeyCode)
            hotkeyConfigurationDidChange()
        }
    }

    @Published public var rulerShortcutModifiers: UInt32 {
        didSet {
            defaults.set(Int(rulerShortcutModifiers), forKey: Keys.rulerShortcutModifiers)
            hotkeyConfigurationDidChange()
        }
    }

    @Published public var colorPickerShortcutKeyCode: UInt16 {
        didSet {
            defaults.set(Int(colorPickerShortcutKeyCode), forKey: Keys.colorPickerShortcutKeyCode)
            hotkeyConfigurationDidChange()
        }
    }

    @Published public var colorPickerShortcutModifiers: UInt32 {
        didSet {
            defaults.set(Int(colorPickerShortcutModifiers), forKey: Keys.colorPickerShortcutModifiers)
            hotkeyConfigurationDidChange()
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
            case .copyToClipboard, .both:
                saveToDisk = true
                copyToClipboard = true
            }
            isSyncingActionFlags = false
        }
    }

    /// Screenshots are always saved to disk.
    @Published public var saveToDisk: Bool {
        didSet {
            if !saveToDisk {
                saveToDisk = true
            }
            defaults.set(true, forKey: Keys.saveToDisk)
            syncPostCaptureActionFromFlags()
        }
    }

    @Published public var saveDirectoryPath: String {
        didSet {
            let path = saveDirectoryPath
            updateSnapshot { $0.saveDirectoryPath = path }
            defaults.set(saveDirectoryPath, forKey: Keys.saveDirectoryPath)
        }
    }

    @Published public var copyToClipboard: Bool {
        didSet {
            let value = copyToClipboard
            updateSnapshot { $0.copyToClipboard = value }
            defaults.set(copyToClipboard, forKey: Keys.copyToClipboard)
            syncPostCaptureActionFromFlags()
        }
    }

    private func syncPostCaptureActionFromFlags() {
        guard !isSyncingActionFlags else { return }
        let newAction: PostCaptureAction = copyToClipboard ? .both : .saveToDisk
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
            let value = imageFormat
            updateSnapshot { $0.imageFormat = value }
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
            updateSnapshot { $0.jpgQuality = clamped }
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
            let value = scrollingCaptureSpeed
            updateSnapshot { $0.scrollingCaptureSpeed = value }
            defaults.set(scrollingCaptureSpeed.rawValue, forKey: Keys.scrollingCaptureSpeed)
        }
    }

    /// Thread-safe (reads the locked mirror).
    public var jpgCompressionFactor: Double {
        captureSnapshot.jpgCompressionFactor
    }


    // MARK: - Validation & Conflict States

    @Published public var isHotkeyConflict: Bool = false
    @Published public var hotkeyErrorMessage: String? = nil

    // MARK: - Initialization

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Defaults:
        // Area: Cmd + Shift + 4 (kVK_ANSI_4)
        // Fullscreen: Cmd + Shift + 2 (kVK_ANSI_2)
        // Repeat Previous: Cmd + Shift + 3 (kVK_ANSI_3)
        // OCR: Cmd + Shift + R (kVK_ANSI_R)
        // Scrolling: Cmd + Shift + 5 (kVK_ANSI_5)
        let defaultModifiers = UInt32(cmdKey | shiftKey)

        self.globalHotkeysEnabled = defaults.object(forKey: Keys.globalHotkeysEnabled) as? Bool ?? true

        if defaults.object(forKey: Keys.hotkeyKeyCode) != nil {
            self.hotkeyKeyCode = AppSettings.storedKeyCode(defaults, key: Keys.hotkeyKeyCode, fallback: UInt16(kVK_ANSI_4))
        } else {
            self.hotkeyKeyCode = UInt16(kVK_ANSI_4)
        }

        if defaults.object(forKey: Keys.hotkeyModifiers) != nil {
            self.hotkeyModifiers = AppSettings.storedModifiers(defaults, key: Keys.hotkeyModifiers, fallback: defaultModifiers)
        } else {
            self.hotkeyModifiers = defaultModifiers
        }

        if defaults.object(forKey: Keys.fullscreenShortcutKeyCode) != nil {
            self.fullscreenShortcutKeyCode = AppSettings.storedKeyCode(defaults, key: Keys.fullscreenShortcutKeyCode, fallback: UInt16(kVK_ANSI_2))
        } else {
            self.fullscreenShortcutKeyCode = UInt16(kVK_ANSI_2)
        }

        if defaults.object(forKey: Keys.fullscreenShortcutModifiers) != nil {
            self.fullscreenShortcutModifiers = AppSettings.storedModifiers(defaults, key: Keys.fullscreenShortcutModifiers, fallback: defaultModifiers)
        } else {
            self.fullscreenShortcutModifiers = defaultModifiers
        }

        if defaults.object(forKey: Keys.repeatShortcutKeyCode) != nil {
            self.repeatShortcutKeyCode = AppSettings.storedKeyCode(defaults, key: Keys.repeatShortcutKeyCode, fallback: UInt16(kVK_ANSI_3))
        } else {
            self.repeatShortcutKeyCode = UInt16(kVK_ANSI_3)
        }

        if defaults.object(forKey: Keys.repeatShortcutModifiers) != nil {
            self.repeatShortcutModifiers = AppSettings.storedModifiers(defaults, key: Keys.repeatShortcutModifiers, fallback: defaultModifiers)
        } else {
            self.repeatShortcutModifiers = defaultModifiers
        }

        if defaults.object(forKey: Keys.ocrShortcutKeyCode) != nil {
            self.ocrShortcutKeyCode = AppSettings.storedKeyCode(defaults, key: Keys.ocrShortcutKeyCode, fallback: UInt16(kVK_ANSI_R))
        } else {
            self.ocrShortcutKeyCode = UInt16(kVK_ANSI_R)
        }

        if defaults.object(forKey: Keys.ocrShortcutModifiers) != nil {
            self.ocrShortcutModifiers = AppSettings.storedModifiers(defaults, key: Keys.ocrShortcutModifiers, fallback: defaultModifiers)
        } else {
            self.ocrShortcutModifiers = defaultModifiers
        }

        if defaults.object(forKey: Keys.scrollingShortcutKeyCode) != nil {
            self.scrollingShortcutKeyCode = AppSettings.storedKeyCode(defaults, key: Keys.scrollingShortcutKeyCode, fallback: UInt16(kVK_ANSI_5))
        } else {
            self.scrollingShortcutKeyCode = UInt16(kVK_ANSI_5)
        }

        if defaults.object(forKey: Keys.scrollingShortcutModifiers) != nil {
            self.scrollingShortcutModifiers = AppSettings.storedModifiers(defaults, key: Keys.scrollingShortcutModifiers, fallback: defaultModifiers)
        } else {
            self.scrollingShortcutModifiers = defaultModifiers
        }

        if defaults.object(forKey: Keys.rulerShortcutKeyCode) != nil {
            self.rulerShortcutKeyCode = AppSettings.storedKeyCode(defaults, key: Keys.rulerShortcutKeyCode, fallback: UInt16(kVK_ANSI_M))
        } else {
            self.rulerShortcutKeyCode = UInt16(kVK_ANSI_M)
        }

        if defaults.object(forKey: Keys.rulerShortcutModifiers) != nil {
            self.rulerShortcutModifiers = AppSettings.storedModifiers(defaults, key: Keys.rulerShortcutModifiers, fallback: defaultModifiers)
        } else {
            self.rulerShortcutModifiers = defaultModifiers
        }

        if defaults.object(forKey: Keys.colorPickerShortcutKeyCode) != nil {
            self.colorPickerShortcutKeyCode = AppSettings.storedKeyCode(defaults, key: Keys.colorPickerShortcutKeyCode, fallback: UInt16(kVK_ANSI_C))
        } else {
            self.colorPickerShortcutKeyCode = UInt16(kVK_ANSI_C)
        }

        if defaults.object(forKey: Keys.colorPickerShortcutModifiers) != nil {
            self.colorPickerShortcutModifiers = AppSettings.storedModifiers(defaults, key: Keys.colorPickerShortcutModifiers, fallback: defaultModifiers)
        } else {
            self.colorPickerShortcutModifiers = defaultModifiers
        }

        let resolvedDefaultFolder = AppSettings.defaultSaveLocation()
        let configuredPath = defaults.string(forKey: Keys.saveDirectoryPath)
        let finalPath = (configuredPath != nil && !configuredPath!.isEmpty) ? configuredPath! : resolvedDefaultFolder
        self.saveDirectoryPath = finalPath

        // Screenshots always save to disk
        self.saveToDisk = true
        let copiedClip = defaults.object(forKey: Keys.copyToClipboard) as? Bool ?? true
        self.copyToClipboard = copiedClip
        self.postCaptureAction = copiedClip ? .both : .saveToDisk

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

        // didSet does not run during init: seed the thread-safe mirror explicitly
        _snapshot = CaptureSettingsSnapshot(
            saveDirectoryPath: saveDirectoryPath,
            imageFormat: imageFormat,
            copyToClipboard: copyToClipboard,
            jpgQuality: jpgQuality,
            scrollingCaptureSpeed: scrollingCaptureSpeed
        )

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

    public var scrollingShortcutDisplayString: String {
        KeyCodes.shortcutString(keyCode: scrollingShortcutKeyCode, carbonMods: scrollingShortcutModifiers)
    }

    public var rulerShortcutDisplayString: String {
        KeyCodes.shortcutString(keyCode: rulerShortcutKeyCode, carbonMods: rulerShortcutModifiers)
    }

    public var colorPickerShortcutDisplayString: String {
        KeyCodes.shortcutString(keyCode: colorPickerShortcutKeyCode, carbonMods: colorPickerShortcutModifiers)
    }

    public var hotkeyDisplayString: String {
        areaShortcutDisplayString
    }

    /// Thread-safe: read from background queues by the save pipeline and history scanner.
    public var resolvedSaveDirectoryURL: URL {
        threadSafeLock.lock()
        if let cached = _cachedSaveDirectoryURL {
            threadSafeLock.unlock()
            return cached
        }
        let rawPath = _snapshot.saveDirectoryPath
        threadSafeLock.unlock()

        let path = (rawPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }

        threadSafeLock.lock()
        // Only cache if the folder was not changed while we were resolving it
        if _snapshot.saveDirectoryPath == rawPath {
            _cachedSaveDirectoryURL = url
        }
        threadSafeLock.unlock()
        return url
    }

    public func checkForShortcutConflicts() {
        guard globalHotkeysEnabled else {
            isHotkeyConflict = false
            hotkeyErrorMessage = nil
            return
        }

        let shortcuts = [
            ("Area", hotkeyKeyCode, hotkeyModifiers),
            ("Fullscreen", fullscreenShortcutKeyCode, fullscreenShortcutModifiers),
            ("Repeat", repeatShortcutKeyCode, repeatShortcutModifiers),
            ("OCR", ocrShortcutKeyCode, ocrShortcutModifiers),
            ("Scrolling", scrollingShortcutKeyCode, scrollingShortcutModifiers),
            ("Ruler", rulerShortcutKeyCode, rulerShortcutModifiers),
            ("Color Picker", colorPickerShortcutKeyCode, colorPickerShortcutModifiers)
        ].filter { KeyCodes.isShortcutAssigned(keyCode: $0.1, carbonMods: $0.2) }

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

    public func clearAllHotkeys() {
        performHotkeyBatchUpdate {
            applyClearedHotkeys()
        }
    }

    private func applyClearedHotkeys() {
        let noKey = KeyCodes.noKey
        hotkeyKeyCode = noKey
        hotkeyModifiers = 0
        fullscreenShortcutKeyCode = noKey
        fullscreenShortcutModifiers = 0
        repeatShortcutKeyCode = noKey
        repeatShortcutModifiers = 0
        ocrShortcutKeyCode = noKey
        ocrShortcutModifiers = 0
        scrollingShortcutKeyCode = noKey
        scrollingShortcutModifiers = 0
        rulerShortcutKeyCode = noKey
        rulerShortcutModifiers = 0
        colorPickerShortcutKeyCode = noKey
        colorPickerShortcutModifiers = 0
    }

    public func resetHotkeysToDefault() {
        performHotkeyBatchUpdate {
            applyDefaultHotkeys()
        }
    }

    private func applyDefaultHotkeys() {
        globalHotkeysEnabled = true
        hotkeyKeyCode = UInt16(kVK_ANSI_4)
        hotkeyModifiers = UInt32(cmdKey | shiftKey)
        fullscreenShortcutKeyCode = UInt16(kVK_ANSI_2)
        fullscreenShortcutModifiers = UInt32(cmdKey | shiftKey)
        repeatShortcutKeyCode = UInt16(kVK_ANSI_3)
        repeatShortcutModifiers = UInt32(cmdKey | shiftKey)
        ocrShortcutKeyCode = UInt16(kVK_ANSI_R)
        ocrShortcutModifiers = UInt32(cmdKey | shiftKey)
        scrollingShortcutKeyCode = UInt16(kVK_ANSI_5)
        scrollingShortcutModifiers = UInt32(cmdKey | shiftKey)
        rulerShortcutKeyCode = UInt16(kVK_ANSI_M)
        rulerShortcutModifiers = UInt32(cmdKey | shiftKey)
        colorPickerShortcutKeyCode = UInt16(kVK_ANSI_C)
        colorPickerShortcutModifiers = UInt32(cmdKey | shiftKey)
    }

    public func resetHotkeyToDefault() {
        resetHotkeysToDefault()
    }
}
