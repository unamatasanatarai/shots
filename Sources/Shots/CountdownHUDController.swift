import Cocoa

/// Floating HUD window that displays a visual countdown (3... 2... 1...)
/// on the active screen before a delayed capture is performed.
/// Click-through, borderless, silent, and keeps the system cursor visible.
public final class CountdownHUDController {
    public static let shared = CountdownHUDController()

    private var hudPanel: NSPanel?
    private var numberLabel: NSTextField?
    private var subtitleLabel: NSTextField?
    private var countdownTimer: Timer?
    private var remainingSeconds: Int = 0

    private var onCompleteHandler: (() -> Void)?
    private var onCancelHandler: (() -> Void)?

    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    public private(set) var isCountingDown: Bool = false

    private init() {}

    // MARK: - Public API

    /// Starts a visual countdown for the specified number of seconds.
    /// - Parameters:
    ///   - seconds: Number of seconds to count down (must be > 0).
    ///   - screen: The screen on which the HUD should appear (defaults to activeScreen).
    ///   - onComplete: Callback executed when the countdown reaches 0.
    ///   - onCancel: Callback executed if the user presses Escape to cancel.
    public func startCountdown(
        seconds: Int,
        screen: NSScreen? = nil,
        onComplete: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        cancel()

        guard seconds > 0 else {
            onComplete()
            return
        }

        // Guarantee that the mouse cursor is visible and not hidden
        NSCursor.unhide()
        NSCursor.arrow.set()
        CGDisplayShowCursor(kCGNullDirectDisplay)

        isCountingDown = true
        remainingSeconds = seconds
        onCompleteHandler = onComplete
        onCancelHandler = onCancel

        let targetScreen = screen ?? CaptureService.shared.activeScreen() ?? NSScreen.main ?? NSScreen()
        createAndShowHUD(on: targetScreen)
        installEscapeMonitors()

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            self.tick()
        }
        RunLoop.main.add(countdownTimer!, forMode: .common)
    }

    /// Aborts any active countdown immediately and dismisses the HUD.
    public func cancel() {
        guard isCountingDown else { return }
        cleanup()
        let cancelHandler = onCancelHandler
        onCancelHandler = nil
        onCompleteHandler = nil
        cancelHandler?()
    }

    // MARK: - Countdown Loop

    private func tick() {
        remainingSeconds -= 1
        if remainingSeconds > 0 {
            updateHUD()
            // Maintain visible arrow cursor during every tick
            NSCursor.unhide()
            NSCursor.arrow.set()
            CGDisplayShowCursor(kCGNullDirectDisplay)
        } else {
            complete()
        }
    }

    private func complete() {
        cleanup()
        let completeHandler = onCompleteHandler
        onCompleteHandler = nil
        onCancelHandler = nil

        // Allow Window Server to flush away the HUD before capturing screen pixels
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            completeHandler?()
        }
    }

    private func cleanup() {
        isCountingDown = false
        countdownTimer?.invalidate()
        countdownTimer = nil

        removeEscapeMonitors()

        if let panel = hudPanel {
            panel.orderOut(nil)
            self.hudPanel = nil
            self.numberLabel = nil
            self.subtitleLabel = nil
        }
        CATransaction.flush()
    }

    // MARK: - HUD Presentation

    private func createAndShowHUD(on screen: NSScreen) {
        let panelSize = NSSize(width: 160, height: 160)
        let screenFrame = screen.frame
        let origin = NSPoint(
            x: screenFrame.midX - (panelSize.width / 2.0),
            y: screenFrame.midY - (panelSize.height / 2.0)
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let visualEffect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 28
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 0.0
        visualEffect.layer?.borderColor = nil

        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))

        // Timer symbol icon
        let iconImageView = NSImageView(frame: NSRect(x: (panelSize.width - 24) / 2, y: 116, width: 24, height: 24))
        if let icon = NSImage(systemSymbolName: "timer", accessibilityDescription: "Timer") {
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            iconImageView.image = icon.withSymbolConfiguration(config)
            iconImageView.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        }
        container.addSubview(iconImageView)

        // Large Countdown Digit
        let numLabel = NSTextField(labelWithString: "\(remainingSeconds)")
        numLabel.frame = NSRect(x: 10, y: 46, width: panelSize.width - 20, height: 64)
        numLabel.alignment = .center
        numLabel.font = NSFont.systemFont(ofSize: 52, weight: .bold)
        numLabel.textColor = .white
        container.addSubview(numLabel)
        self.numberLabel = numLabel

        // Subtitle status label
        let subLabel = NSTextField(labelWithString: "Capturing in \(remainingSeconds)s")
        subLabel.frame = NSRect(x: 10, y: 26, width: panelSize.width - 20, height: 16)
        subLabel.alignment = .center
        subLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        container.addSubview(subLabel)
        self.subtitleLabel = subLabel

        // Escape hint
        let escLabel = NSTextField(labelWithString: "Esc to cancel")
        escLabel.frame = NSRect(x: 10, y: 10, width: panelSize.width - 20, height: 14)
        escLabel.alignment = .center
        escLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        escLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        container.addSubview(escLabel)

        visualEffect.addSubview(container)
        panel.contentView = visualEffect

        panel.orderFrontRegardless()
        self.hudPanel = panel
    }

    private func updateHUD() {
        numberLabel?.stringValue = "\(remainingSeconds)"
        subtitleLabel?.stringValue = "Capturing in \(remainingSeconds)s"
    }

    // MARK: - Key Event Monitors

    private func installEscapeMonitors() {
        removeEscapeMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.cancel()
                return nil
            }
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                DispatchQueue.main.async {
                    self?.cancel()
                }
            }
        }
    }

    private func removeEscapeMonitors() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
    }
}
