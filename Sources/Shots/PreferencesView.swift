import SwiftUI
import Carbon
import Cocoa

public struct PreferencesView: View {
    public enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case capture = "Capture"
        case shortcuts = "Shortcuts"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .general: return "gearshape"
            case .capture: return "camera"
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
    @State private var selectedTab: Tab = .general
    @State private var recordingTarget: ShortcutTarget? = nil
    @State private var eventMonitor: Any?
    @State private var screenCaptureGranted: Bool = CGPreflightScreenCaptureAccess()
    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()

    public var isRecordingHotkey: Bool { recordingTarget != nil }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Minimalistic Tab Switcher
            HStack {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            // Active Tab Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
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
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 480, height: 500)
        .onDisappear {
            stopRecording()
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

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
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
            // Startup Card
            VStack(alignment: .leading, spacing: 8) {
                Text("Startup")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                            .font(.system(size: 13, weight: .regular))
                        Text("Start Shots automatically when you log into your Mac")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { newValue in
                            _ = LaunchAtLoginService.shared.setLaunchAtLogin(enabled: newValue)
                        }
                    ))
                    .labelsHidden()
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))

            // Storage Location Card
            VStack(alignment: .leading, spacing: 10) {
                Text("Storage Location")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save screenshots to")
                            .font(.system(size: 13, weight: .regular))
                        Text(settings.saveDirectoryPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()

                    Button("Change Location...") {
                        onChooseFolder()
                    }
                    .font(.system(size: 12))

                    Button(action: {
                        NSWorkspace.shared.open(settings.resolvedSaveDirectoryURL)
                    }) {
                        Image(systemName: "folder")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("Open Screenshots Folder")

                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([settings.resolvedSaveDirectoryURL])
                    }) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))

            // Image Format Card
            VStack(alignment: .leading, spacing: 10) {
                Text("Image Format & Quality")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack {
                    Text("File format")
                        .font(.system(size: 13, weight: .regular))
                    Spacer()
                    Picker("", selection: $settings.imageFormat) {
                        ForEach(ImageFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                if settings.imageFormat == .jpg {
                    Divider()

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("JPG Quality")
                                .font(.system(size: 13, weight: .regular))
                            Text("Higher quality produces larger file sizes")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
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
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))

            // Permissions Card
            VStack(alignment: .leading, spacing: 8) {
                Text("System Permissions")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack {
                    Label("Screen Recording", systemImage: "display")
                        .font(.system(size: 12))
                    Spacer()
                    if screenCaptureGranted {
                        Text("Granted")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    } else {
                        Button("Grant Access") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.system(size: 11))
                    }
                }

                Divider()

                HStack {
                    Label("Accessibility", systemImage: "hand.tap")
                        .font(.system(size: 12))
                    Spacer()
                    if accessibilityGranted {
                        Text("Granted")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    } else {
                        Button("Grant Access") {
                            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                            _ = AXIsProcessTrustedWithOptions(options)
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.system(size: 11))
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
        }
    }
}

// MARK: - Subviews: Capture Tab

private struct CaptureTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 12) {
            // Clipboard Action Card
            VStack(alignment: .leading, spacing: 8) {
                Text("After Capture")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Copy to clipboard")
                            .font(.system(size: 13, weight: .regular))
                        Text("Automatically copy screenshot image to clipboard after capture")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.copyToClipboard)
                        .labelsHidden()
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))

            // Capture Behavior Card
            VStack(alignment: .leading, spacing: 10) {
                Text("Capture Options")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include mouse cursor")
                            .font(.system(size: 13, weight: .regular))
                        Text("Show mouse cursor arrow in captured screenshots")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.includeCursor)
                        .labelsHidden()
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Timer delay")
                            .font(.system(size: 13, weight: .regular))
                        Text("Countdown delay before taking a screenshot")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $settings.captureDelaySeconds) {
                        Text("None").tag(0)
                        Text("3s").tag(3)
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))

            // Scrolling Capture Card
            VStack(alignment: .leading, spacing: 8) {
                Text("Scrolling Capture")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack {
                    Text("Capture speed")
                        .font(.system(size: 13, weight: .regular))
                    Spacer()
                    Picker("", selection: $settings.scrollingCaptureSpeed) {
                        ForEach(ScrollingCaptureSpeed.allCases) { speed in
                            Text(speed.displayName).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                HStack {
                    Spacer()
                    Text(scrollingSpeedNote)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
        }
    }

    private var scrollingSpeedNote: String {
        switch settings.scrollingCaptureSpeed {
        case .slow: return "Step: 45 px • 500 ms pause (Smooth, heavy pages)"
        case .normal: return "Step: 60 px • 350 ms pause (Recommended)"
        case .fast: return "Step: 90 px • 200 ms pause (Fast native windows)"
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
        VStack(spacing: 10) {
            // Master Global Shortcuts Toggle
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable global shortcuts")
                            .font(.system(size: 13, weight: .regular))
                        Text("Trigger capture tools with global keyboard shortcuts")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.globalHotkeysEnabled)
                        .labelsHidden()
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))

            // Shortcuts List Card
            VStack(spacing: 8) {
                ForEach(PreferencesView.ShortcutTarget.allCases) { target in
                    HStack {
                        Label(target.rawValue, systemImage: target.icon)
                            .font(.system(size: 13, weight: .regular))

                        Spacer()

                        // Interactive Recorder Badge
                        Button(action: {
                            onToggleRecording(target)
                        }) {
                            HStack(spacing: 5) {
                                if recordingTarget == target {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 7, height: 7)
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
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(recordingTarget == target ? Color.accentColor.opacity(0.12) : Color(NSColor.controlColor))
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(recordingTarget == target ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.7), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!settings.globalHotkeysEnabled)

                        // Clear/Remove Shortcut
                        Button(action: {
                            onClearShortcut(target)
                        }) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!settings.globalHotkeysEnabled || !isAssigned(for: target))
                        .opacity((settings.globalHotkeysEnabled && isAssigned(for: target)) ? 0.75 : 0.2)
                        .help("Remove shortcut")

                        // Reset to default
                        Button(action: {
                            onResetShortcut(target)
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!settings.globalHotkeysEnabled || isDefault(for: target))
                        .opacity((settings.globalHotkeysEnabled && !isDefault(for: target)) ? 0.75 : 0.2)
                        .help("Reset to default")
                    }

                    if target != PreferencesView.ShortcutTarget.allCases.last {
                        Divider()
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
            .opacity(settings.globalHotkeysEnabled ? 1.0 : 0.55)

            // Conflict Warning Banner
            if settings.globalHotkeysEnabled && settings.isHotkeyConflict, let msg = settings.hotkeyErrorMessage {
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

            HStack {
                Text("Click to rebind • Delete to remove • Esc to cancel")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Button("Remove All") {
                    onClearAll()
                }
                .font(.system(size: 11))
                .buttonStyle(.link)
                .disabled(!settings.globalHotkeysEnabled)

                Text("•")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))

                Button("Reset All") {
                    onResetAll()
                }
                .font(.system(size: 11))
                .buttonStyle(.link)
            }
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
