import Cocoa
import SwiftUI

public final class PreferencesWindowController: NSWindowController {
    public static let shared = PreferencesWindowController()

    private init() {
        let hostingController = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 410),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Shots! Preferences"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.level = .floating

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showWindow() {
        guard let window = self.window else { return }

        // Refresh root view to re-evaluate screen capture permissions
        (window.contentViewController as? NSHostingController<PreferencesView>)?.rootView = PreferencesView()

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
