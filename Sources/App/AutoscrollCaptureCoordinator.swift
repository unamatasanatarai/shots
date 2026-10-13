import AppKit
import Carbon
import CoreGraphics

public final class AutoscrollCaptureCoordinator: NSObject {
    public static let shared = AutoscrollCaptureCoordinator()

    private var hudWindow: NSPanel?
    private var isCancelled = false
    private var keyMonitor: Any?

    private override init() {
        super.init()
    }

    // MARK: - Public Entry Point

    public func startAutoscrollCapture(delay: Int? = nil, completion: ((CGImage?) -> Void)? = nil) {
        let delaySeconds = delay ?? AppSettings.shared.captureDelaySeconds
        if delaySeconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(delaySeconds)) { [weak self] in
                self?.beginAutoscrollFlow(completion: completion)
            }
        } else {
            beginAutoscrollFlow(completion: completion)
        }
    }

    private func beginAutoscrollFlow(completion: ((CGImage?) -> Void)?) {
        RegionSelectionCoordinator.shared.startRegionSelection { [weak self] regionInfo in
            guard let self = self, let region = regionInfo else {
                completion?(nil)
                return
            }
            self.executeAutoscrollSession(region: region, completion: completion)
        }
    }

    // MARK: - Auto-scroll Execution Session

    private func executeAutoscrollSession(region: SelectedRegionInfo, completion: ((CGImage?) -> Void)?) {
        isCancelled = false

        // Compute screen coordinates for the center of the region
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let globalAppKitX = region.screen.frame.origin.x + region.rect.midX
        let globalAppKitY = region.screen.frame.origin.y + region.rect.midY
        let targetCenterCG = CGPoint(x: globalAppKitX, y: primaryHeight - globalAppKitY)

        // Present floating status HUD
        showHUD(near: region)

        // Capture off the main thread to maintain responsive UI
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }

            // Allow window server time to cleanly dismiss selection overlay
            usleep(250_000)

            // 1. Initial Frame Capture
            guard let initialDisplay = CGDisplayCreateImage(region.displayID),
                  let firstFrame = CaptureService.shared.cropImage(initialDisplay, to: region.rect, in: region.screen.frame.size) else {
                DispatchQueue.main.async {
                    self.dismissHUD()
                    completion?(nil)
                }
                return
            }

            var frames: [CGImage] = [firstFrame]
            var lastFrame = firstFrame
            var consecutiveIdenticalCount = 0
            var accumulatedHeight = firstFrame.height
            let maxHeight = ScrollingCaptureService.maxAllowedHeight
            let maxSteps = 80 // Safety ceiling: prevents runaway loops on infinite feeds
            let scrollPixels: Int32 = 60 // Gentle, controlled scroll cadence (~3-4 lines of code)

            for _ in 0..<maxSteps {
                guard !self.isCancelled else { break }

                // Post synthetic scroll event down targeted at the window center
                self.postScrollEvent(deltaY: scrollPixels, at: targetCenterCG)

                // Wait 350ms for content animation, inertial scrolling, and GPU redraw to completely settle
                usleep(350_000)

                guard !self.isCancelled else { break }

                // Capture next display frame
                guard let currentDisplay = CGDisplayCreateImage(region.displayID),
                      let currentFrame = CaptureService.shared.cropImage(currentDisplay, to: region.rect, in: region.screen.frame.size) else {
                    break
                }

                // Detect vertical pixel offset
                let shift = ScrollingCaptureService.shared.detectVerticalOffset(between: lastFrame, and: currentFrame)

                if shift == 0 {
                    consecutiveIdenticalCount += 1
                    // If content didn't move 2 consecutive times, bottom of page is reached
                    if consecutiveIdenticalCount >= 2 {
                        break
                    }
                } else {
                    consecutiveIdenticalCount = 0
                    frames.append(currentFrame)
                    lastFrame = currentFrame
                    accumulatedHeight += shift
                    if accumulatedHeight >= maxHeight {
                        break
                    }
                }
            }

            // Dismiss floating HUD
            DispatchQueue.main.async {
                self.dismissHUD()
            }

            // Stitch frames or fallback to single frame
            let finalImage: CGImage?
            if frames.count > 1 {
                finalImage = ScrollingCaptureService.shared.stitchFrames(frames, maxHeight: maxHeight)
            } else {
                finalImage = frames.first
            }

            if let result = finalImage {
                CaptureManager.shared.lastCapture = LastCaptureRecord(
                    mode: .region(rect: region.rect, screenFrame: region.screen.frame, displayID: region.displayID)
                )
                CaptureManager.shared.processCapturedImage(result)
            } else {
                NSSound.beep()
            }

            DispatchQueue.main.async {
                completion?(finalImage)
            }
        }
    }

    // MARK: - Synthetic Scrolling Dispatch

    private func postScrollEvent(deltaY: Int32, at point: CGPoint) {
        // Dispatch pixel-based scroll wheel event to hardware HID tap only (avoid double dispatch)
        if let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: -deltaY,
            wheel2: 0,
            wheel3: 0
        ) {
            event.location = point
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Floating Status HUD

    private func showHUD(near region: SelectedRegionInfo) {
        dismissHUD()

        let hudW: CGFloat = 260
        let hudH: CGFloat = 36
        let screenFrame = region.screen.frame

        let posX = (screenFrame.origin.x + region.rect.midX) - (hudW / 2)
        var posY = (screenFrame.origin.y + region.rect.maxY) + 12
        if posY + hudH > screenFrame.maxY - 10 {
            posY = (screenFrame.origin.y + region.rect.minY) - hudH - 12
        }

        let panel = NSPanel(
            contentRect: NSRect(x: posX, y: posY, width: hudW, height: hudH),
            styleMask: [.nonactivatingPanel, .borderless, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let hudView = AutoscrollHUDView(frame: NSRect(x: 0, y: 0, width: hudW, height: hudH)) { [weak self] in
            self?.stopAutoscroll()
        }
        panel.contentView = hudView
        panel.orderFrontRegardless()
        self.hudWindow = panel

        // Escape / Return / Space abort listener
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 || event.keyCode == 36 || event.keyCode == 49 { // Esc, Enter, Space
                self?.stopAutoscroll()
                return nil
            }
            return event
        }
    }

    public func stopAutoscroll() {
        isCancelled = true
        dismissHUD()
    }

    private func dismissHUD() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let window = hudWindow {
            window.orderOut(nil)
            hudWindow = nil
        }
    }
}

// MARK: - Autoscroll HUD View

private final class AutoscrollHUDView: NSView {
    private let onStop: () -> Void

    init(frame frameRect: NSRect, onStop: @escaping () -> Void) {
        self.onStop = onStop
        super.init(frame: frameRect)
        wantsLayer = true
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 0.94).cgColor
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.25).cgColor
        layer?.borderWidth = 1.0

        // Status Label
        let label = NSTextField(labelWithString: "⏬ Scrolling... (Esc to finish)")
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.frame = NSRect(x: 12, y: 8, width: 175, height: 20)
        addSubview(label)

        // Stop Button
        let stopButton = NSButton(title: "Finish", target: self, action: #selector(stopClicked))
        stopButton.bezelStyle = .rounded
        stopButton.controlSize = .small
        stopButton.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        stopButton.frame = NSRect(x: bounds.width - 66, y: 7, width: 56, height: 22)
        addSubview(stopButton)
    }

    @objc private func stopClicked() {
        onStop()
    }
}
