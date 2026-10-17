import Foundation
import CoreGraphics
import AppKit

/// Notification HUD toast pill matching the "hit cmd+q again to quit" styling.
public final class EditorToastView: NSVisualEffectView {
    public static let sharedIdentifier = NSUserInterfaceItemIdentifier("ImpactCopiedToast")

    private var dismissWorkItem: DispatchWorkItem?
    private let label: NSTextField

    public init(text: String = "Copied to Clipboard") {
        self.label = NSTextField(labelWithString: text)
        super.init(frame: NSRect(x: 0, y: 0, width: 180, height: 34))

        identifier = EditorToastView.sharedIdentifier
        material = .hudWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows or refreshes the HUD toast pill in the given container
    public static func show(in container: NSView, below anchorView: NSView? = nil, text: String = "Copied to Clipboard") {
        if let existing = container.subviews.first(where: { $0.identifier == sharedIdentifier }) as? EditorToastView {
            existing.label.stringValue = text
            existing.pulseAndResetTimer()
            return
        }

        let toast = EditorToastView(text: text)
        toast.alphaValue = 0.0
        container.addSubview(toast)

        NSLayoutConstraint.activate([
            toast.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            toast.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 20)
        ])
        container.layoutSubtreeIfNeeded()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            toast.animator().alphaValue = 1.0
        }

        toast.scheduleDismissal()
    }

    private func pulseAndResetTimer() {
        dismissWorkItem?.cancel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            self.animator().alphaValue = 0.60
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                self.animator().alphaValue = 1.0
            }
        }
        scheduleDismissal()
    }

    private func scheduleDismissal() {
        dismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                self.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                self?.removeFromSuperview()
            })
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
}
