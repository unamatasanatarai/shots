import Cocoa

public final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    private var captureRegionMenuItem: NSMenuItem!
    private var captureFullscreenMenuItem: NSMenuItem!
    private var scrollingCaptureMenuItem: NSMenuItem!
    private var repeatScreenshotMenuItem: NSMenuItem!
    private var ocrRecognitionMenuItem: NSMenuItem!
    private var screenRulerMenuItem: NSMenuItem!
    private var colorPickerMenuItem: NSMenuItem!
    private var recentScreenshotsMenuItem: NSMenuItem!
    private var includeCursorMenuItem: NSMenuItem!
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

        // 3. Scrolling Capture
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

        // 4. Repeat Previous Screenshot
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

        // 4. OCR Recognition
        let ocrShortcut = AppSettings.shared.ocrShortcutDisplayString
        ocrRecognitionMenuItem = NSMenuItem(
            title: "OCR Recognition (\(ocrShortcut))",
            action: #selector(ocrRecognitionAction),
            keyEquivalent: ""
        )
        ocrRecognitionMenuItem.target = self
        if let textIcon = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil) {
            textIcon.isTemplate = true
            ocrRecognitionMenuItem.image = textIcon
        }
        menu.addItem(ocrRecognitionMenuItem)

        // Screen Ruler
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

        // Color Picker
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
        // 5. Recent Screenshots
        recentScreenshotsMenuItem = NSMenuItem(
            title: "Recent Screenshots",
            action: nil,
            keyEquivalent: ""
        )
        if let clockIcon = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil) {
            clockIcon.isTemplate = true
            recentScreenshotsMenuItem.image = clockIcon
        }
        let recentMenu = NSMenu()
        recentScreenshotsMenuItem.submenu = recentMenu
        menu.addItem(recentScreenshotsMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Quick Toggles: Include Cursor & Launch at Login
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

        menu.addItem(NSMenuItem.separator())

        // Preferences & Screenshots Folder
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

        // Quit Shots
        let quitItem = NSMenuItem(
            title: "Quit Shots",
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
        let ocrShortcut = settings.ocrShortcutDisplayString
        let scrollShortcut = settings.scrollingShortcutDisplayString
        let rulerShortcut = settings.rulerShortcutDisplayString
        let colorPickerShortcut = settings.colorPickerShortcutDisplayString

        let showShortcuts = settings.globalHotkeysEnabled
        let formatTitle: (String, String) -> String = { base, shortcut in
            (showShortcuts && shortcut != "None") ? "\(base) (\(shortcut))" : base
        }

        captureRegionMenuItem.title = formatTitle("Capture Region", areaShortcut)
        captureFullscreenMenuItem.title = formatTitle("Capture Fullscreen", fsShortcut)
        scrollingCaptureMenuItem.title = formatTitle("Scrolling Capture", scrollShortcut)
        repeatScreenshotMenuItem.title = formatTitle("Repeat Previous Screenshot", repShortcut)
        ocrRecognitionMenuItem.title = formatTitle("OCR Recognition", ocrShortcut)
        screenRulerMenuItem.title = formatTitle("Screen Ruler", rulerShortcut)
        colorPickerMenuItem.title = formatTitle("Color Picker", colorPickerShortcut)
        repeatScreenshotMenuItem.isEnabled = (CaptureManager.shared.lastCapture != nil)
        if let button = statusItem.button {
            button.toolTip = (showShortcuts && areaShortcut != "None")
                ? "Shots — Click for options or press \(areaShortcut)"
                : "Shots — Click for options"
        }

        includeCursorMenuItem.state = settings.includeCursor ? .on : .off
        launchAtLoginMenuItem.state = settings.launchAtLogin ? .on : .off

        updateRecentScreenshotsMenu()
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
                } else if let fallback = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) {
                    fallback.isTemplate = true
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
                if let editIcon = NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: nil) {
                    editIcon.isTemplate = true
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
                if let revealIcon = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil) {
                    revealIcon.isTemplate = true
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
                if let copyIcon = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) {
                    copyIcon.isTemplate = true
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

    // MARK: - Actions

    @objc private func openImageInImpactAction() {
        ImpactLauncher.shared.openImageFileDialog()
    }

    @objc private func openTestImageInImpactAction() {
        ImpactLauncher.shared.openTestImage()
    }

    @objc public func openRecentInImpactAction(_ sender: NSMenuItem) {
        guard let fileURL = sender.representedObject as? URL else { return }
        ImpactLauncher.shared.openImageFile(url: fileURL)
    }

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

    @objc public func scrollingCaptureAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.startScrollingCapture()
        }
    }

    @objc private func repeatScreenshotAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.repeatPreviousScreenshot()
        }
    }

    @objc public func ocrRecognitionAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.startOCRRecognition()
        }
    }

    @objc public func screenRulerAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.startRuler()
        }
    }

    @objc public func colorPickerAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CaptureManager.shared.startColorPicker()
        }
    }

    @objc private func revealLatestScreenshotAction() {
        _ = SaveService.shared.revealLatestScreenshot()
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
        if Thread.isMainThread {
            updateMenuItemsState()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateMenuItemsState()
            }
        }
    }
}
