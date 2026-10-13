import Cocoa

public final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    private var captureRegionMenuItem: NSMenuItem!
    private var captureFullscreenMenuItem: NSMenuItem!
    private var saveToDiskMenuItem: NSMenuItem!
    private var copyToClipboardMenuItem: NSMenuItem!
    private var includeCursorMenuItem: NSMenuItem!
    private var delayMenuItem: NSMenuItem!
    private var formatMenuItem: NSMenuItem!
    private var qualityMenuItem: NSMenuItem!

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

        menu.addItem(NSMenuItem.separator())

        // 3. Quick Toggles
        saveToDiskMenuItem = NSMenuItem(
            title: "Save to Folder",
            action: #selector(toggleSaveToDisk),
            keyEquivalent: ""
        )
        saveToDiskMenuItem.target = self
        menu.addItem(saveToDiskMenuItem)

        copyToClipboardMenuItem = NSMenuItem(
            title: "Copy to Clipboard",
            action: #selector(toggleCopyToClipboard),
            keyEquivalent: ""
        )
        copyToClipboardMenuItem.target = self
        menu.addItem(copyToClipboardMenuItem)

        includeCursorMenuItem = NSMenuItem(
            title: "Include Cursor",
            action: #selector(toggleIncludeCursor),
            keyEquivalent: ""
        )
        includeCursorMenuItem.target = self
        menu.addItem(includeCursorMenuItem)

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

        menu.addItem(NSMenuItem.separator())

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
        let shortcut = settings.hotkeyDisplayString
        captureRegionMenuItem.title = "Capture Region (\(shortcut))"

        if let button = statusItem.button {
            button.toolTip = "Shots! — Click for options or press \(shortcut)"
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

    @objc private func openPreferencesAction() {
        PreferencesWindowController.shared.showWindow()
    }

    @objc private func openFolderAction() {
        let url = AppSettings.shared.resolvedSaveDirectoryURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    @objc private func settingsDidChange() {
        updateMenuItemsState()
    }
}
