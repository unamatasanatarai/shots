import AppKit
import Carbon
import CoreGraphics

// MARK: - Selected Region Data

public struct SelectedRegionInfo: Equatable {
    public let rect: NSRect
    public let screen: NSScreen
    public let displayID: CGDirectDisplayID

    public init(rect: NSRect, screen: NSScreen, displayID: CGDirectDisplayID) {
        self.rect = rect
        self.screen = screen
        self.displayID = displayID
    }
}

// MARK: - Region Selection Coordinator

public final class RegionSelectionCoordinator {
    public static let shared = RegionSelectionCoordinator()

    private var overlayPanels: [NSPanel] = []
    private var isSelecting = false
    private var completionHandler: ((CGImage?) -> Void)?
    private var regionCompletionHandler: ((SelectedRegionInfo?) -> Void)?
    private var localKeyDownMonitor: Any?

    private var escapeHotKeyRef: EventHotKeyRef?
    private var escapeEventHandlerRef: EventHandlerRef?
    private let escapeHotKeyID = EventHotKeyID(signature: 0x45534350 /* 'ESCP' */, id: 99)

    /// Active consuming event tap that swallows clicks/drags so menus stay open
    /// and background windows are never activated.
    private var eventTap: CFMachPort?
    private var tapRunLoopSource: CFRunLoopSource?

    /// Live selection state driven exclusively by the event tap.
    private var liveStartPoint: NSPoint?
    private var liveCurrentPoint: NSPoint?
    private var liveIsDragging = false

    private init() {}

    // MARK: - Public API

    public func startRegionSelection(completion: @escaping (SelectedRegionInfo?) -> Void) {
        guard !isSelecting else { return }
        regionCompletionHandler = completion
        startSelection { _ in }
    }

    public func startSelection(completion: @escaping (CGImage?) -> Void) {
        guard !isSelecting else { return }
        isSelecting = true
        completionHandler = completion

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            finish(with: nil)
            return
        }

        // Preflight Accessibility permission so users are prompted if not yet granted
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        // Install global Escape hotkey so Escape cancels immediately without needing window focus
        installEscapeHotKey()

        // Local monitor for Escape fallback
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.finish(with: nil)
                return nil
            }
            return event
        }

        overlayPanels.removeAll()

        for screen in screens {
            let panel = RegionOverlayPanel(
                contentRect: screen.frame,
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )

            // Sit just above popUpMenu level so crosshairs draw over context menus,
            // while remaining completely transparent so video playback and animations continue uninterrupted.
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            // Overlay panel is 100% click-through. All mouse events are handled by the CGEventTap.
            panel.ignoresMouseEvents = true
            panel.acceptsMouseMovedEvents = false

            let selectionView = RegionSelectionView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                screen: screen
            )

            panel.contentView = selectionView
            overlayPanels.append(panel)
        }

        // Install consuming event tap to intercept and swallow mouse clicks/drags
        installEventTap()

        // Show transparent overlays without stealing key focus from existing windows or menus
        for panel in overlayPanels {
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Finish

    private func finish(with image: CGImage?) {
        guard isSelecting else { return }
        isSelecting = false

        removeEscapeHotKey()
        removeEventTap()

        liveStartPoint = nil
        liveCurrentPoint = nil
        liveIsDragging = false

        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyDownMonitor = nil
        }

        for panel in overlayPanels {
            panel.orderOut(nil)
        }
        overlayPanels.removeAll()
        CATransaction.flush()

        let handler = completionHandler
        completionHandler = nil
        handler?(image)

        let regHandler = regionCompletionHandler
        regionCompletionHandler = nil
        regHandler?(nil)
    }

    // MARK: - Consuming Event Tap (Live Mode)

    /// Installs a CGEventTap at `.defaultTap` (consuming mode) to **swallow**
    /// mouse-moved, click, drag, and scroll events before they reach underlying apps.
    /// This prevents hover events from opening submenus, changing focus, or activating buttons.
    private func installEventTap() {
        let eventsOfInterest: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let tapCallback: CGEventTapCallBack = { (_, type, event, userInfo) -> Unmanaged<CGEvent>? in
            guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
            let coordinator = Unmanaged<RegionSelectionCoordinator>.fromOpaque(userInfo).takeUnretainedValue()
            let shouldConsume = coordinator.handleTapEvent(type: type, event: event)
            return shouldConsume ? nil : Unmanaged.passUnretained(event)
        }

        // Try .cgSessionEventTap first (swallows app dispatch while preserving system pointer motion)
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: tapCallback,
            userInfo: selfPtr
        ) ?? CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: tapCallback,
            userInfo: selfPtr
        ) {
            eventTap = tap
        } else {
            NSLog("Shots!: Consuming event tap unavailable. Prompting Accessibility permission and falling back to listen-only.")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)

            guard let tap = CGEvent.tapCreate(
                tap: .cgAnnotatedSessionEventTap,
                place: .tailAppendEventTap,
                options: .listenOnly,
                eventsOfInterest: eventsOfInterest,
                callback: { (_, type, event, userInfo) -> Unmanaged<CGEvent>? in
                    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
                    let coordinator = Unmanaged<RegionSelectionCoordinator>.fromOpaque(userInfo).takeUnretainedValue()
                    _ = coordinator.handleTapEvent(type: type, event: event)
                    return Unmanaged.passUnretained(event)
                },
                userInfo: selfPtr
            ) else {
                return
            }
            eventTap = tap
        }

        guard let tap = eventTap else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = tapRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            eventTap = nil
            tapRunLoopSource = nil
        }
    }

    /// Handles observed mouse events. Returns `true` to swallow the event, `false` to pass through.
    @discardableResult
    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Bool {
        // Automatically recover if macOS disables the event tap due to timeout or user input
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }

        let cgPoint = event.location

        switch type {
        case .mouseMoved:
            if liveIsDragging {
                liveCurrentPoint = cgPoint
            }
            updateOverlays(globalCGPoint: cgPoint)
            return true // consume — swallow hover events so menus don't change focus or open submenus

        case .leftMouseDragged:
            if liveIsDragging {
                liveCurrentPoint = cgPoint
            }
            updateOverlays(globalCGPoint: cgPoint)
            return true // consume

        case .leftMouseDown:
            liveStartPoint = cgPoint
            liveCurrentPoint = cgPoint
            liveIsDragging = true
            updateOverlays(globalCGPoint: cgPoint)
            return true // consume — prevents menu dismissal & button clicks

        case .leftMouseUp:
            guard liveIsDragging, let start = liveStartPoint else { return true }
            let end = cgPoint
            liveIsDragging = false
            liveCurrentPoint = nil
            liveStartPoint = nil
            performLiveCapture(startCG: start, endCG: end)
            return true // consume

        case .rightMouseDown:
            finish(with: nil)
            return true // consume — prevents context menu on cancellation

        case .scrollWheel, .rightMouseUp, .otherMouseDown:
            return true // consume — prevent accidental scroll or secondary clicks during selection

        default:
            return false
        }
    }

    /// Update mouse coordinates and selection rect on all screen overlays.
    private func updateOverlays(globalCGPoint: NSPoint) {
        let screenHeight = NSScreen.screens.first.map { $0.frame.maxY } ?? 0
        let appKitGlobal = NSPoint(x: globalCGPoint.x, y: screenHeight - globalCGPoint.y)

        for panel in overlayPanels {
            guard let view = panel.contentView as? RegionSelectionView else { continue }
            let screenFrame = view.targetScreen.frame

            let localPt = NSPoint(
                x: appKitGlobal.x - screenFrame.origin.x,
                y: appKitGlobal.y - screenFrame.origin.y
            )

            var localStart: NSPoint?
            var localCurrent: NSPoint?

            if liveIsDragging, let startCG = liveStartPoint, let curCG = liveCurrentPoint {
                localStart = NSPoint(
                    x: startCG.x - screenFrame.origin.x,
                    y: (screenHeight - startCG.y) - screenFrame.origin.y
                )
                localCurrent = NSPoint(
                    x: curCG.x - screenFrame.origin.x,
                    y: (screenHeight - curCG.y) - screenFrame.origin.y
                )
            }

            view.externalUpdate(
                mousePoint: localPt,
                isDragging: liveIsDragging,
                selectionStart: localStart,
                selectionCurrent: localCurrent
            )
        }
    }

    /// On mouse release: hide overlays, take a clean screenshot of the display, and crop to selection.
    private func performLiveCapture(startCG: NSPoint, endCG: NSPoint) {
        let midX = (startCG.x + endCG.x) / 2.0
        let midY = (startCG.y + endCG.y) / 2.0

        let targetScreen = CaptureService.shared.screen(containingCGPoint: CGPoint(x: midX, y: midY))
            ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let screenFrame = targetScreen.frame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        let localStart = NSPoint(
            x: startCG.x - screenFrame.origin.x,
            y: (primaryHeight - startCG.y) - screenFrame.origin.y
        )
        let localEnd = NSPoint(
            x: endCG.x - screenFrame.origin.x,
            y: (primaryHeight - endCG.y) - screenFrame.origin.y
        )

        let selRect = normalizedRect(from: localStart, to: localEnd)
        let viewSize = screenFrame.size

        // Hide overlays immediately before screen capture
        for panel in overlayPanels {
            panel.orderOut(nil)
        }
        CATransaction.flush()

        let displayID = (targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
            ?? CGMainDisplayID()

        if let regHandler = regionCompletionHandler {
            regionCompletionHandler = nil
            finish(with: nil)
            let chosenRect = (selRect.width >= 6 && selRect.height >= 6) ? selRect : screenFrame
            regHandler(SelectedRegionInfo(rect: chosenRect, screen: targetScreen, displayID: displayID))
            return
        }

        if selRect.width >= 6 && selRect.height >= 6 {
            CaptureManager.shared.lastCapture = LastCaptureRecord(
                mode: .region(rect: selRect, screenFrame: screenFrame, displayID: displayID)
            )
            let fullImage = CGDisplayCreateImage(displayID)
            var cropped = fullImage.flatMap { cropImage($0, to: selRect, in: viewSize) }
            if AppSettings.shared.includeCursor, let validCrop = cropped {
                cropped = CaptureService.shared.compositeCursor(
                    on: validCrop,
                    screen: targetScreen,
                    cropRect: selRect
                )
            }
            finish(with: cropped ?? fullImage)
        } else {
            CaptureManager.shared.lastCapture = LastCaptureRecord(mode: .fullscreen)
            // Click without drag captures full display
            var fullImage = CGDisplayCreateImage(displayID)
            if AppSettings.shared.includeCursor, let validFull = fullImage {
                fullImage = CaptureService.shared.compositeCursor(on: validFull, screen: targetScreen)
            }
            finish(with: fullImage)
        }
    }

    // MARK: - Escape HotKey Handling

    private func installEscapeHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, theEvent, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                var hkID = EventHotKeyID()
                let paramStatus = GetEventParameter(
                    theEvent,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if paramStatus == noErr && hkID.id == 99 {
                    DispatchQueue.main.async {
                        let coordinator = Unmanaged<RegionSelectionCoordinator>.fromOpaque(userData).takeUnretainedValue()
                        coordinator.finish(with: nil)
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &escapeEventHandlerRef
        )

        if status == noErr {
            RegisterEventHotKey(
                UInt32(kVK_Escape),
                0,
                escapeHotKeyID,
                GetApplicationEventTarget(),
                0,
                &escapeHotKeyRef
            )
        }
    }

    private func removeEscapeHotKey() {
        if let ref = escapeHotKeyRef {
            UnregisterEventHotKey(ref)
            escapeHotKeyRef = nil
        }
        if let handler = escapeEventHandlerRef {
            RemoveEventHandler(handler)
            escapeEventHandlerRef = nil
        }
    }

    // MARK: - Geometry & Cropping Helpers

    private func normalizedRect(from p1: NSPoint, to p2: NSPoint) -> NSRect {
        CaptureService.shared.normalizedRect(from: p1, to: p2)
    }

    private func cropImage(_ image: CGImage, to selRect: NSRect, in viewSize: NSSize) -> CGImage? {
        CaptureService.shared.cropImage(image, to: selRect, in: viewSize)
    }
}

// MARK: - Overlay Panel Subclass

private final class RegionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Region Selection View

private final class RegionSelectionView: NSView {
    fileprivate let targetScreen: NSScreen

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var currentMousePoint: NSPoint?
    private var isDragging = false

    init(frame frameRect: NSRect, screen: NSScreen) {
        self.targetScreen = screen
        super.init(frame: frameRect)
        wantsLayer = true

        let globalMouse = NSEvent.mouseLocation
        if screen.frame.contains(globalMouse) {
            currentMousePoint = NSPoint(
                x: globalMouse.x - screen.frame.origin.x,
                y: globalMouse.y - screen.frame.origin.y
            )
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - External Updates from Event Tap

    func externalUpdate(
        mousePoint: NSPoint,
        isDragging dragging: Bool,
        selectionStart: NSPoint?,
        selectionCurrent: NSPoint?
    ) {
        currentMousePoint = mousePoint
        isDragging = dragging
        startPoint = selectionStart
        currentPoint = selectionCurrent
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { false }

    // MARK: - Drawing & Rendering

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Selection Marquee: translucent darken with high-contrast borders
        if isDragging, let start = startPoint, let current = currentPoint {
            let selRect = normalizedRect(from: start, to: current)
            if selRect.width > 0 && selRect.height > 0 {
                context.saveGState()
                context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.18))
                context.fill(selRect)

                // 1px white border
                context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
                context.setLineWidth(1.0)
                context.stroke(selRect)

                // Subtle blue accent ring
                context.setStrokeColor(CGColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.45))
                context.setLineWidth(0.5)
                context.stroke(selRect.insetBy(dx: -0.5, dy: -0.5))
                context.restoreGState()

                // Live dimension badge
                drawDimensionBadge(for: selRect, in: context)
            }
        }

        // 2. Crosshair and coordinates badge (rendered only if mouse is within this screen)
        let activePoint = currentPoint ?? currentMousePoint
        if let pt = activePoint, bounds.contains(pt) {
            drawCrosshairs(at: pt, in: context)
            drawCoordinateBadge(at: pt, in: context)
        }
    }

    // MARK: - 1-Line-Thick Fading Crosshair

    private func drawCrosshairs(at point: NSPoint, in context: CGContext) {
        let mx = point.x
        let my = point.y
        let w = bounds.width
        let h = bounds.height

        let gap: CGFloat = 8.0
        let fadeDist: CGFloat = 80.0
        let baseAlpha: CGFloat = 0.65

        context.saveGState()
        context.setShadow(offset: .zero, blur: 1.5, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.75))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let fullColor = CGColor(red: 1, green: 1, blue: 1, alpha: baseAlpha)
        let zeroColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)

        guard let gradientFadeIn = CGGradient(
            colorsSpace: colorSpace,
            colors: [zeroColor, fullColor] as CFArray,
            locations: [0.0, 1.0]
        ), let gradientFadeOut = CGGradient(
            colorsSpace: colorSpace,
            colors: [fullColor, zeroColor] as CFArray,
            locations: [0.0, 1.0]
        ) else {
            context.restoreGState()
            return
        }

        let yPos = floor(my)
        let xPos = floor(mx)

        // Horizontal Left
        if mx - gap > 0 {
            let leftEnd = mx - gap
            let fadeStart = max(0, leftEnd - fadeDist)

            if fadeStart > 0 {
                context.setFillColor(fullColor)
                context.fill(CGRect(x: 0, y: yPos, width: fadeStart, height: 1.0))
            }

            context.saveGState()
            context.clip(to: CGRect(x: fadeStart, y: yPos, width: leftEnd - fadeStart, height: 1.0))
            context.drawLinearGradient(gradientFadeOut, start: CGPoint(x: fadeStart, y: yPos), end: CGPoint(x: leftEnd, y: yPos), options: [])
            context.restoreGState()
        }

        // Horizontal Right
        if mx + gap < w {
            let rightStart = mx + gap
            let fadeEnd = min(w, rightStart + fadeDist)

            context.saveGState()
            context.clip(to: CGRect(x: rightStart, y: yPos, width: fadeEnd - rightStart, height: 1.0))
            context.drawLinearGradient(gradientFadeIn, start: CGPoint(x: rightStart, y: yPos), end: CGPoint(x: fadeEnd, y: yPos), options: [])
            context.restoreGState()

            if fadeEnd < w {
                context.setFillColor(fullColor)
                context.fill(CGRect(x: fadeEnd, y: yPos, width: w - fadeEnd, height: 1.0))
            }
        }

        // Vertical Bottom
        if my - gap > 0 {
            let bottomEnd = my - gap
            let fadeStart = max(0, bottomEnd - fadeDist)

            if fadeStart > 0 {
                context.setFillColor(fullColor)
                context.fill(CGRect(x: xPos, y: 0, width: 1.0, height: fadeStart))
            }

            context.saveGState()
            context.clip(to: CGRect(x: xPos, y: fadeStart, width: 1.0, height: bottomEnd - fadeStart))
            context.drawLinearGradient(gradientFadeOut, start: CGPoint(x: xPos, y: fadeStart), end: CGPoint(x: xPos, y: bottomEnd), options: [])
            context.restoreGState()
        }

        // Vertical Top
        if my + gap < h {
            let topStart = my + gap
            let fadeEnd = min(h, topStart + fadeDist)

            context.saveGState()
            context.clip(to: CGRect(x: xPos, y: topStart, width: 1.0, height: fadeEnd - topStart))
            context.drawLinearGradient(gradientFadeIn, start: CGPoint(x: xPos, y: topStart), end: CGPoint(x: xPos, y: fadeEnd), options: [])
            context.restoreGState()

            if fadeEnd < h {
                context.setFillColor(fullColor)
                context.fill(CGRect(x: xPos, y: fadeEnd, width: 1.0, height: h - fadeEnd))
            }
        }

        context.restoreGState()
    }

    // MARK: - Live Coordinate Badge Next to Cursor

    private func drawCoordinateBadge(at point: NSPoint, in context: CGContext) {
        let scaleX = targetScreen.backingScaleFactor
        let scaleY = targetScreen.backingScaleFactor
        let maxPixelX = Int(bounds.width * scaleX)
        let maxPixelY = Int(bounds.height * scaleY)

        let curX = max(0, min(Int(round(point.x * scaleX)), maxPixelX))
        let curY = max(0, min(Int(round((bounds.height - point.y) * scaleY)), maxPixelY))

        let text = "x: \(curX)\ny: \(curY)"

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]

        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()

        let padH: CGFloat = 7
        let padV: CGFloat = 5
        let badgeW = ceil(textSize.width + (padH * 2))
        let badgeH = ceil(textSize.height + (padV * 2))

        var badgeX = point.x + 14
        var badgeY = point.y - badgeH - 8

        if badgeX + badgeW > bounds.width - 8 {
            badgeX = point.x - badgeW - 14
        }
        if badgeY < 8 {
            badgeY = point.y + 14
        }
        if badgeY + badgeH > bounds.height - 8 {
            badgeY = point.y - badgeH - 14
        }

        badgeX = max(8, min(badgeX, bounds.width - badgeW - 8))
        badgeY = max(8, min(badgeY, bounds.height - badgeH - 8))

        let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)

        context.saveGState()
        let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        context.addPath(badgePath)
        context.setFillColor(CGColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 0.90))
        context.fillPath()

        context.addPath(badgePath)
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
        context.setLineWidth(0.75)
        context.strokePath()
        context.restoreGState()

        let textOrigin = NSPoint(x: badgeX + padH, y: badgeY + padV)
        attributedText.draw(at: textOrigin)
    }

    // MARK: - Dimension Badge

    private func drawDimensionBadge(for selRect: CGRect, in context: CGContext) {
        let scaleX = targetScreen.backingScaleFactor
        let scaleY = targetScreen.backingScaleFactor

        let pixelWidth = Int(round(selRect.width * scaleX))
        let pixelHeight = Int(round(selRect.height * scaleY))

        let dimensionText = "\(pixelWidth) × \(pixelHeight)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]

        let attributedString = NSAttributedString(string: dimensionText, attributes: attributes)
        let textSize = attributedString.size()

        let pillPaddingH: CGFloat = 8
        let pillPaddingV: CGFloat = 4
        let pillWidth = textSize.width + (pillPaddingH * 2)
        let pillHeight = textSize.height + (pillPaddingV * 2)

        var pillOriginY = selRect.minY - pillHeight - 8
        if pillOriginY < 12 {
            pillOriginY = min(bounds.height - pillHeight - 12, selRect.maxY + 8)
        }
        var pillOriginX = selRect.midX - (pillWidth / 2)
        pillOriginX = max(10, min(pillOriginX, bounds.width - pillWidth - 10))

        let pillRect = NSRect(x: pillOriginX, y: pillOriginY, width: pillWidth, height: pillHeight)

        context.saveGState()
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        context.addPath(pillPath)
        context.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.92))
        context.fillPath()

        context.addPath(pillPath)
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.25))
        context.setLineWidth(0.75)
        context.strokePath()
        context.restoreGState()

        let textPoint = NSPoint(
            x: pillRect.origin.x + pillPaddingH,
            y: pillRect.origin.y + pillPaddingV
        )
        attributedString.draw(at: textPoint)
    }

    // MARK: - Geometry Helpers

    private func normalizedRect(from p1: NSPoint, to p2: NSPoint) -> NSRect {
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        let width = abs(p2.x - p1.x)
        let height = abs(p2.y - p1.y)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
