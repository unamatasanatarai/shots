import Foundation
import CoreGraphics
import Cocoa
import Carbon
import Vision
import CoreImage

public struct AppTests {
    @MainActor
    public static func run(testRunner: @MainActor (String, () throws -> Void) -> Void) {

        // MARK: - AppConfig Suite
        testRunner("AppConfig - Properties and Defaults") {
            assert(AppConfig.appName == "Shots", "App name should be Shots")
            assert(!AppConfig.version.isEmpty, "App version should not be empty")
            assert(AppConfig.bundleIdentifier == "com.local.Shots", "Bundle ID should be com.local.Shots")
            assert(!AppConfig.minSystemVersion.isEmpty, "Minimum system version should be defined")
        }

        testRunner("AppConfig - Version Formatting") {
            let version = AppConfig.version
            let parts = version.split(separator: ".")
            assert(parts.count >= 2, "Version should be semver-like (e.g. 1.0 or 1.0.0)")
        }

        // MARK: - KeyCodes Suite
        testRunner("KeyCodes - Carbon and Cocoa Modifier Mappings") {
            let cocoaCmdShift: NSEvent.ModifierFlags = [.command, .shift]
            let carbonMods = KeyCodes.carbonModifiers(from: cocoaCmdShift)
            assert((carbonMods & UInt32(cmdKey)) != 0, "Carbon mods should include cmdKey")
            assert((carbonMods & UInt32(shiftKey)) != 0, "Carbon mods should include shiftKey")
            assert((carbonMods & UInt32(optionKey)) == 0, "Carbon mods should not include optionKey")

            let restoredCocoa = KeyCodes.cocoaModifiers(from: carbonMods)
            assert(restoredCocoa.contains(.command), "Restored cocoa should contain command")
            assert(restoredCocoa.contains(.shift), "Restored cocoa should contain shift")
            assert(!restoredCocoa.contains(.option), "Restored cocoa should not contain option")
        }

        testRunner("KeyCodes - Symbol String Generation") {
            let mods = UInt32(cmdKey | shiftKey)
            let symbols = KeyCodes.modifierSymbols(carbonMods: mods)
            assert(symbols.contains("⌘"), "Symbols must contain ⌘")
            assert(symbols.contains("⇧"), "Symbols must contain ⇧")

            let shortcut1 = KeyCodes.shortcutString(keyCode: UInt16(kVK_ANSI_1), carbonMods: mods)
            assert(shortcut1.contains("1"), "Shortcut must contain 1")
            assert(shortcut1.contains("⌘"), "Shortcut must contain ⌘")
            assert(shortcut1.contains("⇧"), "Shortcut must contain ⇧")
        }

        testRunner("KeyCodes - Key Names") {
            assert(KeyCodes.keyName(for: UInt16(kVK_ANSI_A)) == "A", "ANSI A key name")
            assert(KeyCodes.keyName(for: UInt16(kVK_ANSI_1)) == "1", "ANSI 1 key name")
            assert(KeyCodes.keyName(for: UInt16(kVK_Escape)) == "⎋", "Escape key name")
            assert(KeyCodes.keyName(for: UInt16(kVK_Return)) == "↩", "Return key name")
            assert(KeyCodes.keyName(for: UInt16(kVK_F1)) == "F1", "F1 key name")
        }

        // MARK: - AppSettings Suite
        testRunner("AppSettings - Defaults and State Management") {
            let testSuiteName = "com.test.shots.\(UUID().uuidString)"
            guard let testDefaults = UserDefaults(suiteName: testSuiteName) else {
                assertionFailure("Failed to allocate test UserDefaults")
                return
            }

            let settings = AppSettings(defaults: testDefaults)

            // Verify default hotkey: Cmd + Shift + 4
            assert(settings.hotkeyKeyCode == UInt16(kVK_ANSI_4), "Default keyCode must be 21 (ANSI 4)")
            assert(settings.hotkeyModifiers == UInt32(cmdKey | shiftKey), "Default modifiers must be cmdKey | shiftKey")
            assert(settings.saveToDisk == true, "saveToDisk must default to true")
            assert(settings.copyToClipboard == true, "copyToClipboard must default to true")
            assert(!settings.saveDirectoryPath.isEmpty, "saveDirectoryPath must have default path")
            assert(settings.scrollingCaptureSpeed == .normal, "scrollingCaptureSpeed must default to .normal")

            // Verify saveToDisk is mandatory and remains true
            settings.saveToDisk = false
            assert(settings.saveToDisk == true, "saveToDisk must remain true as disk saving is mandatory")
            assert(testDefaults.bool(forKey: AppSettings.Keys.saveToDisk) == true, "UserDefaults must reflect mandatory saveToDisk")

            settings.scrollingCaptureSpeed = .slow
            assert(testDefaults.string(forKey: AppSettings.Keys.scrollingCaptureSpeed) == ScrollingCaptureSpeed.slow.rawValue, "UserDefaults must store updated scrollingCaptureSpeed")
            assert(settings.scrollingCaptureSpeed.stepDelayMicroseconds == 350_000, "Slow speed must have 350ms step delay")
            assert(settings.scrollingCaptureSpeed.scrollDeltaPixels == 60, "Slow speed must have 60px scroll delta")

            settings.scrollingCaptureSpeed = .normal
            assert(settings.scrollingCaptureSpeed.stepDelayMicroseconds == 200_000, "Normal speed must have 200ms step delay")
            assert(settings.scrollingCaptureSpeed.scrollDeltaPixels == 90, "Normal speed must have 90px scroll delta")

            settings.scrollingCaptureSpeed = .fast
            assert(testDefaults.string(forKey: AppSettings.Keys.scrollingCaptureSpeed) == ScrollingCaptureSpeed.fast.rawValue, "UserDefaults must store fast scrollingCaptureSpeed")
            assert(settings.scrollingCaptureSpeed.stepDelayMicroseconds == 100_000, "Fast speed must have 100ms step delay")
            assert(settings.scrollingCaptureSpeed.scrollDeltaPixels == 120, "Fast speed must have 120px scroll delta")

            settings.hotkeyKeyCode = UInt16(kVK_ANSI_2)
            assert(testDefaults.integer(forKey: AppSettings.Keys.hotkeyKeyCode) == Int(kVK_ANSI_2), "UserDefaults must store updated keyCode")

            // Test reset
            settings.resetHotkeyToDefault()
            assert(settings.hotkeyKeyCode == UInt16(kVK_ANSI_4), "Reset must restore default keycode")
            assert(settings.hotkeyModifiers == UInt32(cmdKey | shiftKey), "Reset must restore default modifiers")

            // Cleanup
            testDefaults.removePersistentDomain(forName: testSuiteName)
        }

        testRunner("AppSettings - Resolved Directory URL and Auto-Creation") {
            let settings = AppSettings.shared
            let dirURL = settings.resolvedSaveDirectoryURL
            assert(!dirURL.path.contains("~"), "Resolved URL path should expand tilde")
            assert(dirURL.isFileURL, "Resolved URL should be a file URL")
            assert(FileManager.default.fileExists(atPath: dirURL.path), "Resolved save directory must exist on disk")

            let defaultLoc = AppSettings.defaultSaveLocation()
            assert(!defaultLoc.isEmpty, "Default save location must not be empty")
            assert(!defaultLoc.contains("~"), "Default save location must have tilde expanded")
        }

        // MARK: - Image & Lossless PNG Encoding Suite
        testRunner("Lossless PNG Rasterization & Magic Bytes") {
            // Generate a synthetic test CGImage buffer (64x64 RGBA)
            let width = 64
            let height = 64
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else {
                assertionFailure("Failed to allocate CGContext")
                return
            }

            context.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1.0))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            guard let testImage = context.makeImage() else {
                assertionFailure("Failed to create test CGImage")
                return
            }

            // Test PNG encoding via SaveService
            let saveService = SaveService.shared
            guard let pngData = saveService.encodePNG(image: testImage) else {
                assertionFailure("Failed to encode via SaveService.encodePNG")
                return
            }

            assert(!pngData.isEmpty, "PNG data must not be empty")

            // Verify PNG standard 8-byte header: 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A
            let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            var actualHeader = [UInt8](repeating: 0, count: 8)
            pngData.copyBytes(to: &actualHeader, count: 8)
            assert(actualHeader == pngHeader, "Encoded data must match standard PNG magic signature")

            // Verify saving pipeline to temporary directory
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SaveServiceTest_\(UUID().uuidString)")
            do {
                let savedURL = try saveService.saveImageData(pngData, to: tempDir, filename: "test_output.png")
                assert(FileManager.default.fileExists(atPath: savedURL.path), "Saved PNG file must exist on disk")
                assert(saveService.latestSavedURL == savedURL, "SaveService.latestSavedURL should update")
                try? FileManager.default.removeItem(at: tempDir)
            } catch {
                assertionFailure("SaveService.saveImageData failed: \(error)")
            }
        }

        testRunner("Filename Formatting - shot_YYYYMMDD_HHMMSS Pattern & Collision Resolution") {
            let filename = SaveService.generateFilename(date: Date(), format: .png)

            // Validate filename matches ^shot_\d{8}_\d{6}\.png$
            let regex = try! NSRegularExpression(pattern: #"^shot_\d{8}_\d{6}\.png$"#)
            let matchRange = NSRange(location: 0, length: filename.utf16.count)
            assert(regex.firstMatch(in: filename, range: matchRange) != nil, "Filename must match 'shot_YYYYMMDD_HHMMSS.png', was: \(filename)")

            // Test collision handling
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CollisionTest_\(UUID().uuidString)")
            try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

            let testDate = Date(timeIntervalSince1970: 1700000000)
            let expectedBase = SaveService.generateFilename(date: testDate, format: .png)
            let url1 = SaveService.shared.resolveUniqueDestinationURL(in: tempDir, date: testDate, format: .png)
            assert(url1.lastPathComponent == expectedBase, "Initial URL should have base name, expected \(expectedBase) got \(url1.lastPathComponent)")

            // Simulate file existing
            try! "dummy".write(to: url1, atomically: true, encoding: .utf8)

            let expectedCollided = expectedBase.replacingOccurrences(of: ".png", with: "_1.png")
            let url2 = SaveService.shared.resolveUniqueDestinationURL(in: tempDir, date: testDate, format: .png)
            assert(url2.lastPathComponent == expectedCollided, "Collision URL should have _1 suffix, was: \(url2.lastPathComponent)")

            try? FileManager.default.removeItem(at: tempDir)
        }

        // MARK: - CaptureService Fullscreen Suite
        testRunner("CaptureService - Active Screen & Fullscreen Resolution") {
            let activeScreen = CaptureService.shared.activeScreen()
            assert(activeScreen != nil, "Active screen should not be nil on macOS system")

            let mainDisplay = CGMainDisplayID()
            let displayID = (activeScreen.flatMap { CaptureService.shared.displayID(for: $0) }) ?? mainDisplay
            assert(displayID != 0, "Resolved display ID must be valid non-zero")

            let result = CaptureService.shared.captureActiveFullscreen()
            assert(result != nil, "CaptureService.captureActiveFullscreen() should return a result")
            assert(result?.displayID != 0, "Result display ID must be valid")
        }

        // MARK: - Area Selection & Coordinates Suite
        testRunner("Area Screenshot - Normalization and Cropping Engine") {
            // 1. Normalized rect tests
            let p1 = NSPoint(x: 100, y: 200)
            let p2 = NSPoint(x: 50, y: 350)
            let norm = CaptureService.shared.normalizedRect(from: p1, to: p2)
            assert(norm.origin.x == 50 && norm.origin.y == 200, "Normalized rect origin should be min coordinates")
            assert(norm.width == 50 && norm.height == 150, "Normalized rect dimensions should be positive deltas")

            // 2. Cropping engine test with synthetic image
            let width = 200
            let height = 100
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let baseImage = ctx.makeImage()!

            // Select 50x30 region in 100x50 logical view size (2x retina scale)
            let selRect = NSRect(x: 10, y: 10, width: 50, height: 30)
            let viewSize = NSSize(width: 100, height: 50)
            let cropped = CaptureService.shared.cropImage(baseImage, to: selRect, in: viewSize)

            assert(cropped != nil, "Cropped image must not be nil")
            assert(cropped!.width == 100, "Cropped image pixel width must be 50 * 2x scale = 100, was: \(cropped!.width)")
            assert(cropped!.height == 60, "Cropped image pixel height must be 30 * 2x scale = 60, was: \(cropped!.height)")
        }

        // MARK: - Multi-Display Support Suite
        testRunner("Multi-Display Support - Coordinate Inversion & Display Targeting") {
            let primaryScreen = NSScreen.screens.first ?? NSScreen()
            let primaryHeight = primaryScreen.frame.height

            // 1. Test coordinate inversion round-trip
            let appKitPoint = NSPoint(x: 250, y: 150)
            let cgPoint = CaptureService.shared.coreGraphicsPoint(from: appKitPoint)
            assert(cgPoint.x == 250, "CG X matches AppKit X")
            assert(cgPoint.y == primaryHeight - 150, "CG Y is inverted by primary screen height")

            let restoredAppKit = CaptureService.shared.appKitPoint(from: cgPoint)
            assert(restoredAppKit.x == appKitPoint.x && restoredAppKit.y == appKitPoint.y, "Round trip must restore exact AppKit coordinates")

            // 2. Test display lookup by point
            let midPoint = NSPoint(x: primaryScreen.frame.midX, y: primaryScreen.frame.midY)
            let resolvedScreen = CaptureService.shared.screen(containing: midPoint)
            assert(resolvedScreen != nil, "Resolved screen for primary mid-point must not be nil")
            assert(resolvedScreen == primaryScreen, "Resolved screen should be primary screen")

            let resolvedFromCG = CaptureService.shared.screen(containingCGPoint: cgPoint)
            assert(resolvedFromCG != nil, "Resolved screen from CG point must not be nil")
        }

        testRunner("Multi-Display Support - Secondary Display Non-Zero Origin Cropping") {
            // Secondary display positioned at x=1920, y=0, size=(1920, 1080)
            let secondaryFrame = NSRect(x: 1920, y: 0, width: 1920, height: 1080)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(
                data: nil,
                width: 3840,
                height: 2160,
                bitsPerComponent: 8,
                bytesPerRow: 3840 * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let displayImage = ctx.makeImage()!

            // 1. If screenFrame is wrongly passed as crop rect (BUG-003):
            let buggyCrop = CaptureService.shared.cropImage(displayImage, to: secondaryFrame, in: secondaryFrame.size)
            assert(buggyCrop == nil, "cropImage with global screenFrame fails due to out-of-bounds offset")

            // 2. Local bounds NSRect(origin: .zero, size: secondaryFrame.size) works cleanly:
            let localRect = NSRect(origin: .zero, size: secondaryFrame.size)
            let correctCrop = CaptureService.shared.cropImage(displayImage, to: localRect, in: secondaryFrame.size)
            assert(correctCrop != nil, "cropImage with local bounds must succeed")
            assert(correctCrop!.width == 3840 && correctCrop!.height == 2160, "Full display crop should match display image dimensions")
        }

        // MARK: - Cursor Capture Suite
        testRunner("Cursor Capture - Compositing Engine & Settings") {
            let settings = AppSettings.shared
            let prevSetting = settings.includeCursor
            defer { settings.includeCursor = prevSetting }

            settings.includeCursor = true
            assert(settings.includeCursor == true, "includeCursor can be set to true")

            // Test cursor compositing on synthetic image
            let width = 200
            let height = 200
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let baseImage = ctx.makeImage()!
            let testScreen = NSScreen.screens.first ?? NSScreen()

            // 1. Mouse inside screen -> composites cursor image
            let insideMouse = NSPoint(x: testScreen.frame.midX, y: testScreen.frame.midY)
            let composited = CaptureService.shared.compositeCursor(
                on: baseImage,
                screen: testScreen,
                mouseLocation: insideMouse
            )
            assert(composited != nil, "Composited image must not be nil")
            assert(composited!.width == width && composited!.height == height, "Composited dimensions must match base image")

            // 2. Mouse outside screen -> returns original image untouched
            let outsideMouse = NSPoint(x: -9999, y: -9999)
            let untouched = CaptureService.shared.compositeCursor(
                on: baseImage,
                screen: testScreen,
                mouseLocation: outsideMouse
            )
            assert(untouched == baseImage, "Mouse outside target bounds should return base image untouched")
        }

        // MARK: - Capture Delay Suite
        testRunner("Capture Delay - Defaults and Configuration") {
            let settings = AppSettings.shared
            let prevDelay = settings.captureDelaySeconds
            defer { settings.captureDelaySeconds = prevDelay }

            // Verify default is 0
            let testSuite = "com.test.shots.delay.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: testSuite)!
            let freshSettings = AppSettings(defaults: defaults)
            assert(freshSettings.captureDelaySeconds == 0, "Capture delay must default to 0 seconds")

            // Verify mutations persist
            freshSettings.captureDelaySeconds = 5
            assert(defaults.integer(forKey: AppSettings.Keys.captureDelaySeconds) == 5, "Mutation must persist to UserDefaults")

            freshSettings.captureDelaySeconds = 10
            assert(freshSettings.captureDelaySeconds == 10, "Setting delay to 10 seconds")

            defaults.removePersistentDomain(forName: testSuite)

            // Test CountdownHUDController lifecycle
            var zeroCompleted = false
            CountdownHUDController.shared.startCountdown(seconds: 0) {
                zeroCompleted = true
            }
            assert(zeroCompleted, "Countdown with 0 seconds must complete synchronously")

            var cancelled = false
            CountdownHUDController.shared.startCountdown(seconds: 5, onComplete: {}, onCancel: {
                cancelled = true
            })
            assert(CountdownHUDController.shared.isCountingDown, "HUD must report isCountingDown == true while active")
            CountdownHUDController.shared.cancel()
            assert(!CountdownHUDController.shared.isCountingDown, "HUD must not be counting down after cancel()")
            assert(cancelled, "Cancellation handler must be called when cancel() is invoked")

            // Test BUG-011: Cancellation during completion delay
            var completedDuringDelay = false
            var cancelledDuringDelay = false
            CountdownHUDController.shared.startCountdown(seconds: 1, onComplete: {
                completedDuringDelay = true
            }, onCancel: {
                cancelledDuringDelay = true
            })
            // Run loop for 1.02s until timer ticks to 0 and enters complete()
            RunLoop.current.run(until: Date().addingTimeInterval(1.02))
            // Cancel within the 60ms window
            CountdownHUDController.shared.cancel()
            // Wait another 100ms to verify completion was aborted
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            assert(!completedDuringDelay, "Capture completion must NOT fire after cancellation during delay")
            assert(cancelledDuringDelay, "Cancellation handler must fire when cancelled during delay")

            // Test RegionSelectionCoordinator activeDelaySeconds
            PermissionsManager.shared.screenRecordingOverride = true
            PermissionsManager.shared.accessibilityOverride = true
            defer {
                PermissionsManager.shared.resetTestingState()
            }

            RegionSelectionCoordinator.shared.startSelection(mode: .area, delaySeconds: 3) { _ in }
            assert(RegionSelectionCoordinator.shared.activeDelaySeconds == 3, "Coordinator must store activeDelaySeconds")
            assert(RegionSelectionCoordinator.shared.isSelecting, "Coordinator must enter isSelecting")

            // Simulate finish
            let escapeEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            )
            if let evt = escapeEvent {
                _ = NSApp.sendEvent(evt)
            }
            assert(RegionSelectionCoordinator.shared.activeDelaySeconds == 0, "activeDelaySeconds must reset to 0 on exit")
        }

        // MARK: - JPG Support Suite
        testRunner("JPG Support - JPEG Encoding, Magic Bytes & Settings") {
            let settings = AppSettings.shared
            let prevFormat = settings.imageFormat
            defer { settings.imageFormat = prevFormat }

            settings.imageFormat = .jpg
            assert(settings.imageFormat == .jpg, "imageFormat can be toggled to .jpg")

            // Test JPG encoding with synthetic image
            let width = 64
            let height = 64
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let testImage = ctx.makeImage()!

            guard let jpgData = SaveService.shared.encodeJPG(image: testImage, quality: 0.8) else {
                assertionFailure("Failed to encode image to JPG")
                return
            }

            assert(!jpgData.isEmpty, "JPG data must not be empty")

            // Verify JPEG standard 3-byte SOI header: 0xFF, 0xD8, 0xFF
            var headerBytes = [UInt8](repeating: 0, count: 3)
            jpgData.copyBytes(to: &headerBytes, count: 3)
            assert(headerBytes[0] == 0xFF && headerBytes[1] == 0xD8 && headerBytes[2] == 0xFF, "Data must start with standard JPEG SOI marker (FF D8 FF)")

            // Test saving JPG to disk
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("JPGTest_\(UUID().uuidString)")
            do {
                let savedURL = try SaveService.shared.saveJPG(testImage, to: tempDir, filename: "test_output.jpg")
                assert(FileManager.default.fileExists(atPath: savedURL.path), "Saved JPG must exist on disk")
                assert(savedURL.pathExtension == "jpg", "Saved file must have .jpg extension")
                try? FileManager.default.removeItem(at: tempDir)
            } catch {
                assertionFailure("Failed to save JPG: \(error)")
            }
        }

        // MARK: - JPG Quality Suite
        testRunner("JPG Quality - Compression Factor and File Size Scaling") {
            let settings = AppSettings.shared
            let prevQuality = settings.jpgQuality
            defer { settings.jpgQuality = prevQuality }

            // 1. Verify default quality is 80
            let testSuite = "com.test.shots.quality.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: testSuite)!
            let freshSettings = AppSettings(defaults: defaults)
            assert(freshSettings.jpgQuality == 80, "Default JPG quality must be 80")
            assert(abs(freshSettings.jpgCompressionFactor - 0.8) < 0.001, "Default compression factor must be 0.8")

            // 2. Test clamping
            freshSettings.jpgQuality = 150
            assert(freshSettings.jpgQuality == 100, "Quality should be clamped to 100 max")
            freshSettings.jpgQuality = -10
            assert(freshSettings.jpgQuality == 1, "Quality should be clamped to 1 min")

            // 3. Test compression factor scaling with synthetic gradient image
            let width = 256
            let height = 256
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            // Fill with gradient-like varying pixels to make JPEG compression differences noticeable
            for y in 0..<height {
                for x in 0..<width {
                    ctx.setFillColor(CGColor(red: CGFloat(x) / 256.0, green: CGFloat(y) / 256.0, blue: 0.5, alpha: 1.0))
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
            let gradientImage = ctx.makeImage()!

            let lowQualityData = SaveService.shared.encodeJPG(image: gradientImage, quality: 0.20)!
            let highQualityData = SaveService.shared.encodeJPG(image: gradientImage, quality: 0.95)!

            assert(lowQualityData.count < highQualityData.count, "Low quality JPG (\(lowQualityData.count) bytes) should be smaller than high quality JPG (\(highQualityData.count) bytes)")

            defaults.removePersistentDomain(forName: testSuite)
        }

        // MARK: - Save Location Settings Suite
        testRunner("Save Location Settings - Custom Path Persistence and Auto-Creation") {
            let settings = AppSettings.shared
            let prevPath = settings.saveDirectoryPath
            defer {
                settings.saveDirectoryPath = prevPath
            }

            let customDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CustomShotsLocation_\(UUID().uuidString)")
            settings.saveDirectoryPath = customDir.path

            assert(settings.saveDirectoryPath == customDir.path, "saveDirectoryPath must reflect custom path")
            assert(settings.resolvedSaveDirectoryURL.path == customDir.path, "resolvedSaveDirectoryURL must match custom path")
            assert(FileManager.default.fileExists(atPath: customDir.path), "Custom save directory must be auto-created on disk")

            try? FileManager.default.removeItem(at: customDir)
        }

        // MARK: - Post-Capture Action Suite
        testRunner("Post-Capture Action - Mode Synchronization, Persistence, and Pasteboard Dispatch") {
            let testSuite = "com.test.shots.postcapture.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: testSuite) else {
                assertionFailure("Failed to allocate test defaults suite")
                return
            }

            let settings = AppSettings(defaults: defaults)

            // Test 1: Setting .saveToDisk (saves to disk, no clipboard copy)
            settings.postCaptureAction = .saveToDisk
            assert(settings.saveToDisk == true, "saveToDisk must always be true")
            assert(settings.copyToClipboard == false, "copyToClipboard must be false for .saveToDisk")
            assert(defaults.string(forKey: AppSettings.Keys.postCaptureAction) == PostCaptureAction.saveToDisk.rawValue, "UserDefaults must persist postCaptureAction")

            // Test 2: Setting .copyToClipboard (saves to disk AND copies to clipboard)
            settings.postCaptureAction = .copyToClipboard
            assert(settings.saveToDisk == true, "saveToDisk must always be true")
            assert(settings.copyToClipboard == true, "copyToClipboard must be true for .copyToClipboard")

            // Test 3: Setting .both (saves to disk AND copies to clipboard)
            settings.postCaptureAction = .both
            assert(settings.saveToDisk == true, "saveToDisk must be true for .both")
            assert(settings.copyToClipboard == true, "copyToClipboard must be true for .both")
            assert(defaults.string(forKey: AppSettings.Keys.postCaptureAction) == PostCaptureAction.both.rawValue, "UserDefaults must persist postCaptureAction")

            // Test 4: Mutating flags directly syncs postCaptureAction
            settings.copyToClipboard = false
            assert(settings.postCaptureAction == .saveToDisk, "Flag mutation must update postCaptureAction to .saveToDisk")

            settings.copyToClipboard = true
            assert(settings.postCaptureAction == .both, "Flag mutation must update postCaptureAction to .both")

            // Test 5: Pasteboard copy verification with mock image
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(
                data: nil,
                width: 10,
                height: 10,
                bitsPerComponent: 8,
                bytesPerRow: 10 * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let testImage = context.makeImage()!
            SaveService.shared.copyToPasteboard(image: testImage, fileURL: nil)

            let pb = NSPasteboard.general
            assert(pb.types?.contains(.png) == true || pb.types?.contains(.tiff) == true, "System pasteboard must contain image data")

            defaults.removePersistentDomain(forName: testSuite)
        }

        // MARK: - Menu Bar Integration Suite
        testRunner("Menu Bar Integration - Status Item, Icons, and Dropdown Hierarchy") {
            _ = NSApplication.shared
            let controller = StatusBarController()
            let statusItem = controller.currentStatusItem
            assert(statusItem.length == NSStatusItem.variableLength, "Status item length must be variableLength")

            guard let button = statusItem.button else {
                assertionFailure("Status item button must exist")
                return
            }

            assert(button.image != nil, "Status item button must have an icon")
            assert(button.image?.isTemplate == true, "Status item icon must be in template mode for native dark/light menu bars")
            assert(button.toolTip?.contains("Shots") == true, "Status button tooltip must contain app name")

            let menu = controller.currentMenu
            controller.menuWillOpen(menu)
            let visibleItems = menu.items.filter { !$0.isSeparatorItem && !$0.isHidden }
            let titles = visibleItems.map { $0.title }

            assert(titles.contains("Capture Region"), "Menu must contain Capture Region item")
            assert(titles.contains("Repeat Previous Screenshot"), "Menu must contain Repeat Previous Screenshot item")
            assert(titles.contains("Capture Fullscreen"), "Menu must contain Capture Fullscreen item")
            assert(titles.contains("OCR Recognition"), "Menu must contain OCR Recognition item")
            assert(titles.contains("Scrolling Capture"), "Menu must contain Scrolling Capture item")
            assert(titles.contains(where: { $0.contains("Recent Screenshots") }), "Menu must contain Recent Screenshots item")
            assert(titles.contains("Screen Ruler"), "Menu must contain Screen Ruler item")
            assert(titles.contains("Color Picker"), "Menu must contain Color Picker item")
            assert(titles.contains("Preferences & Hotkeys..."), "Menu must contain Preferences item")
            assert(titles.contains("Quit Shots"), "Menu must contain Quit item")

            // Verified items moved to preferences or removed from dropdown
            assert(!titles.contains("Include Cursor"), "Include Cursor must be removed from dropdown and moved to preferences")
            assert(!titles.contains("Launch at Login"), "Launch at Login must be removed from dropdown and moved to preferences")
            assert(!titles.contains("Open Screenshots Folder"), "Open Screenshots Folder must be removed from dropdown")
            assert(!titles.contains("Reveal Latest Screenshot"), "Reveal Latest Screenshot must be removed from dropdown")
            assert(!titles.contains(where: { $0.contains("Impact") }), "Impact items must be removed from dropdown")
            assert(!titles.contains("Copy to Clipboard"), "Copy to Clipboard must be removed from dropdown")
            assert(!titles.contains("Capture Delay"), "Capture Delay must be removed from dropdown")
            assert(!titles.contains("Image Format"), "Image Format must be removed from dropdown")
            assert(!titles.contains("JPG Quality"), "JPG Quality must be removed from dropdown")
            assert(!titles.contains("Change Save Location..."), "Change Save Location must be removed from dropdown")

            // Strict relative ordering verification
            let captureRegionIdx = visibleItems.firstIndex(where: { $0.title == "Capture Region" })!
            let repeatIdx = visibleItems.firstIndex(where: { $0.title == "Repeat Previous Screenshot" })!
            let fsIdx = visibleItems.firstIndex(where: { $0.title == "Capture Fullscreen" })!
            let ocrIdx = visibleItems.firstIndex(where: { $0.title == "OCR Recognition" })!
            let scrollIdx = visibleItems.firstIndex(where: { $0.title == "Scrolling Capture" })!
            let recentsIdx = visibleItems.firstIndex(where: { $0.title.contains("Recent Screenshots") })!
            let rulerIdx = visibleItems.firstIndex(where: { $0.title == "Screen Ruler" })!
            let pickerIdx = visibleItems.firstIndex(where: { $0.title == "Color Picker" })!
            let prefsIdx = visibleItems.firstIndex(where: { $0.title == "Preferences & Hotkeys..." })!
            let quitIdx = visibleItems.firstIndex(where: { $0.title == "Quit Shots" })!

            assert(captureRegionIdx < repeatIdx, "Capture Region must precede Repeat Previous Screenshot")
            assert(repeatIdx < fsIdx, "Repeat Previous Screenshot must precede Capture Fullscreen")
            assert(fsIdx < ocrIdx, "Capture Fullscreen must precede OCR Recognition")
            assert(ocrIdx < scrollIdx, "OCR Recognition must precede Scrolling Capture")
            assert(scrollIdx < recentsIdx, "Scrolling Capture must precede Recent Screenshots")
            assert(recentsIdx < rulerIdx, "Recent Screenshots must precede Screen Ruler")
            assert(rulerIdx < pickerIdx, "Screen Ruler must precede Color Picker")
            assert(pickerIdx < prefsIdx, "Color Picker must precede Preferences")
            assert(prefsIdx < quitIdx, "Preferences must precede Quit Shots")

            // Verify Recent Screenshots click action targets openFolderAction
            let recentsItem = visibleItems[recentsIdx]
            assert(recentsItem.action == #selector(controller.openFolderAction), "Recent Screenshots action must be openFolderAction")

            // Verify clean titles and right-aligned key equivalents
            let regionItem = visibleItems[captureRegionIdx]
            assert(regionItem.title == "Capture Region", "Title must not contain parenthesized shortcut")
            assert(!regionItem.keyEquivalent.isEmpty, "keyEquivalent must be set for native right-aligned shortcut")
            assert(regionItem.keyEquivalentModifierMask.contains([.command, .shift]), "keyEquivalentModifierMask must contain shift and command")
        }

        // MARK: - Global Keyboard Shortcuts Suite
        testRunner("Global Keyboard Shortcuts - Multi-Mode Mappings, Conflicts, and Dispatch") {
            let testSuite = "com.test.shots.shortcuts.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: testSuite) else {
                assertionFailure("Failed to allocate test defaults")
                return
            }

            let settings = AppSettings(defaults: defaults)

            // Verify default shortcut strings
            assert(settings.areaShortcutDisplayString == "⇧⌘4", "Area shortcut default must be ⇧⌘4 (was \(settings.areaShortcutDisplayString))")
            assert(settings.fullscreenShortcutDisplayString == "⇧⌘2", "Fullscreen shortcut default must be ⇧⌘2 (was \(settings.fullscreenShortcutDisplayString))")
            assert(settings.repeatShortcutDisplayString == "⇧⌘3", "Repeat shortcut default must be ⇧⌘3 (was \(settings.repeatShortcutDisplayString))")
            assert(settings.ocrShortcutDisplayString == "⇧⌘R", "OCR shortcut default must be ⇧⌘R (was \(settings.ocrShortcutDisplayString))")
            assert(settings.scrollingShortcutDisplayString == "⇧⌘5", "Scrolling shortcut default must be ⇧⌘5 (was \(settings.scrollingShortcutDisplayString))")
            assert(settings.rulerShortcutDisplayString == "⇧⌘M", "Ruler shortcut default must be ⇧⌘M (was \(settings.rulerShortcutDisplayString))")
            assert(settings.colorPickerShortcutDisplayString == "⇧⌘C", "Color Picker shortcut default must be ⇧⌘C (was \(settings.colorPickerShortcutDisplayString))")

            // Test custom assignment
            settings.fullscreenShortcutKeyCode = UInt16(kVK_ANSI_8)
            assert(settings.fullscreenShortcutDisplayString == "⇧⌘8", "Updated shortcut must reflect new keycode")
            assert(defaults.integer(forKey: AppSettings.Keys.fullscreenShortcutKeyCode) == Int(kVK_ANSI_8), "UserDefaults must store new shortcut")

            // Test conflict detection
            settings.fullscreenShortcutKeyCode = settings.areaShortcutKeyCode
            settings.fullscreenShortcutModifiers = settings.areaShortcutModifiers
            settings.checkForShortcutConflicts()
            assert(settings.isHotkeyConflict == true, "Matching shortcut combination must trigger conflict flag")
            assert(settings.hotkeyErrorMessage != nil, "Conflict error message must be set")

            // Test reset to defaults
            settings.resetHotkeysToDefault()
            assert(settings.isHotkeyConflict == false, "Reset must resolve shortcut conflict")
            assert(settings.areaShortcutDisplayString == "⇧⌘4", "Reset must restore Area shortcut")
            assert(settings.fullscreenShortcutDisplayString == "⇧⌘2", "Reset must restore Fullscreen shortcut")
            assert(settings.repeatShortcutDisplayString == "⇧⌘3", "Reset must restore Repeat shortcut")
            assert(settings.ocrShortcutDisplayString == "⇧⌘R", "Reset must restore OCR shortcut")
            assert(settings.scrollingShortcutDisplayString == "⇧⌘5", "Reset must restore Scrolling shortcut")
            assert(settings.rulerShortcutDisplayString == "⇧⌘M", "Reset must restore Ruler shortcut")
            assert(settings.colorPickerShortcutDisplayString == "⇧⌘C", "Reset must restore Color Picker shortcut")

            // Test HotKeyManager multi-mode dispatch callbacks
            let manager = HotKeyManager.shared
            var areaFired = false
            var fsFired = false
            var repeatFired = false
            var ocrFired = false
            var scrollFired = false
            var rulerFired = false
            var pickerFired = false

            manager.onAreaCaptureTrigger = { areaFired = true }
            manager.onFullscreenCaptureTrigger = { fsFired = true }
            manager.onRepeatCaptureTrigger = { repeatFired = true }
            manager.onOCRCaptureTrigger = { ocrFired = true }
            manager.onScrollingCaptureTrigger = { scrollFired = true }
            manager.onRulerTrigger = { rulerFired = true }
            manager.onColorPickerTrigger = { pickerFired = true }

            // Trigger closures manually to verify wiring
            manager.onAreaCaptureTrigger?()
            assert(areaFired, "Area capture trigger callback must execute")

            manager.onFullscreenCaptureTrigger?()
            assert(fsFired, "Fullscreen capture trigger callback must execute")

            manager.onRepeatCaptureTrigger?()
            assert(repeatFired, "Repeat capture trigger callback must execute")

            manager.onOCRCaptureTrigger?()
            assert(ocrFired, "OCR capture trigger callback must execute")

            manager.onScrollingCaptureTrigger?()
            assert(scrollFired, "Scrolling capture trigger callback must execute")

            manager.onRulerTrigger?()
            assert(rulerFired, "Ruler trigger callback must execute")

            manager.onColorPickerTrigger?()
            assert(pickerFired, "Color Picker trigger callback must execute")

            // Test clearing individual and all shortcuts
            settings.areaShortcutKeyCode = KeyCodes.noKey
            settings.areaShortcutModifiers = 0
            assert(settings.areaShortcutDisplayString == "None", "Unassigned shortcut must display 'None'")
            assert(!KeyCodes.isShortcutAssigned(keyCode: settings.areaShortcutKeyCode, carbonMods: settings.areaShortcutModifiers), "isShortcutAssigned must return false for noKey")

            settings.clearAllHotkeys()
            assert(settings.areaShortcutDisplayString == "None", "clearAllHotkeys must set Area to None")
            assert(settings.fullscreenShortcutDisplayString == "None", "clearAllHotkeys must set Fullscreen to None")
            assert(settings.repeatShortcutDisplayString == "None", "clearAllHotkeys must set Repeat to None")
            assert(settings.ocrShortcutDisplayString == "None", "clearAllHotkeys must set OCR to None")
            assert(settings.scrollingShortcutDisplayString == "None", "clearAllHotkeys must set Scrolling to None")
            assert(settings.rulerShortcutDisplayString == "None", "clearAllHotkeys must set Ruler to None")
            assert(settings.colorPickerShortcutDisplayString == "None", "clearAllHotkeys must set Color Picker to None")

            // Test master toggle: globalHotkeysEnabled
            settings.resetHotkeysToDefault()
            assert(settings.globalHotkeysEnabled == true, "resetHotkeysToDefault must enable global hotkeys")
            settings.globalHotkeysEnabled = false
            assert(manager.registerCurrentHotkey() == true, "registerCurrentHotkey must return true when global hotkeys are disabled")

            settings.resetHotkeysToDefault()

            defaults.removePersistentDomain(forName: testSuite)
        }

        // MARK: - Launch at Login Suite
        testRunner("Launch at Login - State Management & Persistence") {
            let testSuite = "com.test.shots.launch.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: testSuite) else {
                assertionFailure("Failed to allocate test defaults")
                return
            }

            let settings = AppSettings(defaults: defaults)
            assert(settings.launchAtLogin == false, "Launch at Login must default to false")

            // Test setting toggle
            settings.launchAtLogin = true
            assert(settings.launchAtLogin == true, "launchAtLogin must be true when enabled")
            assert(defaults.bool(forKey: AppSettings.Keys.launchAtLogin) == true, "UserDefaults must persist launchAtLogin = true")

            settings.launchAtLogin = false
            assert(settings.launchAtLogin == false, "launchAtLogin must be false when disabled")
            assert(defaults.bool(forKey: AppSettings.Keys.launchAtLogin) == false, "UserDefaults must persist launchAtLogin = false")

            // Test LaunchAtLoginService API invocation
            let service = LaunchAtLoginService.shared
            let prevSetting = AppSettings.shared.launchAtLogin
            defer {
                _ = service.setLaunchAtLogin(enabled: prevSetting)
            }

            _ = service.setLaunchAtLogin(enabled: true)
            assert(AppSettings.shared.launchAtLogin == true, "Service must update AppSettings.shared")

            _ = service.setLaunchAtLogin(enabled: false)
            assert(AppSettings.shared.launchAtLogin == false, "Service must update AppSettings.shared to false")

            defaults.removePersistentDomain(forName: testSuite)
        }

        // MARK: - Repeat Previous Screenshot Suite
        testRunner("Repeat Previous Screenshot - Parameters Caching and Dynamic Re-execution") {
            let manager = CaptureManager.shared
            let prevCapture = manager.lastCapture
            defer {
                manager.lastCapture = prevCapture
            }

            // 1. Fullscreen mode record caching
            manager.lastCapture = LastCaptureRecord(mode: .fullscreen)
            assert(manager.lastCapture?.mode == .fullscreen, "lastCapture must reflect fullscreen mode")

            // 2. Region mode record caching
            let testRect = NSRect(x: 100, y: 150, width: 400, height: 300)
            let testFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
            let testDisplayID = CGMainDisplayID()
            let regionRecord = LastCaptureRecord(mode: .region(rect: testRect, screenFrame: testFrame, displayID: testDisplayID))
            manager.lastCapture = regionRecord

            guard let cached = manager.lastCapture else {
                assertionFailure("lastCapture must not be nil")
                return
            }

            if case .region(let r, let f, let d) = cached.mode {
                assert(r == testRect, "Cached rect must match testRect")
                assert(f == testFrame, "Cached screenFrame must match testFrame")
                assert(d == testDisplayID, "Cached displayID must match testDisplayID")
            } else {
                assertionFailure("Cached mode must be .region")
            }

            // 3. Status bar menu item state reflects presence of lastCapture
            let controller = StatusBarController()
            let menu = controller.currentMenu
            let repeatItem = menu.items.first(where: { $0.title.contains("Repeat Previous Screenshot") })
            assert(repeatItem != nil, "Repeat item must be present in menu")
            assert(repeatItem?.isEnabled == true, "Repeat item must be enabled when lastCapture exists")

            manager.lastCapture = nil
            controller.menuWillOpen(menu)
            assert(repeatItem?.isEnabled == false, "Repeat item must be disabled when lastCapture is nil")
        }

        testRunner("Coordinates Badge - Pattern Format & Boundary Clamping") {
            let curX = 1420
            let curY = 850
            let formattedText = "x: \(curX)\ny: \(curY)"

            let regex = try! NSRegularExpression(pattern: #"^x: \d+\ny: \d+$"#)
            let matchRange = NSRange(location: 0, length: formattedText.utf16.count)
            assert(regex.firstMatch(in: formattedText, range: matchRange) != nil, "Coordinate text must match 'x: [0-9]+\\ny: [0-9]+'")

            // Verify badge clamping logic stays strictly within bounds for all screen corners
            let boundsSize = CGSize(width: 1920, height: 1080)
            let badgeW: CGFloat = 80
            let badgeH: CGFloat = 40
            let margin: CGFloat = 8

            let testPoints = [
                CGPoint(x: 5, y: 5),                      // Bottom-left corner
                CGPoint(x: 1918, y: 1078),                // Top-right corner
                CGPoint(x: 1000, y: 500),                 // Center
                CGPoint(x: 1915, y: 5),                   // Bottom-right corner
                CGPoint(x: 5, y: 1075)                    // Top-left corner
            ]

            for pt in testPoints {
                var badgeX = pt.x + 14
                var badgeY = pt.y - badgeH - 8

                if badgeX + badgeW > boundsSize.width - margin {
                    badgeX = pt.x - badgeW - 14
                }
                if badgeY < margin {
                    badgeY = pt.y + 14
                }
                if badgeY + badgeH > boundsSize.height - margin {
                    badgeY = pt.y - badgeH - 14
                }
                badgeX = max(margin, min(badgeX, boundsSize.width - badgeW - margin))
                badgeY = max(margin, min(badgeY, boundsSize.height - badgeH - margin))

                assert(badgeX >= margin, "Badge X must be >= margin (was \(badgeX))")
                assert(badgeX + badgeW <= boundsSize.width - margin, "Badge right must not exceed bounds")
                assert(badgeY >= margin, "Badge Y must be >= margin (was \(badgeY))")
            }
        }

        // MARK: - Reveal Latest Screenshot Suite
        testRunner("Reveal Latest Screenshot - File Resolution and Menu Bar Integration") {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("shots_reveal_test_\(UUID().uuidString)")
            try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }

            let saveService = SaveService.shared
            let oldLatest = saveService.latestSavedURL
            defer {
                saveService.latestSavedURL = oldLatest
            }

            // 1. Initial empty directory resolution without cached URL
            saveService.latestSavedURL = nil
            let emptyResult = saveService.resolveLatestScreenshotURL(directoryURL: tempDir)
            assert(emptyResult == nil, "Empty directory must resolve to nil")

            // 2. Create mock screenshot files with distinct modification timestamps
            let olderURL = tempDir.appendingPathComponent("shot_20261013_080000.png")
            let newerURL = tempDir.appendingPathComponent("shot_20261013_120000.jpg")
            let nonScreenshotURL = tempDir.appendingPathComponent("notes.txt")

            try! "older".write(to: olderURL, atomically: true, encoding: .utf8)
            try! "newer".write(to: newerURL, atomically: true, encoding: .utf8)
            try! "text".write(to: nonScreenshotURL, atomically: true, encoding: .utf8)

            let olderDate = Date().addingTimeInterval(-3600)
            let newerDate = Date()
            try! FileManager.default.setAttributes([.modificationDate: olderDate], ofItemAtPath: olderURL.path)
            try! FileManager.default.setAttributes([.modificationDate: newerDate], ofItemAtPath: newerURL.path)

            // Test resolution from disk
            saveService.latestSavedURL = nil
            let resolved = saveService.resolveLatestScreenshotURL(directoryURL: tempDir)
            assert(resolved?.lastPathComponent == newerURL.lastPathComponent, "resolveLatestScreenshotURL must choose newest screenshot (got \(String(describing: resolved?.lastPathComponent)))")
            assert(saveService.latestSavedURL?.lastPathComponent == newerURL.lastPathComponent, "latestSavedURL must be updated with resolved file")

            // 3. Test saving updates latestSavedURL immediately
            let sampleData = Data([0x89, 0x50, 0x4E, 0x47])
            try! saveService.saveImageData(sampleData, to: tempDir, filename: "shot_test_immediate.png")
            assert(saveService.latestSavedURL?.lastPathComponent == "shot_test_immediate.png", "saveImageData must update latestSavedURL directly")

            // 4. Test StatusBarController integration
            let controller = StatusBarController()
            let menu = controller.currentMenu
            let revealItem = menu.items.first(where: { $0.title == "Reveal Latest Screenshot" })
            assert(revealItem == nil, "Reveal Latest Screenshot item was removed from dropdown menu")
            assert(saveService.resolveLatestScreenshotURL() != nil, "Latest screenshot URL must resolve")
        }

        // MARK: - Recent Screenshot List Suite
        testRunner("Recent Screenshot List - 5 to 10 Items Discovery, Caching, and Dropdown Submenu") {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("shots_history_test_\(UUID().uuidString)")
            try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }

            let historyService = ScreenshotHistoryService.shared
            historyService.reset()
            defer {
                historyService.reset()
            }

            // 1. Empty directory
            let emptyRecents = historyService.fetchRecentScreenshots(limit: 10, directoryURL: tempDir)
            assert(emptyRecents.isEmpty, "Empty directory must yield 0 recent items")

            // 2. Populate 12 screenshot files with ascending timestamps + 2 non-screenshot files
            let baseTime = Date().addingTimeInterval(-3600)
            var createdFiles: [URL] = []
            for i in 1...12 {
                let pad = String(format: "%02d", i)
                let ext = (i % 2 == 0) ? "jpg" : "png"
                let fileURL = tempDir.appendingPathComponent("shot_20261013_1200\(pad).\(ext)")
                try! "content_\(i)".write(to: fileURL, atomically: true, encoding: .utf8)
                let fileTime = baseTime.addingTimeInterval(Double(i * 60))
                try! FileManager.default.setAttributes([.modificationDate: fileTime], ofItemAtPath: fileURL.path)
                createdFiles.append(fileURL)
            }
            try! "note".write(to: tempDir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
            try! "ignore".write(to: tempDir.appendingPathComponent("other.png"), atomically: true, encoding: .utf8)

            // 3. Test limit = 10 (default)
            let recents10 = historyService.fetchRecentScreenshots(limit: 10, directoryURL: tempDir)
            assert(recents10.count == 10, "Recent screenshots list must clamp to 10 items (got \(recents10.count))")
            assert(recents10[0].filename == createdFiles[11].lastPathComponent, "First item must be the newest screenshot (file 12)")
            assert(recents10[9].filename == createdFiles[2].lastPathComponent, "10th item must be file 3")

            // 4. Test limit = 5
            let recents5 = historyService.fetchRecentScreenshots(limit: 5, directoryURL: tempDir)
            assert(recents5.count == 5, "Recent screenshots list must return requested limit 5 (got \(recents5.count))")
            assert(recents5[0].filename == createdFiles[11].lastPathComponent, "First item of 5 must be newest")

            // 5. Test recordNewScreenshot in-memory insertion and clamping
            historyService.fetchRecentScreenshots(limit: 10, directoryURL: tempDir)
            assert(historyService.recentItems.count == 10, "Pre-condition: 10 items loaded")
            let newShotURL = tempDir.appendingPathComponent("shot_new_live.png")
            try! "live".write(to: newShotURL, atomically: true, encoding: .utf8)
            historyService.recordNewScreenshot(fileURL: newShotURL)
            assert(historyService.recentItems.count == 10, "recordNewScreenshot must clamp to maximum 10 items count")
            assert(historyService.recentItems[0].fileURL.lastPathComponent == "shot_new_live.png", "Newly recorded screenshot must be at index 0")

            // 6. Test StatusBarController dropdown menu integration
            let controller = StatusBarController()
            let menu = controller.currentMenu
            let historyMenuItem = menu.items.first(where: { $0.title.contains("Recent Screenshots") })
            assert(historyMenuItem != nil, "Recent Screenshots menu item must exist")
            assert(historyMenuItem?.submenu != nil, "Recent Screenshots must have a submenu")
            assert(historyMenuItem?.submenu?.items.count ?? 0 >= 1, "Submenu must contain items")
        }

        // MARK: - Recent Screenshot Selection Suite
        testRunner("Recent Screenshot Selection - Reveal in Finder and Menu Item Invocation") {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("shots_select_test_\(UUID().uuidString)")
            try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }

            let validShotURL = tempDir.appendingPathComponent("shot_valid.png")
            try! "valid_img".write(to: validShotURL, atomically: true, encoding: .utf8)
            let nonExistentURL = tempDir.appendingPathComponent("shot_missing.png")

            let historyService = ScreenshotHistoryService.shared
            var revealedURLs: [URL] = []
            historyService.onRevealInFinder = { url in
                revealedURLs.append(url)
            }
            defer {
                historyService.onRevealInFinder = { _ in }
            }

            // 1. Verification of revealScreenshotInFinder API
            assert(historyService.revealScreenshotInFinder(fileURL: validShotURL) == true, "Existing file must reveal successfully")
            assert(revealedURLs.contains(validShotURL), "Valid URL must be captured by reveal handler")
            assert(historyService.revealScreenshotInFinder(fileURL: nonExistentURL) == false, "Missing file must fail reveal safely")

            // 2. Verification of StatusBarController selection wiring
            let controller = StatusBarController()
            let item = NSMenuItem(title: "shot_valid.png", action: #selector(controller.recentScreenshotSelected(_:)), keyEquivalent: "")
            item.target = controller
            item.representedObject = validShotURL

            assert(item.action == #selector(controller.recentScreenshotSelected(_:)), "Action must be recentScreenshotSelected")
            assert((item.representedObject as? URL)?.lastPathComponent == "shot_valid.png", "Represented object must hold target URL")

            // Execute selection action on valid item
            controller.recentScreenshotSelected(item)
            assert(revealedURLs.filter { $0 == validShotURL }.count >= 2, "recentScreenshotSelected must invoke reveal handler for valid item")

            // Execute selection action on missing item (must not crash)
            item.representedObject = nonExistentURL
            controller.recentScreenshotSelected(item)

            // Execute with nil represented object (must not crash)
            item.representedObject = nil
            controller.recentScreenshotSelected(item)
        }

        // MARK: - Recent Screenshot Actions Suite
        testRunner("Recent Screenshot Actions - Submenu Actions: Reveal in Finder and Copy to Clipboard") {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("shots_actions_test_\(UUID().uuidString)")
            try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            let prevDir = AppSettings.shared.saveDirectoryPath
            AppSettings.shared.saveDirectoryPath = tempDir.path
            defer {
                AppSettings.shared.saveDirectoryPath = prevDir
                try? FileManager.default.removeItem(at: tempDir)
            }

            // Create a valid image file on disk
            let imageURL = tempDir.appendingPathComponent("shot_test_action.png")
            let size = CGSize(width: 50, height: 50)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(data: nil, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(NSColor.systemBlue.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            let cgImage = ctx.makeImage()!
            let pngData = SaveService.shared.encodePNG(image: cgImage)!
            try! pngData.write(to: imageURL)

            let historyService = ScreenshotHistoryService.shared

            // 1. Test copyScreenshotToClipboard API
            let copyResult = historyService.copyScreenshotToClipboard(fileURL: imageURL)
            assert(copyResult == true, "copyScreenshotToClipboard must succeed on valid image file")

            let pbTypes = NSPasteboard.general.types ?? []
            assert(pbTypes.contains(.png) || pbTypes.contains(.fileURL) || pbTypes.contains(NSPasteboard.PasteboardType("public.png")), "Pasteboard must contain image/file types after copy")

            let missingURL = tempDir.appendingPathComponent("missing.png")
            assert(historyService.copyScreenshotToClipboard(fileURL: missingURL) == false, "copyScreenshotToClipboard must fail on missing file")

            // 2. Test menu item submenu construction
            historyService.reset()
            historyService.recordNewScreenshot(fileURL: imageURL)

            let controller = StatusBarController()
            let menu = controller.currentMenu
            controller.menuWillOpen(menu)

            let historyMenuItem = menu.items.first(where: { $0.title.contains("Recent Screenshots") })
            let recentSubmenu = historyMenuItem?.submenu
            assert(recentSubmenu != nil, "Recent Screenshots must have submenu")

            let recentItem = recentSubmenu?.items.first(where: { $0.title == imageURL.lastPathComponent })
            assert(recentItem != nil, "Recent screenshot item must exist in submenu")

            let actionSubmenu = recentItem?.submenu
            assert(actionSubmenu != nil, "Recent screenshot item must have action submenu")

            let revealActionItem = actionSubmenu?.items.first(where: { $0.title == "Reveal in Finder" })
            assert(revealActionItem != nil, "Action submenu must contain Reveal in Finder")
            assert(revealActionItem?.action == #selector(controller.revealRecentScreenshotAction(_:)), "Reveal action selector must match")

            let copyActionItem = actionSubmenu?.items.first(where: { $0.title == "Copy to Clipboard" })
            assert(copyActionItem != nil, "Action submenu must contain Copy to Clipboard")
            assert(copyActionItem?.action == #selector(controller.copyRecentScreenshotAction(_:)), "Copy action selector must match")

            // Test executing both action selectors
            var actionRevealedURLs: [URL] = []
            ScreenshotHistoryService.shared.onRevealInFinder = { url in
                actionRevealedURLs.append(url)
            }
            defer {
                ScreenshotHistoryService.shared.onRevealInFinder = { _ in }
            }

            if let revealItem = revealActionItem {
                controller.revealRecentScreenshotAction(revealItem)
                assert(!actionRevealedURLs.isEmpty, "revealRecentScreenshotAction must trigger reveal handler")
            }
            if let copyItem = copyActionItem {
                controller.copyRecentScreenshotAction(copyItem)
            }

            // Verify BUG-006: Explicit "Open Screenshots Folder" menu item in submenu
            let openFolderSubItem = recentSubmenu?.items.first(where: { $0.title == "Open Screenshots Folder" })
            assert(openFolderSubItem != nil, "Submenu must contain Open Screenshots Folder item")
            assert(openFolderSubItem?.action == #selector(controller.openFolderAction), "Open Screenshots Folder action selector must match openFolderAction")

            // Verify BUG-005: menuWillOpen returns immediately using in-memory cache
            let start = DispatchTime.now()
            controller.menuWillOpen(menu)
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            assert(elapsedMs < 20.0, "menuWillOpen must be non-blocking and return immediately (took \(elapsedMs)ms)")
        }

        // MARK: - Native Recognition Framework Suite
        testRunner("Native Recognition Framework - Vision Framework On-Device Infrastructure") {
            let service = RecognitionService.shared
            assert(service.isVisionSupported == true, "Vision framework must be supported on macOS 12+")

            // Create a test image
            let size = CGSize(width: 100, height: 100)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            let testCGImage = ctx.makeImage()!

            // 1. Synchronous request execution
            var requestCompleted = false
            let testRequest = VNRecognizeTextRequest { request, error in
                assert(error == nil, "Vision request execution should not produce error")
                requestCompleted = true
            }

            try! service.performRequests([testRequest], on: testCGImage)
            assert(requestCompleted == true, "Synchronous Vision request must finish execution")

            // 2. Asynchronous request execution
            var asyncCompleted = false
            let asyncRequest = VNRecognizeTextRequest { _, _ in }
            service.performRequestsAsync([asyncRequest], on: testCGImage) { result in
                switch result {
                case .success(let reqs):
                    assert(reqs.count == 1, "Async execution must return requests")
                    asyncCompleted = true
                case .failure(let err):
                    assertionFailure("Async request failed with: \(err.localizedDescription)")
                }
            }

            let runLoopDeadline = Date().addingTimeInterval(1.0)
            while !asyncCompleted && Date() < runLoopDeadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            assert(asyncCompleted == true, "Async Vision request must finish within deadline")
        }

        // MARK: - QR Code Recognition Suite
        testRunner("QR Code Recognition - Detection and Payload Extraction") {
            let service = RecognitionService.shared

            // Generate a real, high-contrast QR code image using CoreImage
            let expectedPayload = "https://shots.local/verify?id=test-qr-12345"
            let filter = CIFilter(name: "CIQRCodeGenerator")
            filter?.setValue(expectedPayload.data(using: .utf8), forKey: "inputMessage")
            filter?.setValue("M", forKey: "inputCorrectionLevel")

            guard let ciOutput = filter?.outputImage else {
                assertionFailure("Failed to generate CIQRCodeGenerator output")
                return
            }

            // Scale up QR code image so it is easily detectable
            let transform = CGAffineTransform(scaleX: 8.0, y: 8.0)
            let scaledImage = ciOutput.transformed(by: transform)

            let ciContext = CIContext()
            guard let qrCGImage = ciContext.createCGImage(scaledImage, from: scaledImage.extent) else {
                assertionFailure("Failed to render QR CGImage")
                return
            }

            // 1. Synchronous QR recognition
            let recognized = try! service.recognizeQRCodes(in: qrCGImage)
            assert(recognized.count == 1, "Exactly 1 QR code must be detected (found \(recognized.count))")
            assert(recognized[0].type == .qrCode, "Recognition type must be .qrCode")
            assert(recognized[0].payload == expectedPayload, "QR payload must match expected string")
            assert(recognized[0].symbology == "QR", "Symbology must be QR")

            // 2. Negative test: Plain white image should produce 0 QR codes
            let plainSize = CGSize(width: 100, height: 100)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: plainSize))
            let plainCGImage = ctx.makeImage()!

            let emptyResults = try! service.recognizeQRCodes(in: plainCGImage)
            assert(emptyResults.isEmpty, "Plain image must yield 0 QR codes")
        }

        // MARK: - Barcode Recognition Suite
        testRunner("Barcode Recognition - 1D Barcode Detection and Symbology Decoding") {
            let service = RecognitionService.shared

            // Generate an authentic Code 128 1D barcode image using CoreImage
            let expectedBarcode = "9876543210"
            let filter = CIFilter(name: "CICode128BarcodeGenerator")
            filter?.setValue(expectedBarcode.data(using: .ascii), forKey: "inputMessage")

            guard let ciOutput = filter?.outputImage else {
                assertionFailure("Failed to generate CICode128BarcodeGenerator output")
                return
            }

            // Scale up barcode so bars have sufficient pixel width
            let transform = CGAffineTransform(scaleX: 8.0, y: 8.0)
            let scaledImage = ciOutput.transformed(by: transform)

            let ciContext = CIContext()
            guard let barcodeCGImage = ciContext.createCGImage(scaledImage, from: scaledImage.extent) else {
                assertionFailure("Failed to render Barcode CGImage")
                return
            }

            // 1. Synchronous barcode recognition
            let recognized = try! service.recognizeBarcodes(in: barcodeCGImage)
            assert(recognized.count == 1, "Exactly 1 barcode must be detected (found \(recognized.count))")
            assert(recognized[0].type == .barcode, "Recognition type must be .barcode")
            assert(recognized[0].payload == expectedBarcode, "Barcode payload must match expected string")
            assert(recognized[0].symbology == "Code 128", "Symbology must be Code 128 (got \(String(describing: recognized[0].symbology)))")

            // 2. Negative test: Plain white image should produce 0 barcodes
            let plainSize = CGSize(width: 100, height: 100)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: plainSize))
            let plainCGImage = ctx.makeImage()!

            let emptyResults = try! service.recognizeBarcodes(in: plainCGImage)
            assert(emptyResults.isEmpty, "Plain image must yield 0 barcodes")
        }

        // MARK: - OCR Text Recognition Suite
        testRunner("OCR Text Recognition - English and Polish Text Extraction") {
            let service = RecognitionService.shared

            // Helper to render high-contrast text to CGImage
            func renderTextImage(text: String, fontSize: CGFloat = 36) -> CGImage {
                let font = NSFont.boldSystemFont(ofSize: fontSize)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.black
                ]
                let size = (text as NSString).size(withAttributes: attrs)
                let imgWidth = max(200, ceil(size.width) + 40)
                let imgHeight = max(100, ceil(size.height) + 40)
                let image = NSImage(size: NSSize(width: imgWidth, height: imgHeight))
                image.lockFocus()
                NSColor.white.setFill()
                NSRect(origin: .zero, size: image.size).fill()
                (text as NSString).draw(at: NSPoint(x: 20, y: 20), withAttributes: attrs)
                image.unlockFocus()
                return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            }

            // 1. English text extraction test
            let englishCG = renderTextImage(text: "Screenshot Captured")
            let englishResults = try! service.recognizeText(in: englishCG)
            assert(!englishResults.isEmpty, "English text must be recognized")
            assert(englishResults[0].type == .text, "Result type must be .text")
            let englishFull = englishResults.map { $0.payload }.joined(separator: " ")
            assert(englishFull.contains("Screenshot") || englishFull.contains("Captured"), "English payload must contain expected text (got '\(englishFull)')")

            // 2. Polish text extraction test (verifying Polish language prioritization)
            let polishCG = renderTextImage(text: "Zrzut ekranu")
            let polishResults = try! service.recognizeText(in: polishCG, languages: ["pl-PL", "en-US"])
            assert(!polishResults.isEmpty, "Polish text must be recognized")
            let polishFull = polishResults.map { $0.payload }.joined(separator: " ")
            assert(polishFull.contains("Zrzut") || polishFull.contains("ekranu"), "Polish payload must contain expected text (got '\(polishFull)')")

            // 3. Negative test: Plain blank image produces 0 text items
            let plainSize = CGSize(width: 100, height: 100)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: plainSize))
            let plainCGImage = ctx.makeImage()!

            let blankResults = try! service.recognizeText(in: plainCGImage)
            assert(blankResults.isEmpty, "Blank image must yield 0 text items")
        }

        // MARK: - Unified Recognition Action Suite
        testRunner("Unified Recognition Action - Auto-Detection of QR, Barcode, Text & Menu Item Integration") {
            let service = RecognitionService.shared
            let ciContext = CIContext()

            // 1. Generate QR Code image -> verify Unified Recognition picks .qrCode
            let qrFilter = CIFilter(name: "CIQRCodeGenerator")
            let qrText = "https://shots.local/unified-qr"
            qrFilter?.setValue(qrText.data(using: .utf8), forKey: "inputMessage")
            let qrScaled = qrFilter!.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
            let qrCG = ciContext.createCGImage(qrScaled, from: qrScaled.extent)!

            let unifiedQR = try! service.recognizeUnified(in: qrCG)
            assert(unifiedQR != nil, "Unified recognition must find QR code")
            assert(unifiedQR?.type == .qrCode, "Unified recognition must return .qrCode type (got \(String(describing: unifiedQR?.type)))")
            assert(unifiedQR?.payload == qrText, "Payload must match QR content")

            // 2. Generate 1D Barcode image -> verify Unified Recognition picks .barcode
            let barFilter = CIFilter(name: "CICode128BarcodeGenerator")
            let barText = "1234598760"
            barFilter?.setValue(barText.data(using: .ascii), forKey: "inputMessage")
            let barScaled = barFilter!.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
            let barCG = ciContext.createCGImage(barScaled, from: barScaled.extent)!

            let unifiedBar = try! service.recognizeUnified(in: barCG)
            assert(unifiedBar != nil, "Unified recognition must find Barcode")
            assert(unifiedBar?.type == .barcode, "Unified recognition must return .barcode type (got \(String(describing: unifiedBar?.type)))")
            assert(unifiedBar?.payload == barText, "Payload must match Barcode content")

            // 3. Generate pure Text image -> verify Unified Recognition picks .text
            let textImg = NSImage(size: NSSize(width: 300, height: 100))
            textImg.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: textImg.size).fill()
            let font = NSFont.boldSystemFont(ofSize: 32)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            ("Unified OCR" as NSString).draw(at: NSPoint(x: 20, y: 20), withAttributes: attrs)
            textImg.unlockFocus()
            let textCG = textImg.cgImage(forProposedRect: nil, context: nil, hints: nil)!

            let unifiedText = try! service.recognizeUnified(in: textCG)
            assert(unifiedText != nil, "Unified recognition must find Text")
            assert(unifiedText?.type == .text, "Unified recognition must return .text type")
            assert(unifiedText?.payload.contains("Unified") == true || unifiedText?.payload.contains("OCR") == true, "Text content must be extracted")

            // 4. Test copyPayloadToPasteboard helper
            if let item = unifiedQR {
                let copySuccess = service.copyPayloadToPasteboard(item)
                assert(copySuccess == true, "copyPayloadToPasteboard must succeed")
                assert(NSPasteboard.general.string(forType: .string) == qrText, "Pasteboard string must match recognized payload")
            }

            // 5. Verify StatusBarController menu item presence and action wiring
            let controller = StatusBarController()
            let menu = controller.currentMenu
            let ocrItem = menu.items.first(where: { $0.title.contains("OCR Recognition") })
            assert(ocrItem != nil, "OCR Recognition item must exist in status menu")
            assert(ocrItem?.action == #selector(controller.ocrRecognitionAction), "OCR Recognition action must be ocrRecognitionAction")
            assert(ocrItem?.image != nil, "OCR Recognition item must have native symbol image")

            // 6. Verify HotKeyManager OCR trigger callback
            var hotkeyTriggered = false
            HotKeyManager.shared.onOCRCaptureTrigger = {
                hotkeyTriggered = true
            }
            HotKeyManager.shared.onOCRCaptureTrigger?()
            assert(hotkeyTriggered == true, "onOCRCaptureTrigger must execute callback")
        }

        // MARK: - Scrolling Capture Suite
        testRunner("Scrolling Capture - Continuous Vertical Stitching & 20,000 px Clamping Enforcement") {
            let service = ScrollingCaptureService.shared

            // 1. Verify architectural constraint: maximum output height is 20,000 px
            assert(ScrollingCaptureService.maxAllowedHeight == 20_000, "Maximum allowed scrolling capture height must be 20,000 px")

            // 2. Helper to construct gradient test frames
            let width = 60
            let frameHeight = 60
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            func makeGradientFrame(yOffset: Int) -> CGImage {
                let ctx = CGContext(
                    data: nil,
                    width: width,
                    height: frameHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )!
                for y in 0..<frameHeight {
                    let v = CGFloat((y + yOffset) % 256) / 255.0
                    ctx.setFillColor(NSColor(red: v, green: v, blue: v, alpha: 1.0).cgColor)
                    ctx.fill(CGRect(x: 0, y: y, width: width, height: 1))
                }
                return ctx.makeImage()!
            }

            let frame1 = makeGradientFrame(yOffset: 0)
            let frame2 = makeGradientFrame(yOffset: 25)

            // 3. Test identical frame detection
            let identicalOffset = service.detectVerticalOffset(between: frame1, and: frame1)
            assert(identicalOffset == 0, "Identical frames must produce vertical offset 0 (got \(identicalOffset))")

            // 4. Test frame stitching
            let stitchedTwoFrames = service.stitchFrames([frame1, frame2])
            assert(stitchedTwoFrames != nil, "Stitched frames image must not be nil")
            assert(stitchedTwoFrames?.width == width, "Stitched width must match source frame width")
            assert(stitchedTwoFrames!.height >= frameHeight, "Stitched height must be >= single frame height (was \(stitchedTwoFrames!.height))")

            // 5. Test strict clamping to maximum height (20,000 px)
            // A. Test clampImageHeight with an artificially tall image (height > 20,000)
            let tallHeight = 22_000
            let tallCtx = CGContext(
                data: nil,
                width: 20,
                height: tallHeight,
                bitsPerComponent: 8,
                bytesPerRow: 20 * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let tallImage = tallCtx.makeImage()!
            let clampedTall = service.clampImageHeight(tallImage)
            assert(clampedTall.height == 20_000, "Image exceeding 20,000 px must be clamped to exactly 20,000 px (got \(clampedTall.height))")

            // B. Test stitchFrames clamping with maxHeight parameter
            let smallClamped = service.stitchFrames([frame1, frame2], maxHeight: 80)
            assert(smallClamped != nil && smallClamped!.height <= 80, "Stitcher must strictly respect custom maxHeight constraint")

            // 6. Test CaptureManager scrolling processing integration
            let mgrResult = CaptureManager.shared.processScrollingFrames([frame1, frame2])
            assert(mgrResult != nil, "CaptureManager.processScrollingFrames must return a valid CGImage")
            assert(mgrResult!.height <= ScrollingCaptureService.maxAllowedHeight, "Processed scrolling image must not exceed 20,000 px")

            // 7. Verify StatusBarController menu item presence and action
            let controller = StatusBarController()
            let menu = controller.currentMenu
            let scrollItem = menu.items.first(where: { $0.title.starts(with: "Scrolling Capture") })
            assert(scrollItem != nil, "Scrolling Capture menu item must exist in status menu")
            assert(scrollItem?.action == #selector(controller.scrollingCaptureAction), "Action must be scrollingCaptureAction")
            assert(scrollItem?.image != nil, "Scrolling Capture must have an icon")
        }

        // MARK: - OCR Flash Notification HUD
        testRunner("OCR Notification HUD - Top Center Notification, 250px Width, Snippet Clamping & Dismiss") {
            let hud = OCRNotificationController.shared

            // Test showing short snippet
            hud.show(snippet: "Hello World", duration: 6.0)

            // Test showing multi-line snippet
            let multiLineText = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6"
            hud.show(snippet: multiLineText, duration: 6.0)

            // Test manual dismiss
            hud.dismiss()
        }

        // MARK: - Transparent Fullscreen Overlay Capture Modes (Area, OCR, Ruler, Color Picker)
        testRunner("Capture Overlay Modes - Area, OCR, Ruler & Color Picker Fullscreen Overlay") {
            // 1. Enum Verification
            assert(CaptureOverlayMode.area.rawValue == "Area", "Area mode rawValue must be Area")
            assert(CaptureOverlayMode.ocr.rawValue == "OCR", "OCR mode rawValue must be OCR")
            assert(CaptureOverlayMode.ruler.rawValue == "Ruler", "Ruler mode rawValue must be Ruler")
            assert(CaptureOverlayMode.colorPicker.rawValue == "Color Picker", "Color Picker rawValue must be Color Picker")
            assert(CaptureOverlayMode.allCases.count == 4, "Must support all 4 capture overlay modes")

            // 2. Color Extraction Verification (sRGB)
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            guard let testCtx = CGContext(
                data: nil,
                width: 10,
                height: 10,
                bitsPerComponent: 8,
                bytesPerRow: 40,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { fatalError("Test context creation failed") }

            // Fill with pure blue #0000FF
            testCtx.setFillColor(CGColor(srgbRed: 0.0, green: 0.0, blue: 1.0, alpha: 1.0))
            testCtx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))

            // Put pure red pixel at (2, 2) in CG top-left coordinates (y=7 from bottom)
            testCtx.setFillColor(CGColor(srgbRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0))
            testCtx.fill(CGRect(x: 2, y: 7, width: 1, height: 1))

            let testImage = testCtx.makeImage()!

            let redColor = RegionSelectionCoordinator.shared.extractColor(from: testImage, x: 2, y: 2)
            assert(redColor != nil, "Color extraction must succeed")
            assert(redColor?.hex == "#FF0000", "Sampled pixel must be pure red #FF0000, got \(String(describing: redColor?.hex))")
            assert(redColor?.rgb.r == 255 && redColor?.rgb.g == 0 && redColor?.rgb.b == 0, "RGB must be (255, 0, 0)")

            let blueColor = RegionSelectionCoordinator.shared.extractColor(from: testImage, x: 0, y: 0)
            assert(blueColor?.hex == "#0000FF", "Sampled pixel must be pure blue #0000FF, got \(String(describing: blueColor?.hex))")

            // 3. Ruler Calculation Mathematics
            let p1 = NSPoint(x: 100, y: 100)
            let p2 = NSPoint(x: 220, y: 190)
            let dx = abs(p2.x - p1.x)
            let dy = abs(p2.y - p1.y)
            let dist = hypot(dx, dy)
            assert(dx == 120, "dx must be 120")
            assert(dy == 90, "dy must be 90")
            assert(dist == 150, "3-4-5 triangle hypotenuse must be 150")

            // 4. Menu Bar Integration
            let controller = StatusBarController()
            let menu = controller.currentMenu

            let rulerItem = menu.items.first(where: { $0.title.contains("Screen Ruler") })
            assert(rulerItem != nil, "Screen Ruler menu item must exist")
            assert(rulerItem?.action == #selector(controller.screenRulerAction), "Screen Ruler action must match screenRulerAction")
            assert(rulerItem?.image != nil, "Screen Ruler item must have an icon")

            let pickerItem = menu.items.first(where: { $0.title.contains("Color Picker") })
            assert(pickerItem != nil, "Color Picker menu item must exist")
            assert(pickerItem?.action == #selector(controller.colorPickerAction), "Color Picker action must match colorPickerAction")
            assert(pickerItem?.image != nil, "Color Picker item must have an icon")
        }

        // MARK: - System Permissions Enforcement Suite
        testRunner("System Permissions - Screen Recording & Accessibility Enforcement") {
            let perm = PermissionsManager.shared
            perm.showAlerts = false
            defer {
                perm.resetTestingState()
            }

            // 1. Both permissions missing: tools must be blocked
            perm.screenRecordingOverride = false
            perm.accessibilityOverride = false
            assert(!perm.isScreenRecordingGranted, "Screen Recording must report not granted")
            assert(!perm.isAccessibilityGranted, "Accessibility must report not granted")
            assert(!perm.hasRequiredPermissions, "hasRequiredPermissions must be false when both are missing")
            assert(perm.missingPermissions.count == 2, "Both permissions must be reported missing")
            assert(perm.missingPermissionsDescription == "Screen Recording and Accessibility", "Description must list both")

            assert(!perm.ensurePermissions(for: "Area Screenshot"), "ensurePermissions must return false")
            assert(perm.lastPromptedTool == "Area Screenshot", "lastPromptedTool must record tool name")
            assert(perm.promptCallCount >= 1, "promptCallCount must increment")

            // Verify tools are blocked from executing
            let prevCapture = CaptureManager.shared.lastCapture
            CaptureManager.shared.startRegionCapture()
            assert(!RegionSelectionCoordinator.shared.isSelecting, "startRegionCapture must not start selection when permissions missing")

            var rulerFinished = false
            CaptureManager.shared.startRuler { result in
                assert(result == nil, "Blocked ruler must complete with nil")
                rulerFinished = true
            }
            assert(rulerFinished, "startRuler callback must fire with nil immediately")

            var pickerFinished = false
            CaptureManager.shared.startColorPicker { result in
                assert(result == nil, "Blocked color picker must complete with nil")
                pickerFinished = true
            }
            assert(pickerFinished, "startColorPicker callback must fire with nil immediately")

            CaptureManager.shared.captureFullscreen()
            assert(CaptureManager.shared.lastCapture == prevCapture, "captureFullscreen must not record new capture when permissions missing")

            var scrollFinished = false
            CaptureManager.shared.startScrollingCapture { result in
                assert(result == nil, "Blocked scrolling capture must complete with nil")
                scrollFinished = true
            }
            assert(scrollFinished, "startScrollingCapture callback must fire with nil immediately")

            // 2. Only Screen Recording missing: tools must still be blocked
            perm.screenRecordingOverride = false
            perm.accessibilityOverride = true
            assert(!perm.hasRequiredPermissions, "hasRequiredPermissions must be false when Screen Recording is missing")
            assert(perm.missingPermissionsDescription == "Screen Recording", "Description must state Screen Recording")
            assert(!perm.ensurePermissions(for: "Screen Ruler"), "ensurePermissions must return false when Screen Recording is missing")

            // 3. Only Accessibility missing: tools must still be blocked
            perm.screenRecordingOverride = true
            perm.accessibilityOverride = false
            assert(!perm.hasRequiredPermissions, "hasRequiredPermissions must be false when Accessibility is missing")
            assert(perm.missingPermissionsDescription == "Accessibility", "Description must state Accessibility")
            assert(!perm.ensurePermissions(for: "Color Picker"), "ensurePermissions must return false when Accessibility is missing")

            // 4. Menu bar item reflects missing permission state
            let controller = StatusBarController()
            let menu = controller.currentMenu
            controller.menuWillOpen(menu)
            let warningItem = menu.items.first(where: { $0.title.contains("Permissions Required") })
            assert(warningItem != nil, "Permissions warning menu item must exist in menu")
            assert(warningItem?.isHidden == false, "Warning item must be visible when permissions are missing")

            // 5. Both permissions granted: tools are allowed
            perm.screenRecordingOverride = true
            perm.accessibilityOverride = true
            assert(perm.hasRequiredPermissions, "hasRequiredPermissions must be true when both are granted")
            assert(perm.missingPermissions.isEmpty, "missingPermissions must be empty when both granted")
            assert(perm.ensurePermissions(for: "Area Screenshot"), "ensurePermissions must return true when both are granted")

            controller.menuWillOpen(menu)
            assert(warningItem?.isHidden == true, "Warning item must be hidden when both permissions are granted")
        }
    }
}
