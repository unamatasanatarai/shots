import Cocoa

public final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    private var permissionWarningMenuItem: NSMenuItem!
    private var captureRegionMenuItem: NSMenuItem!
    private var repeatScreenshotMenuItem: NSMenuItem!
    private var captureFullscreenMenuItem: NSMenuItem!
    private var ocrRecognitionMenuItem: NSMenuItem!
    private var scrollingCaptureMenuItem: NSMenuItem!
    private var recentScreenshotsMenuItem: NSMenuItem!
    private var screenRulerMenuItem: NSMenuItem!
    private var colorPickerMenuItem: NSMenuItem!

    private var isRecentScreenshotsHighlighted = false
    private var menuEventMonitor: Any?

    public override init() {
        super.init()
        setupStatusItem()
        setupMenu()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: AppSettings.hotkeyDidChangeNotification,
            object: nil
        )
    }

    deinit {
        removeMenuEventMonitor()
    }

    public var currentMenu: NSMenu {
        return menu
    }

    public var currentStatusItem: NSStatusItem {
        return statusItem
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let assetImage = NSImage(named: "StatusBarIcon") {
                assetImage.isTemplate = true
                button.image = assetImage
            } else if let symbolImage = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Shots") {
                symbolImage.isTemplate = true
                button.image = symbolImage
            } else {
                button.image = createFallbackIcon()
            }
            button.toolTip = "Shots — Click for options or press \(AppSettings.shared.hotkeyDisplayString)"
        }
    }

    private func createFallbackIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 3, yRadius: 3)
            path.lineWidth = 1.5
            NSColor.black.setStroke()
            path.stroke()

            let centerCircle = NSBezierPath(ovalIn: NSRect(x: 6.5, y: 6.5, width: 5, height: 5))
            path.lineWidth = 1.2
            centerCircle.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func setupMenu() {
        menu = NSMenu()
        menu.delegate = self

        // 0. Permission Warning Banner (hidden when both permissions are granted)
        permissionWarningMenuItem = NSMenuItem(
            title: "⚠️ Permissions Required",
            action: #selector(openPermissionsAction),
            keyEquivalent: ""
        )
        permissionWarningMenuItem.target = self
        permissionWarningMenuItem.isHidden = true
        if let icon = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil) {
            icon.isTemplate = true
            permissionWarningMenuItem.image = icon
        }
        menu.addItem(permissionWarningMenuItem)

        // 1. Capture Region
        captureRegionMenuItem = NSMenuItem(
            title: "Capture Region",
            action: #selector(captureRegionAction),
            keyEquivalent: ""
        )
        captureRegionMenuItem.target = self
        if let icon = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil) {
            icon.isTemplate = true
            captureRegionMenuItem.image = icon
        }
        menu.addItem(captureRegionMenuItem)

        // 2. Repeat Previous Screenshot
        repeatScreenshotMenuItem = NSMenuItem(
            title: "Repeat Previous Screenshot",
            action: #selector(repeatScreenshotAction),
            keyEquivalent: ""
        )
        repeatScreenshotMenuItem.target = self
        if let repeatIcon = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil) {
            repeatIcon.isTemplate = true
            repeatScreenshotMenuItem.image = repeatIcon
        }
        menu.addItem(repeatScreenshotMenuItem)

        // 3. Capture Fullscreen
        captureFullscreenMenuItem = NSMenuItem(
            title: "Capture Fullscreen",
            action: #selector(captureFullscreenAction),
            keyEquivalent: ""
        )
        captureFullscreenMenuItem.target = self
        if let icon = NSImage(systemSymbolName: "display", accessibilityDescription: nil) {
            icon.isTemplate = true
            captureFullscreenMenuItem.image = icon
        }
        menu.addItem(captureFullscreenMenuItem)

        // 4. OCR Recognition
        ocrRecognitionMenuItem = NSMenuItem(
            title: "OCR Recognition",
            action: #selector(ocrRecognitionAction),
            keyEquivalent: ""
        )
        ocrRecognitionMenuItem.target = self
        if let textIcon = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil) {
            textIcon.isTemplate = true
            ocrRecognitionMenuItem.image = textIcon
        }
        menu.addItem(ocrRecognitionMenuItem)

        // 5. Scrolling Capture
        scrollingCaptureMenuItem = NSMenuItem(
            title: "Scrolling Capture",
            action: #selector(scrollingCaptureAction),
            keyEquivalent: ""
        )
        scrollingCaptureMenuItem.target = self
        if let scrollIcon = NSImage(systemSymbolName: "arrow.up.and.down.square", accessibilityDescription: nil) {
            scrollIcon.isTemplate = true
            scrollingCaptureMenuItem.image = scrollIcon
        }
        menu.addItem(scrollingCaptureMenuItem)

        // 6. Recent Screenshots (Clicking opens folder; hovering reveals recent items submenu)
        recentScreenshotsMenuItem = NSMenuItem(
            title: "Recent Screenshots",
            action: #selector(openFolderAction),
            keyEquivalent: ""
        )
        recentScreenshotsMenuItem.target = self
        if let clockIcon = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil) {
            clockIcon.isTemplate = true
            recentScreenshotsMenuItem.image = clockIcon
        }
        let recentMenu = NSMenu()
        recentScreenshotsMenuItem.submenu = recentMenu
        menu.addItem(recentScreenshotsMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 7. Screen Ruler
        screenRulerMenuItem = NSMenuItem(
            title: "Screen Ruler",
            action: #selector(screenRulerAction),
            keyEquivalent: ""
        )
        screenRulerMenuItem.target = self
        if let rulerIcon = NSImage(systemSymbolName: "ruler", accessibilityDescription: nil) {
            rulerIcon.isTemplate = true
            screenRulerMenuItem.image = rulerIcon
        }
        menu.addItem(screenRulerMenuItem)

        // 8. Color Picker
        colorPickerMenuItem = NSMenuItem(
            title: "Color Picker",
            action: #selector(colorPickerAction),
            keyEquivalent: ""
        )
        colorPickerMenuItem.target = self
        if let pickerIcon = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil) {
            pickerIcon.isTemplate = true
            colorPickerMenuItem.image = pickerIcon
        }
        menu.addItem(colorPickerMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 9. Preferences
        let prefsItem = NSMenuItem(
            title: "Preferences & Hotkeys...",
            action: #selector(openPreferencesAction),
            keyEquivalent: ","
        )
        prefsItem.keyEquivalentModifierMask = [.command]
        prefsItem.target = self
        if let gearIcon = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) {
            gearIcon.isTemplate = true
            prefsItem.image = gearIcon
        }
        menu.addItem(prefsItem)
        menu.addItem(NSMenuItem.separator())

        // 10. Quit Shots
        let quitItem = NSMenuItem(
            title: "Quit Shots",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateMenuItemsState()
        updateRecentScreenshotsMenu()
    }

    // MARK: - Menu Delegate & Hover Tracking

    public func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if menu === self.menu {
            isRecentScreenshotsHighlighted = (item === recentScreenshotsMenuItem)
        }
    }

    public func menuWillOpen(_ menu: NSMenu) {
        if menu === self.menu {
            isRecentScreenshotsHighlighted = false
            installMenuEventMonitor()
            updateMenuItemsState()
            updateRecentScreenshotsMenu()
        }
    }

    public func menuDidClose(_ menu: NSMenu) {
        if menu === self.menu {
            removeMenuEventMonitor()
            isRecentScreenshotsHighlighted = false
        }
    }

    private func installMenuEventMonitor() {
        removeMenuEventMonitor()
        menuEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self = self else { return event }
            if self.isRecentScreenshotsHighlighted {
                self.isRecentScreenshotsHighlighted = false
                self.menu.cancelTracking()
                DispatchQueue.main.async {
                    self.openFolderAction()
                }
                return nil
            }
            return event
        }
    }

    private func removeMenuEventMonitor() {
        if let monitor = menuEventMonitor {
            NSEvent.removeMonitor(monitor)
            menuEventMonitor = nil
        }
    }

    private func updateMenuItemsState() {
        let settings = AppSettings.shared
        let showShortcuts = settings.globalHotkeysEnabled

        func applyShortcut(to item: NSMenuItem, title: String, keyCode: UInt16, carbonMods: UInt32) {
            item.title = title
            if showShortcuts && KeyCodes.isShortcutAssigned(keyCode: keyCode, carbonMods: carbonMods) {
                item.keyEquivalent = KeyCodes.keyEquivalent(for: keyCode)
                item.keyEquivalentModifierMask = KeyCodes.cocoaModifiers(from: carbonMods)
            } else {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
            }
        }

        applyShortcut(to: captureRegionMenuItem, title: "Capture Region", keyCode: settings.areaShortcutKeyCode, carbonMods: settings.areaShortcutModifiers)
        applyShortcut(to: repeatScreenshotMenuItem, title: "Repeat Previous Screenshot", keyCode: settings.repeatShortcutKeyCode, carbonMods: settings.repeatShortcutModifiers)
        repeatScreenshotMenuItem.isEnabled = (CaptureManager.shared.lastCapture != nil)

        applyShortcut(to: captureFullscreenMenuItem, title: "Capture Fullscreen", keyCode: settings.fullscreenShortcutKeyCode, carbonMods: settings.fullscreenShortcutModifiers)
        applyShortcut(to: ocrRecognitionMenuItem, title: "OCR Recognition", keyCode: settings.ocrShortcutKeyCode, carbonMods: settings.ocrShortcutModifiers)
        applyShortcut(to: scrollingCaptureMenuItem, title: "Scrolling Capture", keyCode: settings.scrollingShortcutKeyCode, carbonMods: settings.scrollingShortcutModifiers)
        applyShortcut(to: screenRulerMenuItem, title: "Screen Ruler", keyCode: settings.rulerShortcutKeyCode, carbonMods: settings.rulerShortcutModifiers)
        applyShortcut(to: colorPickerMenuItem, title: "Color Picker", keyCode: settings.colorPickerShortcutKeyCode, carbonMods: settings.colorPickerShortcutModifiers)

        let hasPermissions = PermissionsManager.shared.hasRequiredPermissions
        permissionWarningMenuItem.isHidden = hasPermissions
        if !hasPermissions {
            let missing = PermissionsManager.shared.missingPermissionsDescription
            permissionWarningMenuItem.title = "⚠️ Permissions Required (\(missing))"
        }

        if let button = statusItem.button {
            if !hasPermissions {
                button.toolTip = "Shots — Permissions Required (Screen Recording & Accessibility)"
            } else {
                let areaShortcut = settings.areaShortcutDisplayString
                button.toolTip = (showShortcuts && areaShortcut != "None")
                    ? "Shots — Click for options or press \(areaShortcut)"
                    : "Shots — Click for options"
            }
        }
    }

    private func updateRecentScreenshotsMenu() {
        guard let recentMenu = recentScreenshotsMenuItem?.submenu else { return }
        recentMenu.removeAllItems()

        let recents = ScreenshotHistoryService.shared.fetchRecentScreenshots()
        if recents.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Screenshots", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            recentMenu.addItem(emptyItem)
            recentScreenshotsMenuItem.title = "Recent Screenshots"
        } else {
            recentScreenshotsMenuItem.title = "Recent Screenshots (\(recents.count))"
            for item in recents {
                let menuItem = NSMenuItem(
                    title: item.filename,
                    action: #selector(recentScreenshotSelected(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = item.fileURL
                menuItem.toolTip = "Reveal \(item.filename) in Finder or choose action"
                if let thumb = item.thumbnail {
                    menuItem.image = thumb
                } else if let fallback = Self.photoIcon {
                    menuItem.image = fallback
                }

                // Submenu for explicit actions: Open in Impact, Reveal in Finder and Copy to Clipboard
                let actionSubmenu = NSMenu()

                let openInImpactSubItem = NSMenuItem(
                    title: "Open in Impact",
                    action: #selector(openRecentInImpactAction(_:)),
                    keyEquivalent: ""
                )
                openInImpactSubItem.target = self
                openInImpactSubItem.representedObject = item.fileURL
                if let editIcon = Self.editIcon {
                    openInImpactSubItem.image = editIcon
                }
                actionSubmenu.addItem(openInImpactSubItem)

                let revealSubItem = NSMenuItem(
                    title: "Reveal in Finder",
                    action: #selector(revealRecentScreenshotAction(_:)),
                    keyEquivalent: ""
                )
                revealSubItem.target = self
                revealSubItem.representedObject = item.fileURL
                if let revealIcon = Self.revealIcon {
                    revealSubItem.image = revealIcon
                }
                actionSubmenu.addItem(revealSubItem)

                let copySubItem = NSMenuItem(
                    title: "Copy to Clipboard",
                    action: #selector(copyRecentScreenshotAction(_:)),
                    keyEquivalent: ""
                )
                copySubItem.target = self
                copySubItem.representedObject = item.fileURL
                if let copyIcon = Self.copyIcon {
                    copySubItem.image = copyIcon
                }
                actionSubmenu.addItem(copySubItem)

                menuItem.submenu = actionSubmenu
                recentMenu.addItem(menuItem)
            }
        }
    }

    @objc public func recentScreenshotSelected(_ sender: NSMenuItem) {
        guard let fileURL = sender.representedObject as? URL else {
            return
        }
        if !ScreenshotHistoryService.shared.revealScreenshotInFinder(fileURL: fileURL) {
            updateRecentScreenshotsMenu()
        }
    }

    @objc public func revealRecentScreenshotAction(_ sender: NSMenuItem) {
        guard let fileURL = sender.representedObject as? URL else {
            return
        }
        if !ScreenshotHistoryService.shared.revealScreenshotInFinder(fileURL: fileURL) {
            updateRecentScreenshotsMenu()
        }
    }

    @objc public func copyRecentScreenshotAction(_ sender: NSMenuItem) {
        guard let fileURL = sender.representedObject as? URL else {
            return
        }
        if !ScreenshotHistoryService.shared.copyScreenshotToClipboard(fileURL: fileURL) {
            updateRecentScreenshotsMenu()
        }
    }

    private static let photoIcon: NSImage? = {
        let img = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        img?.isTemplate = true
        return img
    }()
    private static let editIcon: NSImage? = {
        let img = NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: nil)
        img?.isTemplate = true
        return img
    }()
    private static let revealIcon: NSImage? = {
        let img = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        img?.isTemplate = true
        return img
    }()
    private static let copyIcon: NSImage? = {
        let img = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        img?.isTemplate = true
        return img
    }()

    // MARK: - Actions

    @objc public func openRecentInImpactAction(_ sender: NSMenuItem) {
        guard let fileURL = sender.representedObject as? URL else { return }
        ImpactLauncher.shared.openImageFile(url: fileURL)
    }

    @objc private func openPermissionsAction() {
        removeMenuEventMonitor()
        PermissionsManager.shared.openSystemSettingsForMissingPermissions()
        PreferencesWindowController.shared.showWindow()
    }

    @objc private func captureRegionAction() {
        guard PermissionsManager.shared.ensurePermissions(for: "Capture Region") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.startRegionCapture()
        }
    }

    @objc private func repeatScreenshotAction() {
        guard PermissionsManager.shared.ensurePermissions(for: "Repeat Screenshot") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.repeatPreviousScreenshot()
        }
    }

    @objc private func captureFullscreenAction() {
        guard PermissionsManager.shared.ensurePermissions(for: "Capture Fullscreen") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.captureFullscreen()
        }
    }

    @objc public func ocrRecognitionAction() {
        guard PermissionsManager.shared.ensurePermissions(for: "OCR Recognition") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.startOCRRecognition()
        }
    }

    @objc public func scrollingCaptureAction() {
        guard PermissionsManager.shared.ensurePermissions(for: "Scrolling Capture") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.startScrollingCapture()
        }
    }

    @objc public func screenRulerAction() {
        guard PermissionsManager.shared.ensurePermissions(for: "Screen Ruler") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.startRuler()
        }
    }

    @objc public func colorPickerAction() {
        guard PermissionsManager.shared.ensurePermissions(for: "Color Picker") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.startColorPicker()
        }
    }

    @objc private func openPreferencesAction() {
        removeMenuEventMonitor()
        PreferencesWindowController.shared.showWindow()
    }

    @objc public func openFolderAction() {
        let url = AppSettings.shared.resolvedSaveDirectoryURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    @objc private func settingsDidChange() {
        if Thread.isMainThread {
            updateMenuItemsState()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateMenuItemsState()
            }
        }
    }
}
