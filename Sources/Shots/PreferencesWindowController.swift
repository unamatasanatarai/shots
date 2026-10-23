import Cocoa
import SwiftUI

public final class PreferencesWindow: NSWindow {
    override public func cancelOperation(_ sender: Any?) {
        close()
    }

    override public func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            close()
            return
        }
        super.keyDown(with: event)
    }

    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

public final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = PreferencesWindowController()

    /// Re-checks missing permissions while the window is open; stopped on close so a hidden window never wakes the app
    private var permissionPollTimer: Timer?

    private init() {
        let hostingController = NSHostingController(rootView: PreferencesView())
        let window = PreferencesWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 435),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Shots Preferences"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        window.acceptsMouseMovedEvents = true

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showWindow() {
        guard let window = self.window else { return }

        // Restore cursor visibility and system arrow cursor
        NSCursor.unhide()
        NSCursor.arrow.set()
        CGDisplayShowCursor(kCGNullDirectDisplay)

        // Signal PreferencesView to re-evaluate permissions without discarding view state
        NotificationCenter.default.post(name: NSNotification.Name("PreferencesViewRefreshPermissions"), object: nil)

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startPermissionPolling()
    }

    private func startPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
        guard !PermissionsManager.shared.hasRequiredPermissions else { return }
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] timer in
            NotificationCenter.default.post(name: NSNotification.Name("PreferencesViewRefreshPermissions"), object: nil)
            if PermissionsManager.shared.hasRequiredPermissions {
                timer.invalidate()
                self?.permissionPollTimer = nil
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .default)
        permissionPollTimer = timer
    }

    public func windowWillClose(_ notification: Notification) {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        NSCursor.unhide()
        NSCursor.arrow.set()
    }

    public func windowDidResignKey(_ notification: Notification) {
        NotificationCenter.default.post(name: NSNotification.Name("PreferencesWindowDidResignKey"), object: nil)
    }
}
