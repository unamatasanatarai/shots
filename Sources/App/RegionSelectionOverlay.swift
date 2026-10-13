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
    private var cursorHideCount = 0
    private var savedCursor: NSCursor?

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreSystemCursor()
        }
    }

    deinit {
        restoreSystemCursor()
    }

    // MARK: - Temporary Custom Cursor Overlay Lifecycle (Hide, Draw, Track, Restore)

    /// Step 1 & 2: Save the current cursor state and hide the system cursor.
    private func hideSystemCursor() {
        guard !isCursorHidden else { return }
        isCursorHidden = true

        // 1. Save the current cursor state
        savedCursor = NSCursor.current

        // 2. Hide the system cursor (WindowServer display hardware + Cocoa cursor)
        hideDisplayCursors()
        cursorHideCount = 1

        NSCursor.hide()
        RegionSelectionView.invisibleCursor.push()
    }

    private func hideDisplayCursors() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        for display in displays {
            CGDisplayHideCursor(display)
        }
    }

    private func showDisplayCursors() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        for display in displays {
            CGDisplayShowCursor(display)
        }
    }

    private func rehideSystemCursorIfNeeded() {
        NSCursor.hide()
        RegionSelectionView.invisibleCursor.set()
    }

    /// Step 5: When the operation ends, hide the graphic and restore the system cursor.
    private func restoreSystemCursor() {
        guard isCursorHidden else { return }
        isCursorHidden = false

        // 5. Restore the system cursor and saved cursor state
        NSCursor.pop()
        NSCursor.unhide()

        while cursorHideCount > 0 {
            showDisplayCursors()
            cursorHideCount -= 1
        }

        savedCursor?.set()
        savedCursor = nil
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

        // Hide normal system mouse cursor while taking shots
        hideSystemCursor()

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

            // Overlay panel captures cursor rects to enforce complete system pointer invisibility.
            // All mouse clicks/drags are intercepted and consumed by the CGEventTap.
            panel.ignoresMouseEvents = false
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

        // Immediately resolve the exact current hardware mouse location from WindowServer
        let initialCGLocation: CGPoint = {
            if let event = CGEvent(source: nil) {
                return event.location
            }
            let appKit = NSEvent.mouseLocation
            let primaryH = NSScreen.screens.first?.frame.height ?? 0
            return CGPoint(x: appKit.x, y: primaryH - appKit.y)
        }()
        liveCurrentPoint = initialCGLocation

        // Immediately position the crosshair reticle center exactly at the hardware mouse cursor
        updateOverlays(globalCGPoint: initialCGLocation)

        // Show transparent overlays without stealing key focus from existing windows or menus
        for panel in overlayPanels {
            panel.orderFrontRegardless()
            panel.resetCursorRects()
        }
    }

    // MARK: - Finish

    private func finish(with image: CGImage?) {
        guard isSelecting else { return }
        isSelecting = false

        restoreSystemCursor()

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
            return true // consume — swallow hover events so menus don't change focus or open submenus

        case .leftMouseDragged:
            if liveIsDragging {
                liveCurrentPoint = cgPoint
                rehideSystemCursorIfNeeded()
            }
            updateOverlays(globalCGPoint: cgPoint)
            return true // consume

        case .leftMouseDown:
            liveStartPoint = cgPoint
            liveCurrentPoint = cgPoint
            liveIsDragging = true
            // macOS unhides cursor upon click at WindowServer level; explicitly re-hide display cursor and Cocoa cursor
            hideDisplayCursors()
            cursorHideCount += 1
            NSCursor.hide()
            RegionSelectionView.invisibleCursor.set()
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

    // MARK: - Invisible Cursor Enforcer

    static let invisibleCursor: NSCursor = {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        return NSCursor(image: image, hotSpot: .zero)
    }()

    override func resetCursorRects() {
        super.resetCursorRects()
        discardCursorRects()
        addCursorRect(bounds, cursor: Self.invisibleCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        Self.invisibleCursor.set()
        NSCursor.hide()
    }

    override func mouseEntered(with event: NSEvent) {
        Self.invisibleCursor.set()
        NSCursor.hide()
    }

    override func mouseMoved(with event: NSEvent) {
        Self.invisibleCursor.set()
    }

    override func mouseDragged(with event: NSEvent) {
        Self.invisibleCursor.set()
        NSCursor.hide()
    }

    // MARK: - Drawing & Rendering

    override func draw(_ dirtyRect: NSRect) {
        Self.invisibleCursor.set()
        if isDragging {
            NSCursor.hide()
        }

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
    // - Circle diameter: 46% of overall width (unchanged)
    // - Horizontal & vertical line length: 75% of overall width/height (compact)
    // - Crosshair strokes: solid charcoal gray, ~3% width (1.0 pt), flat/square terminals
    // - Circle outline: medium-light gray, ~2% width (0.75 pt)
    // - Circle fill: pale neutral gray, low opacity

    private func drawPrecisionCrosshair(at point: NSPoint, in context: CGContext, size: CGFloat = 32.0) {
        let cx = round(point.x)
        let cy = round(point.y)
        let lineHalf = size * 0.375  // 75% of size / 2 = shorter lines

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

        // 1. Circle interior fill: pale neutral gray, low opacity
        let circleFillColor = CGColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 0.22)
        context.setFillColor(circleFillColor)
        context.fillEllipse(in: circleRect)

        // 2. Circle outline: medium-light gray, approximately 2% of overall width
        let circleOutlineColor = CGColor(red: 0.70, green: 0.70, blue: 0.72, alpha: 0.95)
        context.setStrokeColor(circleOutlineColor)
        context.setLineWidth(circleStrokeWidth)
        context.strokeEllipse(in: circleRect)

        // 3. Crosshair strokes: solid charcoal gray, compact lines
        let charcoalColor = CGColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1.0)
        context.setStrokeColor(charcoalColor)
        context.setLineWidth(crosshairStrokeWidth)
        context.setLineCap(.butt)

        // Horizontal line: 75% of overall width
        context.move(to: CGPoint(x: cx - lineHalf, y: cy))
        context.addLine(to: CGPoint(x: cx + lineHalf, y: cy))

        // Vertical line: 75% of overall height
        context.move(to: CGPoint(x: cx, y: cy - lineHalf))
        context.addLine(to: CGPoint(x: cx, y: cy + lineHalf))

        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Live Numbers Rendering (Black Text, Soft Blurry White Outline, Zero Drop Shadow)

    private func measureNumberText(_ text: String) -> NSSize {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 1.0
        paragraphStyle.alignment = .left

        let fillAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        return NSAttributedString(string: text, attributes: fillAttributes).size()
    }

    private func drawSoftGlowNumberText(_ text: String, at origin: NSPoint, in context: CGContext) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 1.0
        paragraphStyle.alignment = .left

        let fillAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 0.10, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]

        // Delicate multi-directional white text-shadow halo (like CSS text-shadow)
        // Multiple subtle passes at slight offsets create a soft, even glow
        let shadowOffsets: [(CGFloat, CGFloat)] = [
            ( 0.0, -1.0), ( 0.0,  1.0), (-1.0,  0.0), ( 1.0,  0.0),
            ( 0.7, -0.7), (-0.7, -0.7), ( 0.7,  0.7), (-0.7,  0.7)
        ]

        for (dx, dy) in shadowOffsets {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.white.withAlphaComponent(0.40)
            shadow.shadowOffset = NSSize(width: dx, height: dy)
            shadow.shadowBlurRadius = 1.5

            let shadowAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.clear,
                .strokeColor: NSColor.white.withAlphaComponent(0.35),
                .strokeWidth: 4.0,
                .shadow: shadow,
                .paragraphStyle: paragraphStyle
            ]
            NSAttributedString(string: text, attributes: shadowAttributes).draw(at: origin)
        }

        // Crisp dark foreground text on top
        NSAttributedString(string: text, attributes: fillAttributes).draw(at: origin)
    }

    // MARK: - Live Coordinate Badge Next to Cursor (Hover Only)

    private func drawCoordinateBadge(at point: NSPoint, in context: CGContext) {
        let scaleX = targetScreen.backingScaleFactor
        let scaleY = targetScreen.backingScaleFactor
        let maxPixelX = Int(bounds.width * scaleX)
        let maxPixelY = Int(bounds.height * scaleY)

        let curX = max(0, min(Int(round(point.x * scaleX)), maxPixelX))
        let curY = max(0, min(Int(round((bounds.height - point.y) * scaleY)), maxPixelY))

        let text = "\(curX)\n\(curY)"
        let textSize = measureNumberText(text)

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

        drawSoftGlowNumberText(text, at: NSPoint(x: originX, y: originY), in: context)
    }

    // MARK: - Live Selection Dimensions Badge (Drag Only)

    private func drawSelectionDimensionsBadge(start: NSPoint, current: NSPoint, in context: CGContext) {
        let scaleX = targetScreen.backingScaleFactor
        let scaleY = targetScreen.backingScaleFactor

        let pixelWidth = Int(round(abs(current.x - start.x) * scaleX))
        let pixelHeight = Int(round(abs(current.y - start.y) * scaleY))

        let dimensionText = "\(pixelWidth)\n\(pixelHeight)"
        let textSize = measureNumberText(dimensionText)

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

        drawSoftGlowNumberText(dimensionText, at: NSPoint(x: originX, y: originY), in: context)
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
