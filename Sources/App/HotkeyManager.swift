import Carbon
import Cocoa

public final class HotKeyManager {
    public static let shared = HotKeyManager()

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let hotKeyID = EventHotKeyID(signature: 0x5343524E /* 'SCRN' */, id: 1)

    public var onTrigger: (() -> Void)?

    public init() {
        installCarbonEventHandler()
        registerCurrentHotkey()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyChanged),
            name: AppSettings.hotkeyDidChangeNotification,
            object: nil
        )
    }

    deinit {
        unregisterHotkey()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, theEvent, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleHotkeyEvent()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        if status != noErr {
            NSLog("Failed to install Carbon event handler: status %d", status)
        }
    }

    @discardableResult
    public func registerCurrentHotkey() -> Bool {
        unregisterHotkey()

        let settings = AppSettings.shared
        let keyCode = UInt32(settings.hotkeyKeyCode)
        let modifiers = settings.hotkeyModifiers

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            NSLog("Failed to register hotkey (code: %u, mods: %u): status %d", keyCode, modifiers, status)
            settings.isHotkeyConflict = true
            settings.hotkeyErrorMessage = "Shortcut is unavailable (used by macOS or another app)."
            return false
        } else {
            NSLog("Successfully registered hotkey: %@", settings.hotkeyDisplayString)
            settings.isHotkeyConflict = false
            settings.hotkeyErrorMessage = nil
            return true
        }
    }

    public func unregisterHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func handleHotkeyEvent() {
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?()
        }
    }

    @objc private func handleHotkeyChanged() {
        registerCurrentHotkey()
    }
}
