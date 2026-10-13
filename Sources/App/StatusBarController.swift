import Cocoa

public final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    private var captureRegionMenuItem: NSMenuItem!
    private var captureFullscreenMenuItem: NSMenuItem!
    private var repeatScreenshotMenuItem: NSMenuItem!
    private var revealLatestMenuItem: NSMenuItem!
    private var saveToDiskMenuItem: NSMenuItem!
    private var copyToClipboardMenuItem: NSMenuItem!
    private var postCaptureActionMenuItem: NSMenuItem!
    private var includeCursorMenuItem: NSMenuItem!
    private var delayMenuItem: NSMenuItem!
    private var formatMenuItem: NSMenuItem!
    private var qualityMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!

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
            } else if let symbolImage = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Shots!") {
                symbolImage.isTemplate = true
                button.image = symbolImage
            } else {
                button.image = createFallbackIcon()
            }
            button.toolTip = "Shots! — Click for options or press \(AppSettings.shared.hotkeyDisplayString)"
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

        // 1. Capture Region
        let shortcut = AppSettings.shared.hotkeyDisplayString
        captureRegionMenuItem = NSMenuItem(
            title: "Capture Region (\(shortcut))",
            action: #selector(captureRegionAction),
            keyEquivalent: ""
        )
        captureRegionMenuItem.target = self
        if let icon = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil) {
            icon.isTemplate = true
            captureRegionMenuItem.image = icon
        }
        menu.addItem(captureRegionMenuItem)

        // 2. Capture Fullscreen
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

        // 3. Repeat Previous Screenshot
        let repeatShortcut = AppSettings.shared.repeatShortcutDisplayString
        repeatScreenshotMenuItem = NSMenuItem(
            title: "Repeat Previous Screenshot (\(repeatShortcut))",
            action: #selector(repeatScreenshotAction),
            keyEquivalent: ""
        )
        repeatScreenshotMenuItem.target = self
        if let repeatIcon = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil) {
            repeatIcon.isTemplate = true
            repeatScreenshotMenuItem.image = repeatIcon
        }
        menu.addItem(repeatScreenshotMenuItem)

        // 4. Reveal Latest Screenshot
        revealLatestMenuItem = NSMenuItem(
            title: "Reveal Latest Screenshot",
            action: #selector(revealLatestScreenshotAction),
            keyEquivalent: ""
        )
        revealLatestMenuItem.target = self
        if let docIcon = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil) {
            docIcon.isTemplate = true
            revealLatestMenuItem.image = docIcon
        }
        menu.addItem(revealLatestMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Quick Toggles
        saveToDiskMenuItem = NSMenuItem(
            title: "Save to Folder",
            action: #selector(toggleSaveToDisk),
            keyEquivalent: ""
        )
        saveToDiskMenuItem.target = self
        if let folderIcon = NSImage(systemSymbolName: "folder", accessibilityDescription: nil) {
            folderIcon.isTemplate = true
            saveToDiskMenuItem.image = folderIcon
        }
        menu.addItem(saveToDiskMenuItem)

        copyToClipboardMenuItem = NSMenuItem(
            title: "Copy to Clipboard",
            action: #selector(toggleCopyToClipboard),
            keyEquivalent: ""
        )
        copyToClipboardMenuItem.target = self
        if let clipIcon = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) {
            clipIcon.isTemplate = true
            copyToClipboardMenuItem.image = clipIcon
        }
        menu.addItem(copyToClipboardMenuItem)

        includeCursorMenuItem = NSMenuItem(
            title: "Include Cursor",
            action: #selector(toggleIncludeCursor),
            keyEquivalent: ""
        )
        includeCursorMenuItem.target = self
        if let cursorIcon = NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: nil) {
            cursorIcon.isTemplate = true
            includeCursorMenuItem.image = cursorIcon
        }
        menu.addItem(includeCursorMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Capture Delay submenu
        delayMenuItem = NSMenuItem(title: "Capture Delay", action: nil, keyEquivalent: "")
        if let timerIcon = NSImage(systemSymbolName: "timer", accessibilityDescription: nil) {
            timerIcon.isTemplate = true
            delayMenuItem.image = timerIcon
        }
        let delayMenu = NSMenu()
        let delays = [(0, "None (0s)"), (3, "3 seconds"), (5, "5 seconds"), (10, "10 seconds")]
        for (sec, title) in delays {
            let item = NSMenuItem(title: title, action: #selector(setDelayAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = sec
            delayMenu.addItem(item)
        }
        delayMenuItem.submenu = delayMenu
        menu.addItem(delayMenuItem)

        // Image Format submenu
        formatMenuItem = NSMenuItem(title: "Image Format", action: nil, keyEquivalent: "")
        if let photoIcon = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) {
            photoIcon.isTemplate = true
            formatMenuItem.image = photoIcon
        }
        let formatMenu = NSMenu()
        for format in ImageFormat.allCases {
            let item = NSMenuItem(title: format.displayName, action: #selector(setFormatAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = format
            formatMenu.addItem(item)
        }
        formatMenuItem.submenu = formatMenu
        menu.addItem(formatMenuItem)

        // JPG Quality submenu
        qualityMenuItem = NSMenuItem(title: "JPG Quality", action: nil, keyEquivalent: "")
        if let sliderIcon = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil) {
            sliderIcon.isTemplate = true
            qualityMenuItem.image = sliderIcon
        }
        let qualityMenu = NSMenu()
        let qualityOptions = [(60, "60% (Compact)"), (80, "80% (Default)"), (90, "90% (High)"), (100, "100% (Maximum)")]
        for (q, title) in qualityOptions {
            let item = NSMenuItem(title: title, action: #selector(setQualityAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = q
            qualityMenu.addItem(item)
        }
        qualityMenuItem.submenu = qualityMenu
        menu.addItem(qualityMenuItem)

        // Post-Capture Action submenu
        postCaptureActionMenuItem = NSMenuItem(title: "Post-Capture Action", action: nil, keyEquivalent: "")
        if let docIcon = NSImage(systemSymbolName: "arrow.right.doc.on.clipboard", accessibilityDescription: nil) {
            docIcon.isTemplate = true
            postCaptureActionMenuItem.image = docIcon
        }
        let postCaptureMenu = NSMenu()
        for action in PostCaptureAction.allCases {
            let item = NSMenuItem(title: action.displayName, action: #selector(setPostCaptureAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            postCaptureMenu.addItem(item)
        }
        postCaptureActionMenuItem.submenu = postCaptureMenu
        menu.addItem(postCaptureActionMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login
        launchAtLoginMenuItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginMenuItem.target = self
        if let loopIcon = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.circle", accessibilityDescription: nil) {
            loopIcon.isTemplate = true
            launchAtLoginMenuItem.image = loopIcon
        }
        menu.addItem(launchAtLoginMenuItem)

        // 4. Preferences & Hotkeys
        let prefsItem = NSMenuItem(
            title: "Preferences & Hotkeys...",
            action: #selector(openPreferencesAction),
            keyEquivalent: ","
        )
        prefsItem.target = self
        if let gearIcon = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) {
            gearIcon.isTemplate = true
            prefsItem.image = gearIcon
        }
        menu.addItem(prefsItem)

        // 5. Open Screenshots Folder
        let folderItem = NSMenuItem(
            title: "Open Screenshots Folder",
            action: #selector(openFolderAction),
            keyEquivalent: "o"
        )
        folderItem.target = self
        if let folderIcon = NSImage(systemSymbolName: "folder", accessibilityDescription: nil) {
            folderIcon.isTemplate = true
            folderItem.image = folderIcon
        }
        menu.addItem(folderItem)

        // 6. Change Save Location
        let changeFolderItem = NSMenuItem(
            title: "Change Save Location...",
            action: #selector(changeFolderAction),
            keyEquivalent: ""
        )
        changeFolderItem.target = self
        if let folderBadgeIcon = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: nil) {
            folderBadgeIcon.isTemplate = true
            changeFolderItem.image = folderBadgeIcon
        }
        menu.addItem(changeFolderItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Quit Shots!
        let quitItem = NSMenuItem(
            title: "Quit Shots!",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateMenuItemsState()
    }

    public func menuWillOpen(_ menu: NSMenu) {
        updateMenuItemsState()
    }

    private func updateMenuItemsState() {
        let settings = AppSettings.shared
        let areaShortcut = settings.areaShortcutDisplayString
        let fsShortcut = settings.fullscreenShortcutDisplayString
        let repShortcut = settings.repeatShortcutDisplayString
        captureRegionMenuItem.title = "Capture Region (\(areaShortcut))"
        captureFullscreenMenuItem.title = "Capture Fullscreen (\(fsShortcut))"
        repeatScreenshotMenuItem.title = "Repeat Previous Screenshot (\(repShortcut))"
        repeatScreenshotMenuItem.isEnabled = (CaptureManager.shared.lastCapture != nil)
        revealLatestMenuItem.isEnabled = (SaveService.shared.resolveLatestScreenshotURL() != nil)

        if let button = statusItem.button {
            button.toolTip = "Shots! — Click for options or press \(areaShortcut)"
        }

        saveToDiskMenuItem.state = settings.saveToDisk ? .on : .off
        copyToClipboardMenuItem.state = settings.copyToClipboard ? .on : .off
        includeCursorMenuItem.state = settings.includeCursor ? .on : .off

        if let delayMenu = delayMenuItem?.submenu {
            for item in delayMenu.items {
                item.state = (item.tag == settings.captureDelaySeconds) ? .on : .off
            }
        }

        if let formatMenu = formatMenuItem?.submenu {
            for item in formatMenu.items {
                if let fmt = item.representedObject as? ImageFormat {
                    item.state = (fmt == settings.imageFormat) ? .on : .off
                }
            }
        }

        if let qualityMenu = qualityMenuItem?.submenu {
            for item in qualityMenu.items {
                item.state = (item.tag == settings.jpgQuality) ? .on : .off
            }
        }

        if let postMenu = postCaptureActionMenuItem?.submenu {
            for item in postMenu.items {
                if let action = item.representedObject as? PostCaptureAction {
                    item.state = (action == settings.postCaptureAction) ? .on : .off
                }
            }
        }

        launchAtLoginMenuItem.state = settings.launchAtLogin ? .on : .off
    }

    // MARK: - Actions

    @objc private func captureRegionAction() {
        // Slight delay to allow menu window to completely dismiss from screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.startRegionCapture()
        }
    }

    @objc private func captureFullscreenAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.captureFullscreen()
        }
    }

    @objc private func repeatScreenshotAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.repeatPreviousScreenshot()
        }
    }

    @objc private func revealLatestScreenshotAction() {
        if !SaveService.shared.revealLatestScreenshot() {
            NSSound.beep()
        }
    }

    @objc private func toggleSaveToDisk() {
        AppSettings.shared.saveToDisk.toggle()
        updateMenuItemsState()
    }

    @objc private func toggleCopyToClipboard() {
        AppSettings.shared.copyToClipboard.toggle()
        updateMenuItemsState()
    }

    @objc private func toggleIncludeCursor() {
        AppSettings.shared.includeCursor.toggle()
        updateMenuItemsState()
    }

    @objc private func setDelayAction(_ sender: NSMenuItem) {
        AppSettings.shared.captureDelaySeconds = sender.tag
        updateMenuItemsState()
    }

    @objc private func setFormatAction(_ sender: NSMenuItem) {
        if let format = sender.representedObject as? ImageFormat {
            AppSettings.shared.imageFormat = format
            updateMenuItemsState()
        }
    }

    @objc private func setQualityAction(_ sender: NSMenuItem) {
        AppSettings.shared.jpgQuality = sender.tag
        updateMenuItemsState()
    }

    @objc private func setPostCaptureAction(_ sender: NSMenuItem) {
        if let action = sender.representedObject as? PostCaptureAction {
            AppSettings.shared.postCaptureAction = action
            updateMenuItemsState()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let current = AppSettings.shared.launchAtLogin
        _ = LaunchAtLoginService.shared.setLaunchAtLogin(enabled: !current)
        updateMenuItemsState()
    }

    @objc private func openPreferencesAction() {
        PreferencesWindowController.shared.showWindow()
    }

    @objc private func openFolderAction() {
        let url = AppSettings.shared.resolvedSaveDirectoryURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func changeFolderAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = AppSettings.shared.resolvedSaveDirectoryURL

        if panel.runModal() == .OK, let selectedURL = panel.url {
            AppSettings.shared.saveDirectoryPath = selectedURL.path
        }
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    @objc private func settingsDidChange() {
        updateMenuItemsState()
    }
}
