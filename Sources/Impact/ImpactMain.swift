import AppKit
import Foundation

@main
struct ImpactMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = ImpactAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
