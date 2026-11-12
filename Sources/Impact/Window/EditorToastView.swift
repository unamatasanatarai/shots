import Foundation
import CoreGraphics
import AppKit

/// Notification HUD toast pill matching the "hit cmd+q again to quit" styling.
public final class EditorToastView: NSVisualEffectView {
    public static let sharedIdentifier = NSUserInterfaceItemIdentifier("ImpactCopiedToast")

    private var dismissWorkItem: DispatchWorkItem?
    public let label: NSTextField
    public let iconView: NSImageView

    public init(text: String = "Copied to Clipboard") {
        self.label = NSTextField(labelWithString: text)
        self.iconView = NSImageView()
        super.init(frame: NSRect(x: 0, y: 0, width: 190, height: 34))

        identifier = EditorToastView.sharedIdentifier
        applyToastPillStyle()
        translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = ImpactTheme.toastForeground
        label.alignment = .left
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        updateIcon(for: text)

        addSubview(iconView)
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTheme()
    }

    private func updateTheme() {
        refreshToastPillColors()
        label.textColor = ImpactTheme.toastForeground
    }

    public func updateContent(text: String) {
        label.stringValue = text
        updateIcon(for: text)
    }

    private func updateIcon(for text: String) {
        let isError = text.localizedCaseInsensitiveContains("could not") || text.localizedCaseInsensitiveContains("failed")
        let symbolName = isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        let symbolColor = isError ? NSColor.systemOrange : NSColor.systemGreen
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        iconView.contentTintColor = symbolColor
    }

    /// Shows or refreshes the HUD toast pill in the given container
    public static func show(in container: NSView, below anchorView: NSView? = nil, text: String = "Copied to Clipboard") {
        if let existing = container.subviews.first(where: { $0.identifier == sharedIdentifier }) as? EditorToastView {
            existing.updateContent(text: text)
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

    /// Bumped by every (re)scheduled dismissal: a fade-out finishing after the toast was shown again must not remove it
    private var dismissalGeneration = 0

    private func scheduleDismissal() {
        dismissWorkItem?.cancel()
        dismissalGeneration += 1
        let generation = dismissalGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                self.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                guard let self = self, self.dismissalGeneration == generation else { return }
                self.removeFromSuperview()
            })
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
}
