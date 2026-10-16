import Cocoa
import SwiftUI

public final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = PreferencesWindowController()

    private init() {
        let hostingController = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(
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
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        NSCursor.unhide()
        NSCursor.arrow.set()
    }

    public func windowDidResignKey(_ notification: Notification) {
        NotificationCenter.default.post(name: NSNotification.Name("PreferencesWindowDidResignKey"), object: nil)
    }
}
