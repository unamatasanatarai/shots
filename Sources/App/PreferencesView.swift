import SwiftUI
import Carbon
import Cocoa

public struct PreferencesView: View {
    @ObservedObject public var settings = AppSettings.shared
    @State private var isRecordingHotkey = false
    @State private var eventMonitor: Any?
    @State private var screenCaptureGranted: Bool = CGPreflightScreenCaptureAccess()
    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()

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
                    // Global Shortcut Box
                    GroupBox(label: Label("Global Shortcut", systemImage: "keyboard")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Capture Trigger:")
                                    .font(.system(size: 13, weight: .medium))

                                Spacer()

                                // Interactive Hotkey Recorder Button
                                Button(action: {
                                    toggleRecording()
                                }) {
                                    HStack(spacing: 6) {
                                        if isRecordingHotkey {
                                            Circle()
                                                .fill(Color.red)
                                                .frame(width: 8, height: 8)
                                            Text("Press keys (Esc to cancel)...")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.primary)
                                        } else {
                                            Text(settings.hotkeyDisplayString)
                                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                                .foregroundColor(.primary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isRecordingHotkey ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(isRecordingHotkey ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)

                                Button("Reset") {
                                    stopRecording()
                                    settings.resetHotkeyToDefault()
                                }
                                .font(.system(size: 11))
                                .disabled(settings.hotkeyKeyCode == UInt16(kVK_ANSI_1) && settings.hotkeyModifiers == UInt32(cmdKey | shiftKey))
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

                            Text("Press the hotkey globally to initiate region selection or capture active screen.")
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
        .frame(width: 480, height: 500)
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - Hotkey Recorder Handlers

    private func toggleRecording() {
        if isRecordingHotkey {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecordingHotkey = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                // Escape cancels
                if event.keyCode == 53 {
                    self.stopRecording()
                    return nil
                }

                // Delete resets to default
                if event.keyCode == 51 {
                    self.settings.resetHotkeyToDefault()
                    self.stopRecording()
                    return nil
                }

                let carbonMods = KeyCodes.carbonModifiers(from: event.modifierFlags)
                let isFunctionKey = (event.keyCode >= 122 && event.keyCode <= 131) || event.keyCode >= 96

                // Require at least one modifier key or a function key
                if carbonMods != 0 || isFunctionKey {
                    self.settings.hotkeyKeyCode = event.keyCode
                    self.settings.hotkeyModifiers = carbonMods
                    self.stopRecording()
                    return nil
                }
            }
            return nil
        }
    }

    private func stopRecording() {
        isRecordingHotkey = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
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
