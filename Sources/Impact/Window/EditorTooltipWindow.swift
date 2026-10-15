import Foundation
import CoreGraphics
import AppKit

/// Floating HUD tooltip window with industry-standard 450ms delay and instant adjacent switching
public final class EditorTooltipWindow: NSWindow {
    public static let shared = EditorTooltipWindow()

    private let label = NSTextField(labelWithString: "")
    private var pendingTimer: Timer?
    private weak var currentTargetView: NSView?

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 24),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        hasShadow = true

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .withinWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 5.0
        effect.layer?.masksToBounds = true
        effect.layer?.borderColor = NSColor(white: 1.0, alpha: 0.18).cgColor
        effect.layer?.borderWidth = 0.5
        effect.translatesAutoresizingMaskIntoConstraints = false
        contentView = effect

        label.font = NSFont.systemFont(ofSize: 11.0, weight: .medium)
        label.textColor = NSColor(white: 0.95, alpha: 1.0)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDeactivate),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func handleWindowDeactivate() {
        hide()
    }

    /// Schedule tooltip with industry-standard 450ms delay, or fast 50ms transition if already active
    public func schedule(text: String, for view: NSView) {
        guard !text.isEmpty else {
            hide()
            return
        }

        pendingTimer?.invalidate()
        pendingTimer = nil

        let wasVisible = isVisible && currentTargetView != nil
        let delay: TimeInterval = wasVisible ? 0.05 : 0.45

        currentTargetView = view
        pendingTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self, weak view] _ in
            guard let self = self, let target = view, self.currentTargetView == target else { return }
            self.show(text: text, for: target)
        }
    }

    private func show(text: String, for view: NSView) {
        guard let window = view.window else { return }
        label.stringValue = text
        let textSize = label.intrinsicContentSize
        let width = ceil(textSize.width + 16.0)
        let height: CGFloat = 24.0

        let rectInWindow = view.convert(view.bounds, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)

        // Center horizontally below the button with a 6px gap
        let x = rectOnScreen.midX - width / 2.0
        let y = rectOnScreen.minY - height - 6.0

        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        alphaValue = 1.0
        orderFront(nil)
    }

    public func hide() {
        pendingTimer?.invalidate()
        pendingTimer = nil
        currentTargetView = nil
        orderOut(nil)
    }
}
