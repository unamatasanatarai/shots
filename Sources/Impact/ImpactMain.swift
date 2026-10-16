import AppKit
import Foundation

public final class ImpactAppDelegate: NSObject, NSApplicationDelegate {
    private var lastCmdQTime: TimeInterval = 0
    /// Tracks whether a file was delivered via Apple Events (Finder "Open With", etc.)
    private var receivedOpenFileEvent: Bool = false

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupDoubleCmdQMonitor()

        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--file"), idx + 1 < args.count {
            let path = args[idx + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ImpactAppCoordinator.shared.openImageFile(url: URL(fileURLWithPath: path))
            }
        } else if args.count > 1 && !args[1].hasPrefix("-") {
            let path = args[1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ImpactAppCoordinator.shared.openImageFile(url: URL(fileURLWithPath: path))
            }
        } else {
            // If macOS delivered an openFile Apple Event (e.g. Finder "Open With"), it arrives
            // between didFinishLaunching and next cycle. Wait briefly to skip welcome if file is incoming.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self, !self.receivedOpenFileEvent else { return }
                ImpactAppCoordinator.shared.openWelcome()
            }
        }
    }

    public func application(_ application: NSApplication, openFile filename: String) -> Bool {
        receivedOpenFileEvent = true
        ImpactAppCoordinator.shared.openImageFile(url: URL(fileURLWithPath: filename))
        return true
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            ImpactAppCoordinator.shared.openWelcome()
        }
        return true
    }

    /// Always return false — termination after last window close is handled by
    /// ImpactAppCoordinator's onClose callback with a delayed check, which avoids
    /// the race condition during window swaps (old panel closed before new one shown).
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func setupDoubleCmdQMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Check for Cmd+Q (keyCode 12 on macOS QWERTY, charactersIgnoringModifiers == "q")
            let isCommand = event.modifierFlags.contains(.command)
            let isQ = event.keyCode == 12 || event.charactersIgnoringModifiers?.lowercased() == "q"

            if isCommand && isQ {
                let now = ProcessInfo.processInfo.systemUptime
                let elapsed = now - self.lastCmdQTime

                if elapsed <= 1.0 {
                    // Double Cmd+Q triggered -> quit application
                    NSApp.terminate(nil)
                    return nil
                } else {
                    // First Cmd+Q press -> record timestamp and show prompt
                    self.lastCmdQTime = now
                    self.showDoubleCmdQPrompt()
                    return nil
                }
            }

            return event
        }
    }

    private func showDoubleCmdQPrompt() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }

        // Subtle overlay HUD pill inside the active window
        let pillId = NSUserInterfaceItemIdentifier("DoubleCmdQPromptPill")
        window.contentView?.subviews.first(where: { $0.identifier == pillId })?.removeFromSuperview()

        let pill = NSVisualEffectView()
        pill.identifier = pillId
        pill.material = .hudWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 16
        pill.layer?.masksToBounds = true
        pill.layer?.borderWidth = 1.0
        pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        pill.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Press ⌘Q again to quit")
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)

        if let container = window.contentView {
            container.addSubview(pill)
            NSLayoutConstraint.activate([
                pill.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                pill.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -40),
                pill.heightAnchor.constraint(equalToConstant: 34),

                label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16),
                label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -16),
                label.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
            ])

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak pill] in
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    pill?.animator().alphaValue = 0.0
                }, completionHandler: {
                    pill?.removeFromSuperview()
                })
            }
        }
    }
}

@main
struct ImpactMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = ImpactAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
