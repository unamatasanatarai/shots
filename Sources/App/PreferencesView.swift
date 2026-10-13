import SwiftUI
import Carbon
import Cocoa

public struct PreferencesView: View {
    enum ShortcutTarget: String, CaseIterable, Identifiable {
        case area = "Area Screenshot"
        case fullscreen = "Fullscreen Screenshot"
        case repeatCapture = "Repeat Previous"
        case ocr = "OCR Recognition"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .area: return "viewfinder"
            case .fullscreen: return "display"
            case .repeatCapture: return "arrow.counterclockwise"
            case .ocr: return "text.viewfinder"
            }
        }
    }

    @ObservedObject public var settings = AppSettings.shared
    @State private var recordingTarget: ShortcutTarget? = nil
    @State private var eventMonitor: Any?
    @State private var screenCaptureGranted: Bool = CGPreflightScreenCaptureAccess()
    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()

    public var isRecordingHotkey: Bool { recordingTarget != nil }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Shots! Preferences")
                        .font(.system(size: 16, weight: .bold))
                    Text("Configure global hotkey, destination folder, and capture behavior")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Global Shortcuts Box
                    GroupBox(label: Label("Global Shortcuts", systemImage: "keyboard")) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(ShortcutTarget.allCases) { target in
                                HStack {
                                    Label(target.rawValue, systemImage: target.icon)
                                        .font(.system(size: 13, weight: .medium))

                                    Spacer()

                                    // Interactive Hotkey Recorder Button
                                    Button(action: {
                                        toggleRecording(for: target)
                                    }) {
                                        HStack(spacing: 6) {
                                            if recordingTarget == target {
                                                Circle()
                                                    .fill(Color.red)
                                                    .frame(width: 8, height: 8)
                                                Text("Press keys (Esc to cancel)...")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(.primary)
                                            } else {
                                                Text(displayString(for: target))
                                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                                    .foregroundColor(.primary)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(recordingTarget == target ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(recordingTarget == target ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: 1.5)
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    Button("Reset") {
                                        stopRecording()
                                        resetShortcut(for: target)
                                    }
                                    .font(.system(size: 11))
                                    .disabled(isDefault(for: target))
                                }

                                if target != ShortcutTarget.allCases.last {
                                    Divider()
                                }
                            }

                            if settings.isHotkeyConflict, let msg = settings.hotkeyErrorMessage {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text(msg)
                                        .font(.system(size: 11))
                                        .foregroundColor(.orange)
                                }
                                .padding(6)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(6)
                            }

                            Text("Trigger screenshots instantly from any application with customizable global shortcuts.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                    }

                    // General Startup Box
                    GroupBox(label: Label("General", systemImage: "gearshape")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Launch Shots! automatically at login", isOn: Binding(
                                get: { settings.launchAtLogin },
                                set: { newValue in
                                    _ = LaunchAtLoginService.shared.setLaunchAtLogin(enabled: newValue)
                                }
                            ))
                            Text("Starts Shots! quietly in the background when you log into your Mac.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                    }

                    // Storage Box
                    GroupBox(label: Label("Storage Destination", systemImage: "folder")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Destination Folder:")
                                        .font(.system(size: 13, weight: .medium))
                                    Text(settings.saveDirectoryPath)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()

                                Button("Choose...") {
                                    chooseFolder()
                                }

                                Button("Reveal") {
                                    NSWorkspace.shared.activateFileViewerSelecting([settings.resolvedSaveDirectoryURL])
                                }
                            }

                            Text("Screenshots are saved as: shot_YYYYMMDD_HHMMSS.\(settings.imageFormat.fileExtension)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                    }

                    // Behavior Box (Capture Behavior Toggles)
                    GroupBox(label: Label("Capture Behavior", systemImage: "slider.horizontal.3")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Post-Capture Action")
                                .font(.system(size: 13, weight: .medium))

                            Picker("", selection: $settings.postCaptureAction) {
                                ForEach(PostCaptureAction.allCases) { action in
                                    Text(action.displayName).tag(action)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text("Configure whether screenshots are saved to disk, copied directly to the clipboard, or both.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            Divider()

                            Toggle("Save screenshot to disk", isOn: $settings.saveToDisk)
                            Toggle("Copy screenshot to clipboard", isOn: $settings.copyToClipboard)
                        }
                        .padding(10)
                    }

                    // Scrolling Capture Box
                    GroupBox(label: Label("Scrolling Capture", systemImage: "arrow.up.and.down.circle")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Capture Speed")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Controls scroll step distance and settling delay during automatic scrolling.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }

                            Picker("Scrolling Speed", selection: $settings.scrollingCaptureSpeed) {
                                ForEach(ScrollingCaptureSpeed.allCases) { speed in
                                    Text(speed.displayName).tag(speed)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(settings.scrollingCaptureSpeed.detailDescription)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                    }

                    // System Permissions Box
                    GroupBox(label: Label("System Permissions", systemImage: "lock.shield")) {
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Screen Recording Permission")
                                        .font(.system(size: 12, weight: .medium))
                                    Text(screenCaptureGranted ? "Granted — ready to capture all displays" : "Access required for capturing display pixels")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if screenCaptureGranted {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Granted")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.green)
                                    }
                                } else {
                                    Button("Open Settings") {
                                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                }
                            }

                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Accessibility Permission")
                                        .font(.system(size: 12, weight: .medium))
                                    Text(accessibilityGranted ? "Granted — menus stay open and videos keep playing" : "Required to prevent clicks from closing menus during selection")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if accessibilityGranted {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Granted")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.green)
                                    }
                                } else {
                                    Button("Open Settings") {
                                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                                        _ = AXIsProcessTrustedWithOptions(options)
                                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(10)
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Text("Status bar only • Runs quietly in background")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Button("Done") {
                    stopRecording()
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 480, height: 530)
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

                // Delete resets to default
                if event.keyCode == 51 {
                    self.resetShortcut(for: target)
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

    private func resetShortcut(for target: ShortcutTarget) {
        switch target {
        case .area:
            settings.hotkeyKeyCode = UInt16(kVK_ANSI_1)
            settings.hotkeyModifiers = UInt32(cmdKey | shiftKey)
        case .fullscreen:
            settings.fullscreenShortcutKeyCode = UInt16(kVK_ANSI_2)
            settings.fullscreenShortcutModifiers = UInt32(cmdKey | shiftKey)
        case .repeatCapture:
            settings.repeatShortcutKeyCode = UInt16(kVK_ANSI_R)
            settings.repeatShortcutModifiers = UInt32(cmdKey | shiftKey)
        case .ocr:
            settings.ocrShortcutKeyCode = UInt16(kVK_ANSI_O)
            settings.ocrShortcutModifiers = UInt32(cmdKey | shiftKey)
        }
    }

    private func displayString(for target: ShortcutTarget) -> String {
        switch target {
        case .area: return settings.areaShortcutDisplayString
        case .fullscreen: return settings.fullscreenShortcutDisplayString
        case .repeatCapture: return settings.repeatShortcutDisplayString
        case .ocr: return settings.ocrShortcutDisplayString
        }
    }

    private func isDefault(for target: ShortcutTarget) -> Bool {
        switch target {
        case .area:
            return settings.hotkeyKeyCode == UInt16(kVK_ANSI_1) && settings.hotkeyModifiers == UInt32(cmdKey | shiftKey)
        case .fullscreen:
            return settings.fullscreenShortcutKeyCode == UInt16(kVK_ANSI_2) && settings.fullscreenShortcutModifiers == UInt32(cmdKey | shiftKey)
        case .repeatCapture:
            return settings.repeatShortcutKeyCode == UInt16(kVK_ANSI_R) && settings.repeatShortcutModifiers == UInt32(cmdKey | shiftKey)
        case .ocr:
            return settings.ocrShortcutKeyCode == UInt16(kVK_ANSI_O) && settings.ocrShortcutModifiers == UInt32(cmdKey | shiftKey)
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
