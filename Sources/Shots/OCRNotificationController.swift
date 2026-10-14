import Cocoa
import SwiftUI

public final class OCRNotificationController {
    public static let shared = OCRNotificationController()

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private let notificationWidth: CGFloat = 250.0

    public init() {}

    // MARK: - Public Presentation API

    public func show(snippet: String, duration: TimeInterval = 6.0) {
        if Thread.isMainThread {
            presentNotification(snippet: snippet, duration: duration)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.presentNotification(snippet: snippet, duration: duration)
            }
        }
    }

    public func dismiss() {
        if Thread.isMainThread {
            fadeOutAndClose()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.fadeOutAndClose()
            }
        }
    }

    // MARK: - Internal Presentation

    private func presentNotification(snippet: String, duration: TimeInterval) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        let targetScreen = findTargetScreen()
        let cleanSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        let displaySnippet = cleanSnippet.isEmpty ? " " : cleanSnippet

        let contentView = OCRNotificationView(
            snippet: displaySnippet,
            logoImage: resolveAppLogo(),
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingController = NSHostingController(rootView: contentView)
        let fittingSize = hostingController.view.fittingSize
        let panelHeight = max(52, fittingSize.height)

        let screenFrame = targetScreen.frame
        let visibleFrame = targetScreen.visibleFrame

        let x = round(screenFrame.midX - (notificationWidth / 2.0))
        let y = round(visibleFrame.maxY - panelHeight - 12.0)
        let panelFrame = NSRect(x: x, y: y, width: notificationWidth, height: panelHeight)

        let targetPanel: NSPanel
        if let existing = panel {
            targetPanel = existing
            targetPanel.contentViewController = hostingController
            targetPanel.setFrame(panelFrame, display: true)
        } else {
            let newPanel = NSPanel(
                contentRect: panelFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = true
            newPanel.hidesOnDeactivate = false
            newPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 2)
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.contentViewController = hostingController
            self.panel = newPanel
            targetPanel = newPanel
        }

        targetPanel.alphaValue = 0.0
        targetPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            targetPanel.animator().alphaValue = 1.0
        }

        // Hang for 6 seconds, then fade out
        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOutAndClose()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func fadeOutAndClose() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        guard let p = panel, p.isVisible else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            p.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self, let activePanel = self.panel else { return }
            if activePanel.alphaValue == 0.0 {
                activePanel.orderOut(nil)
            }
        })
    }

    // MARK: - Helpers

    private func findTargetScreen() -> NSScreen {
        let mouseLoc = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    private func resolveAppLogo() -> NSImage? {
        if let appIcon = NSApp.applicationIconImage, appIcon.isValid {
            return appIcon
        }
        if let icon = NSImage(named: "AppIcon"), icon.isValid {
            return icon
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png") ??
                     Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return nil
    }
}

// MARK: - SwiftUI Notification View

private struct OCRNotificationView: View {
    let snippet: String
    let logoImage: NSImage?
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // App Logo
            if let logo = logoImage {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: 32, height: 32)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            // Notification Text & Snippet
            VStack(alignment: .leading, spacing: 3) {
                Text("Text copied to clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(snippet)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.85))
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 250)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.94))

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss()
        }
    }
}
