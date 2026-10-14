import AppKit
import Foundation

public final class ImpactAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let args = CommandLine.arguments
        if args.contains("--test-editor") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ImpactAppCoordinator.shared.openTestImage()
            }
        } else if let idx = args.firstIndex(of: "--file"), idx + 1 < args.count {
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
            // Default: if launched with no arguments, open test-image or open dialog
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ImpactAppCoordinator.shared.openTestImage()
            }
        }
    }

    public func application(_ application: NSApplication, openFile filename: String) -> Bool {
        ImpactAppCoordinator.shared.openImageFile(url: URL(fileURLWithPath: filename))
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
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
