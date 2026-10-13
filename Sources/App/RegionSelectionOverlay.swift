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
    private var isCursorHidden = false

    private init() {
    }

    deinit {
    }

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
            // while remaining completely transparent so video playback, menus and animations continue uninterrupted.
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true

            let selectionView = RegionSelectionView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                screen: screen
            )

            panel.contentView = selectionView
            overlayPanels.append(panel)
        }

        // Install consuming event tap to intercept and swallow mouse clicks/drags
        installEventTap()

        let initialCGLocation = CGEvent(source: nil)?.location ?? CGPoint.zero
        liveCurrentPoint = initialCGLocation
        updateOverlays(globalCGPoint: initialCGLocation)

        // Show transparent overlays without stealing key focus from existing windows or menus
        for panel in overlayPanels {
            panel.orderFrontRegardless()
        }

        updateOverlays(globalCGPoint: initialCGLocation)
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
        func eventMask(for type: CGEventType) -> CGEventMask {
            CGEventMask(1) << type.rawValue
        }

        let eventsOfInterest: CGEventMask =
            eventMask(for: .mouseMoved) |
            eventMask(for: .leftMouseDown) |
            eventMask(for: .leftMouseDragged) |
            eventMask(for: .leftMouseUp) |
            eventMask(for: .rightMouseDown) |
            eventMask(for: .rightMouseUp) |
            eventMask(for: .otherMouseDown) |
            eventMask(for: .scrollWheel)

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
            return true // consume

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
            return true // consume

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
            return true // consume

        case .scrollWheel, .rightMouseUp, .otherMouseDown:
            return true // consume

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

            let isOnThisScreen = screenFrame.contains(appKitGlobal)
            let localPt: NSPoint? = isOnThisScreen ? NSPoint(
                x: appKitGlobal.x - screenFrame.origin.x,
                y: appKitGlobal.y - screenFrame.origin.y
            ) : nil

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

        // NSTrackingArea with .activeAlways ensures cursorUpdate fires even when
        // our app is not the active (frontmost) application.  .inVisibleRect
        // auto-adapts to bounds changes so we never need to recreate it.
        let cursorTracking = NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(cursorTracking)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - External Updates from Event Tap

    func externalUpdate(
        mousePoint: NSPoint?,
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

    // MARK: - Transparent Native Cursor

    /// A real transparent bitmap avoids AppKit's fallback-to-arrow behavior that
    /// can occur with an empty or one-pixel image.
    static let invisibleCursor: NSCursor = {
        let cursorSize = 32
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: cursorSize,
            pixelsHigh: cursorSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: cursorSize * 4,
            bitsPerPixel: 32
        )!

        for x in 0..<cursorSize {
            for y in 0..<cursorSize {
                representation.setColor(.clear, atX: x, y: y)
            }
        }

        let image = NSImage(size: NSSize(width: cursorSize, height: cursorSize))
        image.addRepresentation(representation)
        return NSCursor(image: image, hotSpot: .zero)
    }()

    override func resetCursorRects() {
        super.resetCursorRects()
        discardCursorRects()
        addCursorRect(bounds, cursor: Self.invisibleCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        // Always force the transparent cursor.  This fires via the .activeAlways
        // tracking area even when our app is not frontmost, ensuring the system
        // pointer never leaks through our custom crosshair.
        Self.invisibleCursor.set()
    }

    // MARK: - Drawing & Rendering

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Selection Marquee: bright luminous highlight with high-contrast glowing borders
        if isDragging, let start = startPoint, let current = currentPoint {
            let selRect = normalizedRect(from: start, to: current)
            if selRect.width > 0 && selRect.height > 0 {
                context.saveGState()

                // Bright luminous translucent highlight (brightens content underneath)
                context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.22))
                context.fill(selRect)

                // Vibrant bright macOS accent outer border (1.5pt)
                context.setStrokeColor(CGColor(red: 0.12, green: 0.58, blue: 1.0, alpha: 0.90))
                context.setLineWidth(1.5)
                context.stroke(selRect.insetBy(dx: -0.75, dy: -0.75))

                // Bright pure white inner border (1.0pt)
                context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
                context.setLineWidth(1.0)
                context.stroke(selRect)
                context.restoreGState()

                // Live dimension numbers (only set of numbers shown during drag)
                drawSelectionDimensionsBadge(start: start, current: current, in: context)
            }
        }

        // 2. Precision reticle crosshair cursor (rendered only if mouse is within this screen)
        let activePoint = currentPoint ?? currentMousePoint
        if let pt = activePoint, bounds.contains(pt) {
            drawPrecisionCrosshair(at: pt, in: context)

            // Cursor coordinates shown ONLY when not dragging
            if !isDragging {
                drawCoordinateBadge(at: pt, in: context)
            }
        }
    }

    // MARK: - Precision Minimalist Reticle Crosshair Cursor
    // Circular reticle with compact crosshairs:
    // - Circle diameter: 46% of overall width
    // - Crosshair lines: luxurious #333333, fading out from 50% to center
    // - Center: exactly 1px of transparency at cursor position

    private static let crosshairColorSpace = CGColorSpaceCreateDeviceRGB()

    private static let crosshairCasingGradient: CGGradient? = {
        let casingComponents: [CGFloat] = [
            1.00, 1.00, 1.00, 0.16,  // Outer tip (solid casing)
            1.00, 1.00, 1.00, 0.16,  // 50% mark
            1.00, 1.00, 1.00, 0.00   // Center gap edge (transparent)
        ]
        let locations: [CGFloat] = [0.0, 0.5, 1.0]
        return CGGradient(colorSpace: crosshairColorSpace, colorComponents: casingComponents, locations: locations, count: 3)
    }()

    private static let crosshairStrokeGradient: CGGradient? = {
        let strokeComponents: [CGFloat] = [
            0.20, 0.20, 0.20, 1.00,  // Outer tip: luxurious #333333
            0.20, 0.20, 0.20, 1.00,  // 50% mark
            0.20, 0.20, 0.20, 0.00   // Center gap edge: transparent
        ]
        let locations: [CGFloat] = [0.0, 0.5, 1.0]
        return CGGradient(colorSpace: crosshairColorSpace, colorComponents: strokeComponents, locations: locations, count: 3)
    }()

    private func drawPrecisionCrosshair(at point: NSPoint, in context: CGContext, size: CGFloat = 32.0) {
        let cx = round(point.x)
        let cy = round(point.y)
        let lineHalf = size * 0.375  // Shorter lines (~12.0 pt)

        let circleDiameter = size * 0.46
        let circleRadius = circleDiameter / 2.0
        let circleStrokeWidth = max(0.65, size * 0.02)
        let crosshairStrokeWidth = max(1.0, size * 0.03)

        context.saveGState()

        let circleRect = CGRect(
            x: cx - circleRadius,
            y: cy - circleRadius,
            width: circleDiameter,
            height: circleDiameter
        )

        // 1. Circle interior fill: subtle translucent dark tint
        let circleFillColor = CGColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 0.12)
        context.setFillColor(circleFillColor)
        context.fillEllipse(in: circleRect)

        // 2. Circle outline: subtle translucent #333333 ring
        let circleOutlineColor = CGColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 0.50)
        context.setStrokeColor(circleOutlineColor)
        context.setLineWidth(circleStrokeWidth)
        context.strokeEllipse(in: circleRect)

        // 3. Crosshair strokes fading out from 50% to center, leaving 1px center transparency
        let centerGap: CGFloat = 0.5  // 0.5 pt on either side = 1.0 pt (1px) transparent center
        let armLength = lineHalf - centerGap
        let casingWidth = crosshairStrokeWidth + 1.8

        if let casingGradient = Self.crosshairCasingGradient,
           let strokeGradient = Self.crosshairStrokeGradient {
            struct CrosshairArm {
                let outer: CGPoint
                let inner: CGPoint
                let strokeRect: CGRect
                let casingRect: CGRect
            }

            let arms: [CrosshairArm] = [
                // Left arm
                CrosshairArm(
                    outer: CGPoint(x: cx - lineHalf, y: cy),
                    inner: CGPoint(x: cx - centerGap, y: cy),
                    strokeRect: CGRect(x: cx - lineHalf, y: cy - crosshairStrokeWidth / 2.0, width: armLength, height: crosshairStrokeWidth),
                    casingRect: CGRect(x: cx - lineHalf, y: cy - casingWidth / 2.0, width: armLength, height: casingWidth)
                ),
                // Right arm
                CrosshairArm(
                    outer: CGPoint(x: cx + lineHalf, y: cy),
                    inner: CGPoint(x: cx + centerGap, y: cy),
                    strokeRect: CGRect(x: cx + centerGap, y: cy - crosshairStrokeWidth / 2.0, width: armLength, height: crosshairStrokeWidth),
                    casingRect: CGRect(x: cx + centerGap, y: cy - casingWidth / 2.0, width: armLength, height: casingWidth)
                ),
                // Bottom arm
                CrosshairArm(
                    outer: CGPoint(x: cx, y: cy - lineHalf),
                    inner: CGPoint(x: cx, y: cy - centerGap),
                    strokeRect: CGRect(x: cx - crosshairStrokeWidth / 2.0, y: cy - lineHalf, width: crosshairStrokeWidth, height: armLength),
                    casingRect: CGRect(x: cx - casingWidth / 2.0, y: cy - lineHalf, width: casingWidth, height: armLength)
                ),
                // Top arm
                CrosshairArm(
                    outer: CGPoint(x: cx, y: cy + lineHalf),
                    inner: CGPoint(x: cx, y: cy + centerGap),
                    strokeRect: CGRect(x: cx - crosshairStrokeWidth / 2.0, y: cy + centerGap, width: crosshairStrokeWidth, height: armLength),
                    casingRect: CGRect(x: cx - casingWidth / 2.0, y: cy + centerGap, width: casingWidth, height: armLength)
                )
            ]

            // Draw white casings first (fading out from 50% to center)
            for arm in arms {
                context.saveGState()
                context.clip(to: arm.casingRect)
                context.drawLinearGradient(casingGradient, start: arm.outer, end: arm.inner, options: [])
                context.restoreGState()
            }

            // Draw #333333 strokes on top (fading out from 50% to center)
            for arm in arms {
                context.saveGState()
                context.clip(to: arm.strokeRect)
                context.drawLinearGradient(strokeGradient, start: arm.outer, end: arm.inner, options: [])
                context.restoreGState()
            }
        }

        context.restoreGState()
    }

    // MARK: - Live Numbers Rendering (Luxurious #333333 Text, 1px Shadow, 3px Gap)

    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 8.0, weight: .semibold)

    private static let numberAttributes: [NSAttributedString.Key: Any] = {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.white.withAlphaComponent(0.85)
        shadow.shadowOffset = NSSize(width: 1.0, height: -1.0)
        shadow.shadowBlurRadius = 0.5

        return [
            .font: numberFont,
            .foregroundColor: NSColor(srgbRed: 0.20, green: 0.20, blue: 0.20, alpha: 1.0),
            .shadow: shadow
        ]
    }()

    private func measureNumberBadge(top: String, bottom: String) -> NSSize {
        let topSize = (top as NSString).size(withAttributes: Self.numberAttributes)
        let bottomSize = (bottom as NSString).size(withAttributes: Self.numberAttributes)
        let width = max(topSize.width, bottomSize.width) + 1.0
        let height = topSize.height + Self.numberFont.capHeight + 3.0 + 1.0
        return NSSize(width: ceil(width), height: ceil(height))
    }

    private func drawNumberBadge(
        top: String,
        bottom: String,
        at origin: NSPoint,
        alignment: NSTextAlignment,
        in context: CGContext
    ) {
        let font = Self.numberFont
        let attributes = Self.numberAttributes

        let topWidth = (top as NSString).size(withAttributes: attributes).width
        let bottomWidth = (bottom as NSString).size(withAttributes: attributes).width
        let maxWidth = max(topWidth, bottomWidth)

        // Distance between the lower edge of numbers in top row and upper edge of numbers in bottom row:
        // topY - bottomY - font.capHeight = 3.0 px => rowSpacing = font.capHeight + 3.0
        let rowSpacing = font.capHeight + 3.0

        let topX: CGFloat
        let bottomX: CGFloat
        if alignment == .right {
            topX = origin.x + (maxWidth - topWidth)
            bottomX = origin.x + (maxWidth - bottomWidth)
        } else {
            topX = origin.x
            bottomX = origin.x
        }

        let bottomOrigin = NSPoint(x: round(bottomX), y: origin.y)
        let topOrigin = NSPoint(x: round(topX), y: origin.y + rowSpacing)

        (bottom as NSString).draw(at: bottomOrigin, withAttributes: attributes)
        (top as NSString).draw(at: topOrigin, withAttributes: attributes)
    }

    // MARK: - Live Coordinate Badge Next to Cursor (Hover Only)

    private func drawCoordinateBadge(at point: NSPoint, in context: CGContext) {
        let scaleX = targetScreen.backingScaleFactor
        let scaleY = targetScreen.backingScaleFactor
        let maxPixelX = Int(bounds.width * scaleX)
        let maxPixelY = Int(bounds.height * scaleY)

        let curX = max(0, min(Int(round(point.x * scaleX)), maxPixelX))
        let curY = max(0, min(Int(round((bounds.height - point.y) * scaleY)), maxPixelY))

        let topText = "\(curX)"
        let bottomText = "\(curY)"
        let textSize = measureNumberBadge(top: topText, bottom: bottomText)

        let offset: CGFloat = 8.0
        let margin: CGFloat = 8.0

        // Default to bottom-right when hovering
        var originX = point.x + offset
        var originY = point.y - textSize.height - offset

        // Edge flip logic:
        // flip to top if would hide below bottom edge of screen,
        // flip bottom if top of screen would hide, left if screen right, right if screen left.
        if originY < margin {
            originY = point.y + offset
        }
        if originY + textSize.height > bounds.height - margin {
            originY = point.y - textSize.height - offset
        }
        if originX + textSize.width > bounds.width - margin {
            originX = point.x - textSize.width - offset
        }
        if originX < margin {
            originX = point.x + offset
        }

        originX = round(max(margin, min(originX, bounds.width - textSize.width - margin)))
        originY = round(max(margin, min(originY, bounds.height - textSize.height - margin)))

        let isRightOfCursor = originX >= point.x
        let alignment: NSTextAlignment = isRightOfCursor ? .left : .right

        drawNumberBadge(top: topText, bottom: bottomText, at: NSPoint(x: originX, y: originY), alignment: alignment, in: context)
    }

    // MARK: - Live Selection Dimensions Badge (Drag Only)

    private func drawSelectionDimensionsBadge(start: NSPoint, current: NSPoint, in context: CGContext) {
        let scaleX = targetScreen.backingScaleFactor
        let scaleY = targetScreen.backingScaleFactor

        let pixelWidth = Int(round(abs(current.x - start.x) * scaleX))
        let pixelHeight = Int(round(abs(current.y - start.y) * scaleY))

        let topText = "\(pixelWidth)"
        let bottomText = "\(pixelHeight)"
        let textSize = measureNumberBadge(top: topText, bottom: bottomText)

        let offset: CGFloat = 8.0
        let margin: CGFloat = 8.0

        let curX = current.x
        let curY = current.y
        let startX = start.x
        let startY = start.y

        let draggingRight = curX >= startX
        let draggingTop = curY >= startY

        // first: top left if dragging top left, top right if dragging top right,
        // bottom right if dragging bottom right, bottom left if dragging bottom left.
        var originX: CGFloat = draggingRight ? (curX + offset) : (curX - textSize.width - offset)
        var originY: CGFloat = draggingTop ? (curY + offset) : (curY - textSize.height - offset)

        // second: flip to top if would hide below bottom edge of screen,
        // flip bottom if top of screen would hide, left if screen right, right if screen left.
        if originY < margin {
            originY = curY + offset
        }
        if originY + textSize.height > bounds.height - margin {
            originY = curY - textSize.height - offset
        }
        if originX + textSize.width > bounds.width - margin {
            originX = curX - textSize.width - offset
        }
        if originX < margin {
            originX = curX + offset
        }

        originX = round(max(margin, min(originX, bounds.width - textSize.width - margin)))
        originY = round(max(margin, min(originY, bounds.height - textSize.height - margin)))

        let isRightOfCursor = originX >= curX
        let alignment: NSTextAlignment = isRightOfCursor ? .left : .right

        drawNumberBadge(top: topText, bottom: bottomText, at: NSPoint(x: originX, y: originY), alignment: alignment, in: context)
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
