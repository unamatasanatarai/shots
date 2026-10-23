import SwiftUI
import Carbon
import Cocoa

public struct PreferencesView: View {
    public enum Tab: String, CaseIterable, Identifiable {
        case capture = "Capture"
        case general = "General"
        case shortcuts = "Shortcuts"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .capture: return "camera"
            case .general: return "gearshape"
            case .shortcuts: return "keyboard"
            }
        }
    }

    enum ShortcutTarget: String, CaseIterable, Identifiable {
        case area = "Area Screenshot"
        case fullscreen = "Fullscreen"
        case repeatCapture = "Repeat Previous"
        case ocr = "OCR Recognition"
        case scrolling = "Scrolling Capture"
        case ruler = "Screen Ruler"
        case colorPicker = "Color Picker"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .area: return "viewfinder"
            case .fullscreen: return "display"
            case .repeatCapture: return "arrow.counterclockwise"
            case .ocr: return "text.viewfinder"
            case .scrolling: return "arrow.up.and.down.circle"
            case .ruler: return "ruler"
            case .colorPicker: return "eyedropper"
            }
        }
    }

    @ObservedObject public var settings = AppSettings.shared
    @State private var selectedTab: Tab = .capture
    @State private var recordingTarget: ShortcutTarget? = nil
    @State private var eventMonitor: Any?
    @State private var screenCaptureGranted: Bool = PermissionsManager.shared.isScreenRecordingGranted
    @State private var accessibilityGranted: Bool = PermissionsManager.shared.isAccessibilityGranted

    public var isRecordingHotkey: Bool { recordingTarget != nil }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header with App Logo & Minimalist Tab Switcher
            HStack(spacing: 12) {
                if let logo = Self.loadAppLogo() {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                }

                Text("Shots")
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .onChange(of: selectedTab) { _ in
                    stopRecording()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            // Active Tab Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    switch selectedTab {
                    case .general:
                        GeneralTab(
                            settings: settings,
                            screenCaptureGranted: screenCaptureGranted,
                            accessibilityGranted: accessibilityGranted,
                            onChooseFolder: chooseFolder
                        )
                    case .capture:
                        CaptureTab(settings: settings)
                    case .shortcuts:
                        ShortcutsTab(
                            settings: settings,
                            recordingTarget: recordingTarget,
                            onToggleRecording: toggleRecording,
                            onClearShortcut: clearShortcut,
                            onResetShortcut: resetShortcut,
                            onClearAll: {
                                stopRecording()
                                settings.clearAllHotkeys()
                            },
                            onResetAll: {
                                stopRecording()
                                settings.resetHotkeysToDefault()
                            }
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }

            // Footer with Version in Lower Right Corner
            HStack {
                Spacer()
                Text("v\(AppConfig.version)")
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .foregroundColor(Color.secondary.opacity(0.65))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        }
        .frame(width: 480, height: 435)
        .onAppear {
            updatePermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            updatePermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            updatePermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PreferencesViewRefreshPermissions"))) { _ in
            updatePermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PreferencesWindowDidResignKey"))) { _ in
            stopRecording()
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func updatePermissions() {
        let newScreen = PermissionsManager.shared.isScreenRecordingGranted
        let newAX = PermissionsManager.shared.isAccessibilityGranted
        if screenCaptureGranted != newScreen {
            screenCaptureGranted = newScreen
        }
        if accessibilityGranted != newAX {
            accessibilityGranted = newAX
        }
    }

    // MARK: - Hotkey Recorder Handlers

    private func toggleRecording(for target: ShortcutTarget) {
        if recordingTarget == target {
            stopRecording()
        } else {
            startRecording(for: target)
        }
    }

    private func startRecording(for target: ShortcutTarget) {
        stopRecording()
        recordingTarget = target

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]) { event in
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                self.stopRecording()
                return event
            }

            if event.type == .keyDown {
                // Escape cancels
                if event.keyCode == 53 {
                    self.stopRecording()
                    return nil
                }

                // Delete or Forward Delete removes/clears the shortcut
                if event.keyCode == 51 || event.keyCode == 117 {
                    self.clearShortcut(for: target)
                    self.stopRecording()
                    return nil
                }

                let carbonMods = KeyCodes.carbonModifiers(from: event.modifierFlags)
                let isFunctionKey = (event.keyCode >= 122 && event.keyCode <= 131) || event.keyCode >= 96

                // Require at least one modifier key or a function key
                if carbonMods != 0 || isFunctionKey {
                    switch target {
                    case .area:
                        self.settings.hotkeyKeyCode = event.keyCode
                        self.settings.hotkeyModifiers = carbonMods
                    case .fullscreen:
                        self.settings.fullscreenShortcutKeyCode = event.keyCode
                        self.settings.fullscreenShortcutModifiers = carbonMods
                    case .repeatCapture:
                        self.settings.repeatShortcutKeyCode = event.keyCode
                        self.settings.repeatShortcutModifiers = carbonMods
                    case .ocr:
                        self.settings.ocrShortcutKeyCode = event.keyCode
                        self.settings.ocrShortcutModifiers = carbonMods
                    case .scrolling:
                        self.settings.scrollingShortcutKeyCode = event.keyCode
                        self.settings.scrollingShortcutModifiers = carbonMods
                    case .ruler:
                        self.settings.rulerShortcutKeyCode = event.keyCode
                        self.settings.rulerShortcutModifiers = carbonMods
                    case .colorPicker:
                        self.settings.colorPickerShortcutKeyCode = event.keyCode
                        self.settings.colorPickerShortcutModifiers = carbonMods
                    }
                    self.stopRecording()
                    return nil
                }
            }
            return nil
        }
    }

    private func stopRecording() {
        recordingTarget = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func clearShortcut(for target: ShortcutTarget) {
        let noKey = KeyCodes.noKey
        switch target {
        case .area:
            settings.hotkeyKeyCode = noKey
            settings.hotkeyModifiers = 0
        case .fullscreen:
            settings.fullscreenShortcutKeyCode = noKey
            settings.fullscreenShortcutModifiers = 0
        case .repeatCapture:
            settings.repeatShortcutKeyCode = noKey
            settings.repeatShortcutModifiers = 0
        case .ocr:
            settings.ocrShortcutKeyCode = noKey
            settings.ocrShortcutModifiers = 0
        case .scrolling:
            settings.scrollingShortcutKeyCode = noKey
            settings.scrollingShortcutModifiers = 0
        case .ruler:
            settings.rulerShortcutKeyCode = noKey
            settings.rulerShortcutModifiers = 0
        case .colorPicker:
            settings.colorPickerShortcutKeyCode = noKey
            settings.colorPickerShortcutModifiers = 0
        }
    }

    private func resetShortcut(for target: ShortcutTarget) {
        let defaultMods = UInt32(cmdKey | shiftKey)
        switch target {
        case .area:
            settings.hotkeyKeyCode = UInt16(kVK_ANSI_4)
            settings.hotkeyModifiers = defaultMods
        case .fullscreen:
            settings.fullscreenShortcutKeyCode = UInt16(kVK_ANSI_2)
            settings.fullscreenShortcutModifiers = defaultMods
        case .repeatCapture:
            settings.repeatShortcutKeyCode = UInt16(kVK_ANSI_3)
            settings.repeatShortcutModifiers = defaultMods
        case .ocr:
            settings.ocrShortcutKeyCode = UInt16(kVK_ANSI_R)
            settings.ocrShortcutModifiers = defaultMods
        case .scrolling:
            settings.scrollingShortcutKeyCode = UInt16(kVK_ANSI_5)
            settings.scrollingShortcutModifiers = defaultMods
        case .ruler:
            settings.rulerShortcutKeyCode = UInt16(kVK_ANSI_M)
            settings.rulerShortcutModifiers = defaultMods
        case .colorPicker:
            settings.colorPickerShortcutKeyCode = UInt16(kVK_ANSI_C)
            settings.colorPickerShortcutModifiers = defaultMods
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = settings.resolvedSaveDirectoryURL

        if panel.runModal() == .OK, let selectedURL = panel.url {
            settings.saveDirectoryPath = selectedURL.path
        }
        NSCursor.unhide()
        NSCursor.arrow.set()
    }

    private static let cachedAppLogo: NSImage? = {
        if let img = NSImage(named: "AppIcon"), img.isValid {
            return img
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url), img.isValid {
            return img
        }
        if let appIcon = NSApp.applicationIconImage, appIcon.isValid {
            return appIcon
        }
        let fallbackPath = "Resources/AppIcon.png"
        if FileManager.default.fileExists(atPath: fallbackPath),
           let img = NSImage(contentsOfFile: fallbackPath) {
            return img
        }
        return nil
    }()

    public static func loadAppLogo() -> NSImage? {
        return cachedAppLogo
    }
}

// MARK: - Reusable Minimalist Text Toggle Row

private struct ToggleRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            isOn.toggle()
        }) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .foregroundColor(isOn ? .accentColor : .secondary.opacity(0.6))
                    .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: isOn ? .medium : .regular))
                    .foregroundColor(isOn ? .primary : .secondary)

                Spacer()

                // Pure text toggle badge with dynamic state styling — NO switch/checkbox controls
                Text(isOn ? "ON" : "OFF")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(isOn ? .accentColor : .secondary.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isOn ? Color.accentColor.opacity(0.14) : Color(NSColor.controlColor).opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isOn ? Color.accentColor.opacity(0.4) : Color(NSColor.separatorColor).opacity(0.35), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Subviews: General Tab

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    let screenCaptureGranted: Bool
    let accessibilityGranted: Bool
    let onChooseFolder: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Main preferences card
            VStack(spacing: 0) {
                // Start at login
                ToggleRow(
                    title: "Start at login",
                    icon: "sparkles",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { newValue in
                            _ = LaunchAtLoginService.shared.setLaunchAtLogin(enabled: newValue)
                        }
                    )
                )

                Divider().padding(.horizontal, 12)

                // Save directory
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundColor(.secondary)
                        .frame(width: 18)
                    Text("Save to")
                        .font(.system(size: 13))
                    Spacer()
                    Text(settings.saveDirectoryPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 160, alignment: .trailing)
                        .help(settings.saveDirectoryPath)

                    Button("Change...") {
                        onChooseFolder()
                    }
                    .font(.system(size: 11))
                    .controlSize(.small)

                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([settings.resolvedSaveDirectoryURL])
                    }) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open Screenshots Folder in Finder")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider().padding(.horizontal, 12)

                // File format
                HStack(spacing: 10) {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                        .frame(width: 18)
                    Text("Format")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $settings.imageFormat) {
                        ForEach(ImageFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

                if settings.imageFormat == .jpg {
                    Divider().padding(.horizontal, 12)

                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.secondary)
                            .frame(width: 18)
                        Text("Quality")
                            .font(.system(size: 13))
                        Spacer()
                        Slider(
                            value: Binding(
                                get: { Double(settings.jpgQuality) },
                                set: { settings.jpgQuality = Int($0) }
                            ),
                            in: 40...100,
                            step: 5
                        )
                        .frame(width: 120)

                        Text("\(settings.jpgQuality)%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .frame(width: 38, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5))

            // System Permissions
            VStack(spacing: 0) {
                if screenCaptureGranted && accessibilityGranted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 13))
                        Text("Permissions granted")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Screen Recording • Accessibility")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 13))
                        Text("Permissions not granted")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                        Spacer()
                        Button("Grant permissions") {
                            PermissionsManager.shared.openSystemSettingsForMissingPermissions()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        (screenCaptureGranted && accessibilityGranted)
                            ? Color(NSColor.separatorColor).opacity(0.4)
                            : Color.orange.opacity(0.5),
                        lineWidth: (screenCaptureGranted && accessibilityGranted) ? 0.5 : 1.0
                    )
            )
        }
    }
}

// MARK: - Subviews: Capture Tab

private struct CaptureTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                ToggleRow(
                    title: "Copy to clipboard",
                    icon: "doc.on.clipboard",
                    isOn: $settings.copyToClipboard
                )

                Divider().padding(.horizontal, 12)

                ToggleRow(
                    title: "Include mouse cursor",
                    icon: "cursorarrow.rays",
                    isOn: $settings.includeCursor
                )

                Divider().padding(.horizontal, 12)

                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .foregroundColor(.secondary)
                        .frame(width: 18)
                    Text("Capture delay")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $settings.captureDelaySeconds) {
                        Text("Off").tag(0)
                        Text("3s").tag(3)
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider().padding(.horizontal, 12)

                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.and.down.circle")
                        .foregroundColor(.secondary)
                        .frame(width: 18)
                    Text("Scrolling speed")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $settings.scrollingCaptureSpeed) {
                        ForEach(ScrollingCaptureSpeed.allCases) { speed in
                            Text(speed.displayName).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5))
        }
    }
}

// MARK: - Subviews: Shortcuts Tab

private struct ShortcutsTab: View {
    @ObservedObject var settings: AppSettings
    let recordingTarget: PreferencesView.ShortcutTarget?
    let onToggleRecording: (PreferencesView.ShortcutTarget) -> Void
    let onClearShortcut: (PreferencesView.ShortcutTarget) -> Void
    let onResetShortcut: (PreferencesView.ShortcutTarget) -> Void
    let onClearAll: () -> Void
    let onResetAll: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Shortcuts List Card
            VStack(spacing: 0) {
                ForEach(Array(PreferencesView.ShortcutTarget.allCases.enumerated()), id: \.element.id) { index, target in
                    HStack(spacing: 10) {
                        Image(systemName: target.icon)
                            .foregroundColor(.secondary)
                            .frame(width: 18)

                        Text(target.rawValue)
                            .font(.system(size: 13))

                        Spacer()

                        // Interactive Recorder Badge
                        Button(action: {
                            onToggleRecording(target)
                        }) {
                            HStack(spacing: 5) {
                                if recordingTarget == target {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 6, height: 6)
                                    Text("Press keys...")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary)
                                } else {
                                    let str = displayString(for: target)
                                    Text(str)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(str == "None" ? .secondary : .primary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(recordingTarget == target ? Color.accentColor.opacity(0.15) : Color(NSColor.controlColor))
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(recordingTarget == target ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)

                        // Clear/Remove Shortcut
                        Button(action: {
                            onClearShortcut(target)
                        }) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isAssigned(for: target))
                        .opacity(isAssigned(for: target) ? 0.75 : 0.15)
                        .help("Clear shortcut")

                        // Reset to default
                        Button(action: {
                            onResetShortcut(target)
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDefault(for: target))
                        .opacity(!isDefault(for: target) ? 0.75 : 0.15)
                        .help("Reset to default")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)

                    if index < PreferencesView.ShortcutTarget.allCases.count - 1 {
                        Divider().padding(.horizontal, 12)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5))

            // Conflict Warning Banner
            if settings.isHotkeyConflict, let msg = settings.hotkeyErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }

            // Footer
            HStack {
                Text("Click shortcut to rebind • Esc cancels")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Button("Reset All") {
                    onResetAll()
                }
                .font(.system(size: 11))
                .buttonStyle(.link)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
    }

    private func displayString(for target: PreferencesView.ShortcutTarget) -> String {
        switch target {
        case .area: return settings.areaShortcutDisplayString
        case .fullscreen: return settings.fullscreenShortcutDisplayString
        case .repeatCapture: return settings.repeatShortcutDisplayString
        case .ocr: return settings.ocrShortcutDisplayString
        case .scrolling: return settings.scrollingShortcutDisplayString
        case .ruler: return settings.rulerShortcutDisplayString
        case .colorPicker: return settings.colorPickerShortcutDisplayString
        }
    }

    private func isAssigned(for target: PreferencesView.ShortcutTarget) -> Bool {
        switch target {
        case .area:
            return KeyCodes.isShortcutAssigned(keyCode: settings.hotkeyKeyCode, carbonMods: settings.hotkeyModifiers)
        case .fullscreen:
            return KeyCodes.isShortcutAssigned(keyCode: settings.fullscreenShortcutKeyCode, carbonMods: settings.fullscreenShortcutModifiers)
        case .repeatCapture:
            return KeyCodes.isShortcutAssigned(keyCode: settings.repeatShortcutKeyCode, carbonMods: settings.repeatShortcutModifiers)
        case .ocr:
            return KeyCodes.isShortcutAssigned(keyCode: settings.ocrShortcutKeyCode, carbonMods: settings.ocrShortcutModifiers)
        case .scrolling:
            return KeyCodes.isShortcutAssigned(keyCode: settings.scrollingShortcutKeyCode, carbonMods: settings.scrollingShortcutModifiers)
        case .ruler:
            return KeyCodes.isShortcutAssigned(keyCode: settings.rulerShortcutKeyCode, carbonMods: settings.rulerShortcutModifiers)
        case .colorPicker:
            return KeyCodes.isShortcutAssigned(keyCode: settings.colorPickerShortcutKeyCode, carbonMods: settings.colorPickerShortcutModifiers)
        }
    }

    private func isDefault(for target: PreferencesView.ShortcutTarget) -> Bool {
        let defaultMods = UInt32(cmdKey | shiftKey)
        switch target {
        case .area:
            return settings.hotkeyKeyCode == UInt16(kVK_ANSI_4) && settings.hotkeyModifiers == defaultMods
        case .fullscreen:
            return settings.fullscreenShortcutKeyCode == UInt16(kVK_ANSI_2) && settings.fullscreenShortcutModifiers == defaultMods
        case .repeatCapture:
            return settings.repeatShortcutKeyCode == UInt16(kVK_ANSI_3) && settings.repeatShortcutModifiers == defaultMods
        case .ocr:
            return settings.ocrShortcutKeyCode == UInt16(kVK_ANSI_R) && settings.ocrShortcutModifiers == defaultMods
        case .scrolling:
            return settings.scrollingShortcutKeyCode == UInt16(kVK_ANSI_5) && settings.scrollingShortcutModifiers == defaultMods
        case .ruler:
            return settings.rulerShortcutKeyCode == UInt16(kVK_ANSI_M) && settings.rulerShortcutModifiers == defaultMods
        case .colorPicker:
            return settings.colorPickerShortcutKeyCode == UInt16(kVK_ANSI_C) && settings.colorPickerShortcutModifiers == defaultMods
        }
    }
}
