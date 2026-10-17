import AppKit
import Carbon
import CoreGraphics

// MARK: - Capture Overlay Modes

public enum CaptureOverlayMode: String, CaseIterable {
    case area = "Area"
    case ocr = "OCR"
    case ruler = "Ruler"
    case colorPicker = "Color Picker"
}

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
    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    public private(set) var activeMode: CaptureOverlayMode = .area
    public private(set) var activeDelaySeconds: Int = 0
    private var overlayPanels: [NSPanel] = []
    public private(set) var isSelecting = false
    private var completionHandler: ((CGImage?) -> Void)?
    private var regionCompletionHandler: ((SelectedRegionInfo?) -> Void)?
    private var rulerCompletionHandler: ((String?) -> Void)?
    private var colorPickerCompletionHandler: ((String?) -> Void)?
    private var screenSnapshots: [CGDirectDisplayID: CGImage] = [:]
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

    public func startRegionSelection(
        mode: CaptureOverlayMode = .area,
        completion: @escaping (SelectedRegionInfo?) -> Void
    ) {
        guard PermissionsManager.shared.ensurePermissions(for: "\(mode.rawValue) Selection") else {
            completion(nil)
            return
        }
        guard !isSelecting else { return }
        regionCompletionHandler = completion
        startSelection(mode: mode) { _ in }
    }

    public func startRuler(completion: ((String?) -> Void)? = nil) {
        guard PermissionsManager.shared.ensurePermissions(for: "Screen Ruler") else {
            completion?(nil)
            return
        }
        guard !isSelecting else { return }
        rulerCompletionHandler = completion
        startSelection(mode: .ruler) { _ in }
    }

    public func startColorPicker(completion: ((String?) -> Void)? = nil) {
        guard PermissionsManager.shared.ensurePermissions(for: "Color Picker") else {
            completion?(nil)
            return
        }
        guard !isSelecting else { return }
        colorPickerCompletionHandler = completion
        startSelection(mode: .colorPicker) { _ in }
    }

    public func startSelection(
        mode: CaptureOverlayMode = .area,
        delaySeconds: Int = 0,
        completion: @escaping (CGImage?) -> Void
    ) {
        guard PermissionsManager.shared.ensurePermissions(for: "\(mode.rawValue) Selection") else {
            completion(nil)
            return
        }
        guard !isSelecting else { return }
        isSelecting = true
        activeMode = mode
        activeDelaySeconds = delaySeconds
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
        screenSnapshots.removeAll()

        for screen in screens {
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
            let snapshot: CGImage?
            if activeMode == .colorPicker {
                snapshot = CGDisplayCreateImage(displayID) ?? CaptureService.shared.captureFullscreen(displayID: displayID)
                if let snap = snapshot {
                    screenSnapshots[displayID] = snap
                }
            } else {
                snapshot = nil
            }

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
                screen: screen,
                mode: activeMode,
                screenImage: snapshot
            )

            panel.contentView = selectionView
            overlayPanels.append(panel)
        }

        // Install consuming event tap to intercept and swallow mouse clicks/drags
        installEventTap()

        let initialCGLocation = CGEvent(source: nil)?.location ?? CGPoint.zero
        liveCurrentPoint = initialCGLocation
        updateOverlays(globalCGPoint: initialCGLocation)

        // Show transparent overlays without stealing key focus or deactivating frontmost app
        for panel in overlayPanels {
            panel.orderFrontRegardless()
        }
        hideSystemCursor()

        updateOverlays(globalCGPoint: initialCGLocation)
    }

    // MARK: - Finish

    private func finish(with image: CGImage?, measurement: String? = nil, colorHex: String? = nil) {
        guard isSelecting else {
            showSystemCursor()
            return
        }
        isSelecting = false
        activeDelaySeconds = 0

        showSystemCursor()

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
        screenSnapshots.removeAll()
        CATransaction.flush()

        let handler = completionHandler
        completionHandler = nil
        handler?(image)

        let regHandler = regionCompletionHandler
        regionCompletionHandler = nil
        regHandler?(nil)

        let rulerHandler = rulerCompletionHandler
        rulerCompletionHandler = nil
        rulerHandler?(measurement)

        let colorHandler = colorPickerCompletionHandler
        colorPickerCompletionHandler = nil
        colorHandler?(colorHex)
    }

    // MARK: - Cursor Visibility Management

    private static var hasEnabledBackgroundCursor = false

    /// Enables cursor manipulation from background connections via CoreGraphics private API.
    /// This allows Shots to hide the system cursor and set custom cursors without activating
    /// or stealing key window status, preserving open context menus and submenus in other apps.
    private static func enableBackgroundCursorControl() {
        guard !hasEnabledBackgroundCursor else { return }
        hasEnabledBackgroundCursor = true

        typealias CGSSetConnectionPropertyFunc = @convention(c) (Int32, Int32, CFString, CFBoolean) -> Int32
        typealias CGSDefaultConnectionFunc = @convention(c) () -> Int32

        let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
        let fallbackHandle = UnsafeMutableRawPointer(bitPattern: -2)

        let setPropSym = (handle != nil ? dlsym(handle, "CGSSetConnectionProperty") : nil) ?? dlsym(fallbackHandle, "CGSSetConnectionProperty")
        let defaultConnSym = (handle != nil ? dlsym(handle, "_CGSDefaultConnection") : nil) ?? dlsym(fallbackHandle, "_CGSDefaultConnection")

        guard let setProp = setPropSym, let defaultConn = defaultConnSym else { return }

        let setConnectionProperty = unsafeBitCast(setProp, to: CGSSetConnectionPropertyFunc.self)
        let defaultConnection = unsafeBitCast(defaultConn, to: CGSDefaultConnectionFunc.self)

        let cid = defaultConnection()
        _ = setConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }

    private func hideSystemCursor() {
        guard !isCursorHidden else { return }
        isCursorHidden = true

        Self.enableBackgroundCursorControl()

        CGDisplayHideCursor(kCGNullDirectDisplay)
        for screen in NSScreen.screens {
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
            CGDisplayHideCursor(displayID)
        }
        NSCursor.hide()
        RegionSelectionView.invisibleCursor.push()
        RegionSelectionView.invisibleCursor.set()
    }

    private func showSystemCursor() {
        guard isCursorHidden else {
            NSCursor.arrow.set()
            return
        }
        isCursorHidden = false

        for screen in NSScreen.screens {
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
            CGDisplayShowCursor(displayID)
        }
        CGDisplayShowCursor(kCGNullDirectDisplay)
        NSCursor.unhide()
        NSCursor.pop()
        NSCursor.arrow.set()
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
            NSLog("Shots: Consuming event tap unavailable. Prompting Accessibility permission and falling back to listen-only.")
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
            if !isCursorHidden {
                hideSystemCursor()
            }
            RegionSelectionView.invisibleCursor.set()
            updateOverlays(globalCGPoint: cgPoint)
            return true // consume

        case .leftMouseDragged:
            if liveIsDragging {
                liveCurrentPoint = cgPoint
            }
            if !isCursorHidden {
                hideSystemCursor()
            }
            RegionSelectionView.invisibleCursor.set()
            updateOverlays(globalCGPoint: cgPoint)
            return true // consume

        case .leftMouseDown:
            if activeMode == .colorPicker {
                if let sampled = sampleColorAtGlobalPoint(cgPoint) {
                    copyToPasteboard(sampled.hex)
                    OCRNotificationController.shared.show(snippet: "Color copied: \(sampled.hex)")
                    finish(with: nil, measurement: nil, colorHex: sampled.hex)
                } else {
                    finish(with: nil)
                }
                return true
            }

            liveStartPoint = cgPoint
            liveCurrentPoint = cgPoint
            liveIsDragging = true
            updateOverlays(globalCGPoint: cgPoint)
            return true // consume

        case .leftMouseUp:
            if activeMode == .colorPicker {
                if let sampled = sampleColorAtGlobalPoint(cgPoint) {
                    copyToPasteboard(sampled.hex)
                    OCRNotificationController.shared.show(snippet: "Color copied: \(sampled.hex)")
                    finish(with: nil, measurement: nil, colorHex: sampled.hex)
                } else {
                    finish(with: nil)
                }
                return true
            }

            guard liveIsDragging, let start = liveStartPoint else { return true }
            let end = cgPoint
            liveIsDragging = false
            liveCurrentPoint = nil
            liveStartPoint = nil

            if activeMode == .ruler {
                let dx = abs(end.x - start.x)
                let dy = abs(end.y - start.y)
                let dist = hypot(dx, dy)
                let measurement = (dx < 2 && dy < 2)
                    ? String(format: "X: %.0f, Y: %.0f px", end.x, end.y)
                    : String(format: "%.0f × %.0f px (Dist: %.1f px)", dx, dy, dist)
                copyToPasteboard(measurement)
                OCRNotificationController.shared.show(snippet: "Ruler copied: \(measurement)")
                finish(with: nil, measurement: measurement, colorHex: nil)
                return true
            }

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

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    public func sampleColorAtGlobalPoint(_ globalCGPoint: CGPoint) -> (hex: String, rgb: (r: Int, g: Int, b: Int))? {
        let targetScreen = CaptureService.shared.screen(containingCGPoint: globalCGPoint)
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else { return nil }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()

        let screenImage = screenSnapshots[displayID] ?? CGDisplayCreateImage(displayID)
        guard let image = screenImage else { return nil }

        let screenFrame = screen.frame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height
        let screenTop = primaryHeight - screenFrame.maxY

        let localX = globalCGPoint.x - screenFrame.minX
        let localY = globalCGPoint.y - screenTop

        let scaleX = CGFloat(image.width) / screenFrame.width
        let scaleY = CGFloat(image.height) / screenFrame.height

        let pixelX = max(0, min(Int(round(localX * scaleX)), image.width - 1))
        let pixelY = max(0, min(Int(round(localY * scaleY)), image.height - 1))

        return extractColor(from: image, x: pixelX, y: pixelY)
    }

    public func extractColor(from image: CGImage, x: Int, y: Int) -> (hex: String, rgb: (r: Int, g: Int, b: Int))? {
        guard x >= 0 && x < image.width && y >= 0 && y < image.height else { return nil }
        guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }

        var pixel: [UInt8] = [0, 0, 0, 0]
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: Self.sRGBColorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let r = Int(pixel[0])
        let g = Int(pixel[1])
        let b = Int(pixel[2])
        let hex = String(format: "#%02X%02X%02X", r, g, b)
        return (hex: hex, rgb: (r, g, b))
    }

    /// Update mouse coordinates and selection rect on all screen overlays.
    private func updateOverlays(globalCGPoint: NSPoint) {
        if !isCursorHidden {
            hideSystemCursor()
        }
        RegionSelectionView.invisibleCursor.set()

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

        let delay = self.activeDelaySeconds
        let isRegion = (selRect.width >= 6 && selRect.height >= 6)

        let captureAction = { [weak self] in
            guard let self = self else { return }
            if isRegion {
                CaptureManager.shared.lastCapture = LastCaptureRecord(
                    mode: .region(rect: selRect, screenFrame: screenFrame, displayID: displayID)
                )
                let fullImage = CGDisplayCreateImage(displayID)
                var cropped = fullImage.flatMap { self.cropImage($0, to: selRect, in: viewSize) }
                if AppSettings.shared.includeCursor, let validCrop = cropped {
                    cropped = CaptureService.shared.compositeCursor(
                        on: validCrop,
                        screen: targetScreen,
                        cropRect: selRect
                    )
                }
                self.finish(with: cropped ?? fullImage)
            } else {
                CaptureManager.shared.lastCapture = LastCaptureRecord(mode: .fullscreen)
                // Click without drag captures full display
                var fullImage = CGDisplayCreateImage(displayID)
                if AppSettings.shared.includeCursor, let validFull = fullImage {
                    fullImage = CaptureService.shared.compositeCursor(on: validFull, screen: targetScreen)
                }
                self.finish(with: fullImage)
            }
        }

        if delay > 0 && activeMode == .area {
            // Remove event tap, escape hotkey, and restore system mouse cursor so the user can interact freely during countdown
            removeEscapeHotKey()
            removeEventTap()
            if let monitor = localKeyDownMonitor {
                NSEvent.removeMonitor(monitor)
                localKeyDownMonitor = nil
            }
            showSystemCursor()
            NSCursor.unhide()
            NSCursor.arrow.set()
            CGDisplayShowCursor(kCGNullDirectDisplay)

            CountdownHUDController.shared.startCountdown(seconds: delay, screen: targetScreen, onComplete: {
                captureAction()
            }, onCancel: { [weak self] in
                self?.finish(with: nil)
            })
        } else {
            captureAction()
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
    fileprivate let mode: CaptureOverlayMode
    fileprivate let screenImage: CGImage?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var currentMousePoint: NSPoint?
    private var isDragging = false

    init(
        frame frameRect: NSRect,
        screen: NSScreen,
        mode: CaptureOverlayMode = .area,
        screenImage: CGImage? = nil
    ) {
        self.targetScreen = screen
        self.mode = mode
        self.screenImage = screenImage
        super.init(frame: frameRect)
        wantsLayer = true

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
        let changed = (currentMousePoint != mousePoint) ||
                      (isDragging != dragging) ||
                      (startPoint != selectionStart) ||
                      (currentPoint != selectionCurrent)
        guard changed else { return }

        currentMousePoint = mousePoint
        isDragging = dragging
        startPoint = selectionStart
        currentPoint = selectionCurrent
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { false }

    // MARK: - Transparent Native Cursor

    static let invisibleCursor: NSCursor = {
        let size = NSSize(width: 1, height: 1)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.set()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: .zero)
    }()

    override func resetCursorRects() {
        super.resetCursorRects()
        discardCursorRects()
        addCursorRect(bounds, cursor: Self.invisibleCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        Self.invisibleCursor.set()
    }

    // MARK: - Drawing & Rendering

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        switch mode {
        case .area:
            drawAreaAndOCR(in: context, isOCR: false)
        case .ocr:
            drawAreaAndOCR(in: context, isOCR: true)
        case .ruler:
            drawRuler(in: context)
        case .colorPicker:
            drawColorPicker(in: context)
        }
    }

    // MARK: - Area & OCR Modes

    private func drawAreaAndOCR(in context: CGContext, isOCR: Bool) {
        // 1. Selection Marquee
        if isDragging, let start = startPoint, let current = currentPoint {
            let selRect = normalizedRect(from: start, to: current)
            if selRect.width > 0 && selRect.height > 0 {
                context.saveGState()

                if isOCR {
                    // Lavender translucent highlight
                    context.setFillColor(CGColor(red: 0.66, green: 0.33, blue: 0.97, alpha: 0.18))
                    context.fill(selRect)

                    // Vibrant violet outer border (1.5pt)
                    context.setStrokeColor(CGColor(red: 0.58, green: 0.20, blue: 0.92, alpha: 0.95))
                    context.setLineWidth(1.5)
                    context.stroke(selRect.insetBy(dx: -0.75, dy: -0.75))

                    // Bright lavender inner border (1.0pt)
                    context.setStrokeColor(CGColor(red: 0.85, green: 0.70, blue: 1.0, alpha: 1.0))
                    context.setLineWidth(1.0)
                    context.stroke(selRect)
                } else {
                    // Bright luminous translucent highlight
                    context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.22))
                    context.fill(selRect)

                    // Vibrant macOS accent outer border (1.5pt)
                    context.setStrokeColor(CGColor(red: 0.12, green: 0.58, blue: 1.0, alpha: 0.90))
                    context.setLineWidth(1.5)
                    context.stroke(selRect.insetBy(dx: -0.75, dy: -0.75))

                    // Bright pure white inner border (1.0pt)
                    context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
                    context.setLineWidth(1.0)
                    context.stroke(selRect)
                }
                context.restoreGState()

                let tag: String? = isOCR ? "OCR" : nil
                drawSelectionDimensionsBadge(start: start, current: current, in: context, tag: tag)
            }
        }

        // 2. Precision reticle crosshair cursor
        let activePoint = currentPoint ?? currentMousePoint
        if let pt = activePoint, bounds.contains(pt) {
            let ringColor = isOCR ? CGColor(red: 0.66, green: 0.33, blue: 0.97, alpha: 0.90) : nil
            drawPrecisionCrosshair(at: pt, in: context, ringColorOverride: ringColor)

            if !isDragging {
                let tag: String? = isOCR ? "OCR" : nil
                drawCoordinateBadge(at: pt, in: context, tag: tag)
            }
        }
    }

    // MARK: - Ruler Mode

    private func drawRuler(in context: CGContext) {
        let activePoint = currentPoint ?? currentMousePoint
        guard let pt = activePoint, bounds.contains(pt) else { return }

        // 1. Full-screen alignment guidelines
        context.saveGState()
        context.setStrokeColor(CGColor(red: 0.12, green: 0.58, blue: 1.0, alpha: 0.45))
        context.setLineWidth(1.0)
        let dashes: [CGFloat] = [4.0, 3.0]
        context.setLineDash(phase: 0, lengths: dashes)

        // Horizontal guideline
        context.move(to: CGPoint(x: 0, y: round(pt.y)))
        context.addLine(to: CGPoint(x: bounds.width, y: round(pt.y)))

        // Vertical guideline
        context.move(to: CGPoint(x: round(pt.x), y: 0))
        context.addLine(to: CGPoint(x: round(pt.x), y: bounds.height))
        context.strokePath()
        context.restoreGState()

        // 2. Measurement Vector & Rect
        if isDragging, let start = startPoint, let current = currentPoint {
            let selRect = normalizedRect(from: start, to: current)
            if selRect.width > 0 && selRect.height > 0 {
                context.saveGState()

                // Light blue box fill
                context.setFillColor(CGColor(red: 0.12, green: 0.58, blue: 1.0, alpha: 0.12))
                context.fill(selRect)

                // Perimeter stroke
                context.setStrokeColor(CGColor(red: 0.12, green: 0.58, blue: 1.0, alpha: 0.85))
                context.setLineWidth(1.0)
                context.stroke(selRect)

                // Diagonal measurement vector
                context.setStrokeColor(CGColor(red: 0.12, green: 0.58, blue: 1.0, alpha: 0.95))
                context.setLineWidth(1.5)
                context.move(to: CGPoint(x: start.x, y: start.y))
                context.addLine(to: CGPoint(x: current.x, y: current.y))
                context.strokePath()

                // Endpoint circles
                context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
                context.fillEllipse(in: CGRect(x: start.x - 3.0, y: start.y - 3.0, width: 6.0, height: 6.0))
                context.fillEllipse(in: CGRect(x: current.x - 3.0, y: current.y - 3.0, width: 6.0, height: 6.0))

                context.restoreGState()

                let scale = targetScreen.backingScaleFactor
                let dx = abs(current.x - start.x) * scale
                let dy = abs(current.y - start.y) * scale
                let dist = hypot(dx, dy)
                let text = String(format: "W: %.0f px  H: %.0f px  Dist: %.1f px", dx, dy, dist)
                drawPillBadge(text: text, at: current, in: context)
            }
        } else {
            drawPrecisionCrosshair(at: pt, in: context)
            let scale = targetScreen.backingScaleFactor
            let curX = Int(round(pt.x * scale))
            let curY = Int(round((bounds.height - pt.y) * scale))
            drawPillBadge(text: "X: \(curX) px  Y: \(curY) px", at: pt, in: context)
        }
    }

    // MARK: - Color Picker Mode

    private func drawColorPicker(in context: CGContext) {
        let activePoint = currentPoint ?? currentMousePoint
        guard let pt = activePoint, bounds.contains(pt) else { return }

        // Center reticle ring at cursor location (9pt diameter with 1pt center hole)
        context.saveGState()
        let reticleRect = CGRect(x: round(pt.x) - 4.5, y: round(pt.y) - 4.5, width: 9.0, height: 9.0)
        context.setStrokeColor(CGColor(gray: 0.0, alpha: 0.8))
        context.setLineWidth(2.5)
        context.strokeEllipse(in: reticleRect)
        context.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
        context.setLineWidth(1.2)
        context.strokeEllipse(in: reticleRect)
        context.restoreGState()

        // Calculate Loupe Position
        let diameter: CGFloat = 126.0
        let pillHeight: CGFloat = 36.0
        let gap: CGFloat = 8.0
        let totalHeight = diameter + gap + pillHeight

        let offset: CGFloat = 20.0
        let margin: CGFloat = 12.0

        var originX = pt.x + offset
        var originY = pt.y + offset

        if originX + diameter > bounds.width - margin {
            originX = pt.x - diameter - offset
        }
        if originX < margin {
            originX = margin
        }

        if originY + totalHeight > bounds.height - margin {
            originY = pt.y - totalHeight - offset
        }
        if originY < margin {
            originY = margin
        }

        let loupeCircleRect = CGRect(x: originX, y: originY + gap + pillHeight, width: diameter, height: diameter)
        let pillRect = CGRect(x: originX, y: originY, width: diameter, height: pillHeight)

        // 1. Draw Loupe Shadow
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: CGColor(gray: 0, alpha: 0.55))
        context.setFillColor(CGColor(gray: 0.12, alpha: 1.0))
        context.fillEllipse(in: loupeCircleRect)
        context.restoreGState()

        // 2. Draw Magnified 9x9 Pixel Grid
        let scaleX = screenImage != nil ? CGFloat(screenImage!.width) / bounds.width : targetScreen.backingScaleFactor
        let scaleY = screenImage != nil ? CGFloat(screenImage!.height) / bounds.height : targetScreen.backingScaleFactor
        let imgX = Int(round(pt.x * scaleX))
        let imgY = Int(round((bounds.height - pt.y) * scaleY))

        var centerColor = NSColor.black
        var centerHex = "#000000"
        var centerRGB = "rgb(0, 0, 0)"

        if let img = screenImage {
            if let sampled = RegionSelectionCoordinator.shared.extractColor(from: img, x: imgX, y: imgY) {
                centerHex = sampled.hex
                centerRGB = "rgb(\(sampled.rgb.r), \(sampled.rgb.g), \(sampled.rgb.b))"
                centerColor = NSColor(
                    srgbRed: CGFloat(sampled.rgb.r) / 255.0,
                    green: CGFloat(sampled.rgb.g) / 255.0,
                    blue: CGFloat(sampled.rgb.b) / 255.0,
                    alpha: 1.0
                )
            }

            context.saveGState()
            context.addEllipse(in: loupeCircleRect)
            context.clip()

            let cropRect = CGRect(x: imgX - 4, y: imgY - 4, width: 9, height: 9)
            if let cropped = img.cropping(to: cropRect) {
                context.interpolationQuality = .none
                context.draw(cropped, in: loupeCircleRect)
            } else {
                context.setFillColor(centerColor.cgColor)
                context.fill(loupeCircleRect)
            }

            // Gridlines
            let cellSize = diameter / 9.0
            context.setStrokeColor(CGColor(gray: 1.0, alpha: 0.18))
            context.setLineWidth(0.75)
            for i in 1..<9 {
                let cellOffset = CGFloat(i) * cellSize
                context.move(to: CGPoint(x: loupeCircleRect.minX + cellOffset, y: loupeCircleRect.minY))
                context.addLine(to: CGPoint(x: loupeCircleRect.minX + cellOffset, y: loupeCircleRect.maxY))
                context.move(to: CGPoint(x: loupeCircleRect.minX, y: loupeCircleRect.minY + cellOffset))
                context.addLine(to: CGPoint(x: loupeCircleRect.maxX, y: loupeCircleRect.minY + cellOffset))
            }
            context.strokePath()

            // Center pixel highlight (cell 4, 4)
            let centerCell = CGRect(
                x: loupeCircleRect.minX + 4.0 * cellSize,
                y: loupeCircleRect.minY + 4.0 * cellSize,
                width: cellSize,
                height: cellSize
            )
            context.setStrokeColor(CGColor(gray: 0.0, alpha: 0.65))
            context.setLineWidth(2.2)
            context.stroke(centerCell)
            context.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
            context.setLineWidth(1.2)
            context.stroke(centerCell)

            context.restoreGState()
        }

        // 3. Loupe Outer Ring
        context.setStrokeColor(CGColor(gray: 1.0, alpha: 0.95))
        context.setLineWidth(2.5)
        context.strokeEllipse(in: loupeCircleRect)

        // 4. Color Info Pill Badge below loupe
        drawColorPickerBadge(
            rect: pillRect,
            color: centerColor,
            hex: centerHex,
            rgbText: centerRGB,
            in: context
        )
    }

    // MARK: - Precision Minimalist Reticle Crosshair Cursor

    private static let crosshairColorSpace = CGColorSpaceCreateDeviceRGB()

    private static let crosshairCasingGradient: CGGradient? = {
        let casingComponents: [CGFloat] = [
            1.00, 1.00, 1.00, 0.16,
            1.00, 1.00, 1.00, 0.16,
            1.00, 1.00, 1.00, 0.00
        ]
        let locations: [CGFloat] = [0.0, 0.5, 1.0]
        return CGGradient(colorSpace: crosshairColorSpace, colorComponents: casingComponents, locations: locations, count: 3)
    }()

    private static let crosshairStrokeGradient: CGGradient? = {
        let strokeComponents: [CGFloat] = [
            0.20, 0.20, 0.20, 1.00,
            0.20, 0.20, 0.20, 1.00,
            0.20, 0.20, 0.20, 0.00
        ]
        let locations: [CGFloat] = [0.0, 0.5, 1.0]
        return CGGradient(colorSpace: crosshairColorSpace, colorComponents: strokeComponents, locations: locations, count: 3)
    }()

    private func drawPrecisionCrosshair(
        at point: NSPoint,
        in context: CGContext,
        size: CGFloat = 32.0,
        ringColorOverride: CGColor? = nil
    ) {
        let cx = round(point.x)
        let cy = round(point.y)
        let lineHalf = size * 0.375

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

        let circleFillColor = CGColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 0.12)
        context.setFillColor(circleFillColor)
        context.fillEllipse(in: circleRect)

        let circleOutlineColor = ringColorOverride ?? CGColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 0.50)
        context.setStrokeColor(circleOutlineColor)
        context.setLineWidth(circleStrokeWidth)
        context.strokeEllipse(in: circleRect)

        let centerGap: CGFloat = 0.5
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
                CrosshairArm(
                    outer: CGPoint(x: cx - lineHalf, y: cy),
                    inner: CGPoint(x: cx - centerGap, y: cy),
                    strokeRect: CGRect(x: cx - lineHalf, y: cy - crosshairStrokeWidth / 2.0, width: armLength, height: crosshairStrokeWidth),
                    casingRect: CGRect(x: cx - lineHalf, y: cy - casingWidth / 2.0, width: armLength, height: casingWidth)
                ),
                CrosshairArm(
                    outer: CGPoint(x: cx + lineHalf, y: cy),
                    inner: CGPoint(x: cx + centerGap, y: cy),
                    strokeRect: CGRect(x: cx + centerGap, y: cy - crosshairStrokeWidth / 2.0, width: armLength, height: crosshairStrokeWidth),
                    casingRect: CGRect(x: cx + centerGap, y: cy - casingWidth / 2.0, width: armLength, height: casingWidth)
                ),
                CrosshairArm(
                    outer: CGPoint(x: cx, y: cy - lineHalf),
                    inner: CGPoint(x: cx, y: cy - centerGap),
                    strokeRect: CGRect(x: cx - crosshairStrokeWidth / 2.0, y: cy - lineHalf, width: crosshairStrokeWidth, height: armLength),
                    casingRect: CGRect(x: cx - casingWidth / 2.0, y: cy - lineHalf, width: casingWidth, height: armLength)
                ),
                CrosshairArm(
                    outer: CGPoint(x: cx, y: cy + lineHalf),
                    inner: CGPoint(x: cx, y: cy + centerGap),
                    strokeRect: CGRect(x: cx - crosshairStrokeWidth / 2.0, y: cy + centerGap, width: crosshairStrokeWidth, height: armLength),
                    casingRect: CGRect(x: cx - casingWidth / 2.0, y: cy + centerGap, width: casingWidth, height: armLength)
                )
            ]

            for arm in arms {
                context.saveGState()
                context.clip(to: arm.casingRect)
                context.drawLinearGradient(casingGradient, start: arm.outer, end: arm.inner, options: [])
                context.restoreGState()
            }

            for arm in arms {
                context.saveGState()
                context.clip(to: arm.strokeRect)
                context.drawLinearGradient(strokeGradient, start: arm.outer, end: arm.inner, options: [])
                context.restoreGState()
            }
        }

        context.restoreGState()
    }

    // MARK: - Live Numbers Rendering

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
        return NSSize(width: ceil(width), height: 16.0)
    }

    private func drawNumberBadge(
        top: String,
        bottom: String,
        at origin: NSPoint,
        alignment: NSTextAlignment,
        in context: CGContext,
        tag: String? = nil
    ) {
        let font = Self.numberFont
        let attributes = Self.numberAttributes

        let finalTop = tag != nil ? "[\(tag!)] \(top)" : top

        let topWidth = (finalTop as NSString).size(withAttributes: attributes).width
        let bottomWidth = (bottom as NSString).size(withAttributes: attributes).width
        let maxWidth = max(topWidth, bottomWidth)

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
        (finalTop as NSString).draw(at: topOrigin, withAttributes: attributes)
    }

    // MARK: - Live Coordinate Badge Next to Cursor (Hover Only)

    private func drawCoordinateBadge(at point: NSPoint, in context: CGContext, tag: String? = nil) {
        let scaleX = targetScreen.backingScaleFactor
        let scaleY = targetScreen.backingScaleFactor
        let maxPixelX = Int(bounds.width * scaleX)
        let maxPixelY = Int(bounds.height * scaleY)

        let curX = max(0, min(Int(round(point.x * scaleX)), maxPixelX))
        let curY = max(0, min(Int(round((bounds.height - point.y) * scaleY)), maxPixelY))

        let topText = "\(curX)"
        let bottomText = "\(curY)"
        let textSize = measureNumberBadge(top: topText, bottom: bottomText)

        let xOffset: CGFloat = 8.0
        let visualGap: CGFloat = 1.0
        let margin: CGFloat = 8.0

        let inkHeight: CGFloat = 16.0
        let inkBottomOffset: CGFloat = 2.0

        var originX = point.x + xOffset
        var originY = point.y - inkHeight - visualGap

        if originY < margin {
            originY = point.y + visualGap - inkBottomOffset
        }
        if originY + inkHeight > bounds.height - margin {
            originY = point.y - inkHeight - visualGap
        }
        if originX + textSize.width > bounds.width - margin {
            originX = point.x - textSize.width - xOffset
        }
        if originX < margin {
            originX = point.x + xOffset
        }

        originX = round(max(margin, min(originX, bounds.width - textSize.width - margin)))
        originY = round(max(margin, min(originY, bounds.height - inkHeight - margin)))

        let isRightOfCursor = originX >= point.x
        let alignment: NSTextAlignment = isRightOfCursor ? .left : .right

        drawNumberBadge(top: topText, bottom: bottomText, at: NSPoint(x: originX, y: originY), alignment: alignment, in: context, tag: tag)
    }

    // MARK: - Live Selection Dimensions Badge (Drag Only)

    private func drawSelectionDimensionsBadge(start: NSPoint, current: NSPoint, in context: CGContext, tag: String? = nil) {
        let scaleX = targetScreen.backingScaleFactor
        let scaleY = targetScreen.backingScaleFactor

        let pixelWidth = Int(round(abs(current.x - start.x) * scaleX))
        let pixelHeight = Int(round(abs(current.y - start.y) * scaleY))

        let topText = "\(pixelWidth)"
        let bottomText = "\(pixelHeight)"
        let textSize = measureNumberBadge(top: topText, bottom: bottomText)

        let xOffset: CGFloat = 8.0
        let visualGap: CGFloat = 1.0
        let margin: CGFloat = 8.0

        let curX = current.x
        let curY = current.y
        let startX = start.x
        let startY = start.y

        let draggingRight = curX >= startX
        let draggingTop = curY >= startY

        let inkHeight: CGFloat = 16.0
        let inkBottomOffset: CGFloat = 2.0

        var originX: CGFloat = draggingRight ? (curX + xOffset) : (curX - textSize.width - xOffset)
        var originY: CGFloat = draggingTop ? (curY + visualGap - inkBottomOffset) : (curY - inkHeight - visualGap)

        if originY < margin {
            originY = curY + visualGap - inkBottomOffset
        }
        if originY + inkHeight > bounds.height - margin {
            originY = curY - inkHeight - visualGap
        }
        if originX + textSize.width > bounds.width - margin {
            originX = curX - textSize.width - xOffset
        }
        if originX < margin {
            originX = curX + xOffset
        }

        originX = round(max(margin, min(originX, bounds.width - textSize.width - margin)))
        originY = round(max(margin, min(originY, bounds.height - inkHeight - margin)))

        let isRightOfCursor = originX >= curX
        let alignment: NSTextAlignment = isRightOfCursor ? .left : .right

        drawNumberBadge(top: topText, bottom: bottomText, at: NSPoint(x: originX, y: originY), alignment: alignment, in: context, tag: tag)
    }

    // MARK: - Pill Badge Helper

    private func drawPillBadge(text: String, at point: NSPoint, in context: CGContext) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attr)
        let pillWidth = textSize.width + 16.0
        let pillHeight = textSize.height + 10.0

        let offset: CGFloat = 12.0
        let margin: CGFloat = 8.0

        var originX = point.x + offset
        var originY = point.y - pillHeight - offset

        if originY < margin {
            originY = point.y + offset
        }
        if originY + pillHeight > bounds.height - margin {
            originY = point.y - pillHeight - offset
        }
        if originX + pillWidth > bounds.width - margin {
            originX = point.x - pillWidth - offset
        }
        if originX < margin {
            originX = point.x + offset
        }

        let rect = CGRect(
            x: round(max(margin, min(originX, bounds.width - pillWidth - margin))),
            y: round(max(margin, min(originY, bounds.height - pillHeight - margin))),
            width: pillWidth,
            height: pillHeight
        )

        context.saveGState()
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.92).setFill()
        path.fill()
        NSColor(white: 1.0, alpha: 0.22).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        (text as NSString).draw(
            at: NSPoint(x: rect.minX + 8.0, y: rect.minY + 5.0),
            withAttributes: attr
        )
        context.restoreGState()
    }

    // MARK: - Color Picker Badge Helper

    private func drawColorPickerBadge(
        rect: CGRect,
        color: NSColor,
        hex: String,
        rgbText: String,
        in context: CGContext
    ) {
        context.saveGState()

        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.94).setFill()
        path.fill()
        NSColor(white: 1.0, alpha: 0.18).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        let swatchRect = CGRect(x: rect.minX + 8, y: rect.minY + 8, width: 20, height: 20)
        let swatchPath = NSBezierPath(roundedRect: swatchRect, xRadius: 4, yRadius: 4)
        color.setFill()
        swatchPath.fill()
        NSColor(white: 1.0, alpha: 0.35).setStroke()
        swatchPath.lineWidth = 1.0
        swatchPath.stroke()

        let textX = swatchRect.maxX + 8
        let hexFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let rgbFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular)

        let hexAttr: [NSAttributedString.Key: Any] = [
            .font: hexFont,
            .foregroundColor: NSColor.white
        ]
        let rgbAttr: [NSAttributedString.Key: Any] = [
            .font: rgbFont,
            .foregroundColor: NSColor(white: 0.75, alpha: 1.0)
        ]

        let hexStr = (hex as NSString)
        let rgbStr = (rgbText as NSString)
        hexStr.draw(at: NSPoint(x: textX, y: rect.minY + 18), withAttributes: hexAttr)
        rgbStr.draw(at: NSPoint(x: textX, y: rect.minY + 5), withAttributes: rgbAttr)

        context.restoreGState()
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
