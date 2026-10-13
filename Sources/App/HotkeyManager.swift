import Carbon
import Cocoa

public final class HotKeyManager {
    public static let shared = HotKeyManager()

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefArea: EventHotKeyRef?
    private var hotKeyRefFullscreen: EventHotKeyRef?
    private var hotKeyRefRepeat: EventHotKeyRef?
    private var hotKeyRefOCR: EventHotKeyRef?

    private let signature: OSType = 0x5343524E /* 'SCRN' */

    public var onTrigger: (() -> Void)?
    public var onAreaCaptureTrigger: (() -> Void)?
    public var onFullscreenCaptureTrigger: (() -> Void)?
    public var onRepeatCaptureTrigger: (() -> Void)?
    public var onOCRCaptureTrigger: (() -> Void)?

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
                guard let userData = userData, let event = theEvent else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let paramStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let id = (paramStatus == noErr) ? hotKeyID.id : 1
                manager.handleHotkeyEvent(id: id)
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
        settings.checkForShortcutConflicts()
        if settings.isHotkeyConflict {
            return false
        }

        var allSucceeded = true

        // 1. Area Screenshot (id: 1)
        let areaStatus = RegisterEventHotKey(
            UInt32(settings.hotkeyKeyCode),
            settings.hotkeyModifiers,
            EventHotKeyID(signature: signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &hotKeyRefArea
        )
        if areaStatus != noErr {
            NSLog("Failed to register Area shortcut (%@): %d", settings.areaShortcutDisplayString, areaStatus)
            allSucceeded = false
        }

        // 2. Fullscreen Screenshot (id: 2)
        let fsStatus = RegisterEventHotKey(
            UInt32(settings.fullscreenShortcutKeyCode),
            settings.fullscreenShortcutModifiers,
            EventHotKeyID(signature: signature, id: 2),
            GetApplicationEventTarget(),
            0,
            &hotKeyRefFullscreen
        )
        if fsStatus != noErr {
            NSLog("Failed to register Fullscreen shortcut (%@): %d", settings.fullscreenShortcutDisplayString, fsStatus)
            allSucceeded = false
        }

        // 3. Repeat Previous Screenshot (id: 3)
        let repStatus = RegisterEventHotKey(
            UInt32(settings.repeatShortcutKeyCode),
            settings.repeatShortcutModifiers,
            EventHotKeyID(signature: signature, id: 3),
            GetApplicationEventTarget(),
            0,
            &hotKeyRefRepeat
        )
        if repStatus != noErr {
            NSLog("Failed to register Repeat shortcut (%@): %d", settings.repeatShortcutDisplayString, repStatus)
            allSucceeded = false
        }

        // 4. OCR Recognition (id: 4)
        let ocrStatus = RegisterEventHotKey(
            UInt32(settings.ocrShortcutKeyCode),
            settings.ocrShortcutModifiers,
            EventHotKeyID(signature: signature, id: 4),
            GetApplicationEventTarget(),
            0,
            &hotKeyRefOCR
        )
        if ocrStatus != noErr {
            NSLog("Failed to register OCR shortcut (%@): %d", settings.ocrShortcutDisplayString, ocrStatus)
            allSucceeded = false
        }

        if !allSucceeded {
            settings.isHotkeyConflict = true
            settings.hotkeyErrorMessage = "One or more shortcuts are unavailable (used by macOS or another app)."
            return false
        } else {
            settings.isHotkeyConflict = false
            settings.hotkeyErrorMessage = nil
            return true
        }
    }

    public func unregisterHotkey() {
        if let ref = hotKeyRefArea {
            UnregisterEventHotKey(ref)
            hotKeyRefArea = nil
        }
        if let ref = hotKeyRefFullscreen {
            UnregisterEventHotKey(ref)
            hotKeyRefFullscreen = nil
        }
        if let ref = hotKeyRefRepeat {
            UnregisterEventHotKey(ref)
            hotKeyRefRepeat = nil
        }
        if let ref = hotKeyRefOCR {
            UnregisterEventHotKey(ref)
            hotKeyRefOCR = nil
        }
    }

    private func handleHotkeyEvent(id: UInt32) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch id {
            case 1:
                self.onAreaCaptureTrigger?()
                self.onTrigger?()
            case 2:
                self.onFullscreenCaptureTrigger?()
            case 3:
                self.onRepeatCaptureTrigger?()
            case 4:
                self.onOCRCaptureTrigger?()
            default:
                self.onTrigger?()
            }
        }
    }

    @objc private func handleHotkeyChanged() {
        registerCurrentHotkey()
    }
}
