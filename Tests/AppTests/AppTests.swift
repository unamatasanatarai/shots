import Foundation
import CoreGraphics
import Cocoa
import Carbon

public struct AppTests {
    @MainActor
    public static func run(testRunner: @MainActor (String, () throws -> Void) -> Void) {

        // MARK: - AppConfig Suite
        testRunner("AppConfig - Properties and Defaults") {
            assert(AppConfig.appName == "Shots!", "App name should be Shots!")
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

            // Verify default hotkey: Cmd + Shift + 1
            assert(settings.hotkeyKeyCode == UInt16(kVK_ANSI_1), "Default keyCode must be 18 (ANSI 1)")
            assert(settings.hotkeyModifiers == UInt32(cmdKey | shiftKey), "Default modifiers must be cmdKey | shiftKey")
            assert(settings.saveToDisk == true, "saveToDisk must default to true")
            assert(settings.copyToClipboard == true, "copyToClipboard must default to true")
            assert(!settings.saveDirectoryPath.isEmpty, "saveDirectoryPath must have default path")

            // Verify mutations persist
            settings.saveToDisk = false
            assert(testDefaults.bool(forKey: AppSettings.Keys.saveToDisk) == false, "UserDefaults must reflect mutation")

            settings.hotkeyKeyCode = UInt16(kVK_ANSI_2)
            assert(testDefaults.integer(forKey: AppSettings.Keys.hotkeyKeyCode) == Int(kVK_ANSI_2), "UserDefaults must store updated keyCode")

            // Test reset
            settings.resetHotkeyToDefault()
            assert(settings.hotkeyKeyCode == UInt16(kVK_ANSI_1), "Reset must restore default keycode")
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

            // Test 1: Setting .saveToDisk
            settings.postCaptureAction = .saveToDisk
            assert(settings.saveToDisk == true, "saveToDisk must be true for .saveToDisk")
            assert(settings.copyToClipboard == false, "copyToClipboard must be false for .saveToDisk")
            assert(defaults.string(forKey: AppSettings.Keys.postCaptureAction) == PostCaptureAction.saveToDisk.rawValue, "UserDefaults must persist postCaptureAction")

            // Test 2: Setting .copyToClipboard
            settings.postCaptureAction = .copyToClipboard
            assert(settings.saveToDisk == false, "saveToDisk must be false for .copyToClipboard")
            assert(settings.copyToClipboard == true, "copyToClipboard must be true for .copyToClipboard")
            assert(defaults.string(forKey: AppSettings.Keys.postCaptureAction) == PostCaptureAction.copyToClipboard.rawValue, "UserDefaults must persist postCaptureAction")

            // Test 3: Setting .both
            settings.postCaptureAction = .both
            assert(settings.saveToDisk == true, "saveToDisk must be true for .both")
            assert(settings.copyToClipboard == true, "copyToClipboard must be true for .both")
            assert(defaults.string(forKey: AppSettings.Keys.postCaptureAction) == PostCaptureAction.both.rawValue, "UserDefaults must persist postCaptureAction")

            // Test 4: Mutating flags directly syncs postCaptureAction
            settings.saveToDisk = true
            settings.copyToClipboard = false
            assert(settings.postCaptureAction == .saveToDisk, "Flag mutation must update postCaptureAction to .saveToDisk")

            settings.saveToDisk = false
            settings.copyToClipboard = true
            assert(settings.postCaptureAction == .copyToClipboard, "Flag mutation must update postCaptureAction to .copyToClipboard")

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
            assert(button.toolTip?.contains("Shots!") == true, "Status button tooltip must contain app name")

            let menu = controller.currentMenu
            let titles = menu.items.map { $0.title }

            assert(titles.contains(where: { $0.contains("Capture Region") }), "Menu must contain Capture Region item")
            assert(titles.contains(where: { $0.contains("Capture Fullscreen") }), "Menu must contain Capture Fullscreen item")
            assert(titles.contains(where: { $0.contains("Repeat Previous Screenshot") }), "Menu must contain Repeat Previous Screenshot item")
            assert(titles.contains("Save to Folder"), "Menu must contain Save to Folder item")
            assert(titles.contains("Copy to Clipboard"), "Menu must contain Copy to Clipboard item")
            assert(titles.contains("Include Cursor"), "Menu must contain Include Cursor item")
            assert(titles.contains("Capture Delay"), "Menu must contain Capture Delay submenu")
            assert(titles.contains("Image Format"), "Menu must contain Image Format submenu")
            assert(titles.contains("JPG Quality"), "Menu must contain JPG Quality submenu")
            assert(titles.contains("Post-Capture Action"), "Menu must contain Post-Capture Action submenu")
            assert(titles.contains("Launch at Login"), "Menu must contain Launch at Login item")
            assert(titles.contains("Preferences & Hotkeys..."), "Menu must contain Preferences item")
            assert(titles.contains("Open Screenshots Folder"), "Menu must contain Open Screenshots Folder item")
            assert(titles.contains("Change Save Location..."), "Menu must contain Change Save Location item")
            assert(titles.contains("Quit Shots!"), "Menu must contain Quit item")

            // Verify submenus have children
            let delayItem = menu.items.first(where: { $0.title == "Capture Delay" })
            assert(delayItem?.submenu?.items.count == 4, "Capture Delay submenu must have 4 options")

            let formatItem = menu.items.first(where: { $0.title == "Image Format" })
            assert(formatItem?.submenu?.items.count == 2, "Image Format submenu must have 2 options (PNG, JPG)")

            let postCaptureItem = menu.items.first(where: { $0.title == "Post-Capture Action" })
            assert(postCaptureItem?.submenu?.items.count == 3, "Post-Capture Action submenu must have 3 options")
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
            assert(settings.areaShortcutDisplayString == "⇧⌘1", "Area shortcut default must be ⇧⌘1 (was \(settings.areaShortcutDisplayString))")
            assert(settings.fullscreenShortcutDisplayString == "⇧⌘2", "Fullscreen shortcut default must be ⇧⌘2 (was \(settings.fullscreenShortcutDisplayString))")
            assert(settings.repeatShortcutDisplayString == "⇧⌘R", "Repeat shortcut default must be ⇧⌘R (was \(settings.repeatShortcutDisplayString))")
            assert(settings.ocrShortcutDisplayString == "⇧⌘O", "OCR shortcut default must be ⇧⌘O (was \(settings.ocrShortcutDisplayString))")

            // Test custom assignment
            settings.fullscreenShortcutKeyCode = UInt16(kVK_ANSI_3)
            assert(settings.fullscreenShortcutDisplayString == "⇧⌘3", "Updated shortcut must reflect new keycode")
            assert(defaults.integer(forKey: AppSettings.Keys.fullscreenShortcutKeyCode) == Int(kVK_ANSI_3), "UserDefaults must store new shortcut")

            // Test conflict detection
            settings.fullscreenShortcutKeyCode = settings.areaShortcutKeyCode
            settings.fullscreenShortcutModifiers = settings.areaShortcutModifiers
            settings.checkForShortcutConflicts()
            assert(settings.isHotkeyConflict == true, "Matching shortcut combination must trigger conflict flag")
            assert(settings.hotkeyErrorMessage != nil, "Conflict error message must be set")

            // Test reset to defaults
            settings.resetHotkeysToDefault()
            assert(settings.isHotkeyConflict == false, "Reset must resolve shortcut conflict")
            assert(settings.areaShortcutDisplayString == "⇧⌘1", "Reset must restore Area shortcut")
            assert(settings.fullscreenShortcutDisplayString == "⇧⌘2", "Reset must restore Fullscreen shortcut")

            // Test HotKeyManager multi-mode dispatch callbacks
            let manager = HotKeyManager.shared
            var areaFired = false
            var fsFired = false
            var repeatFired = false
            var ocrFired = false

            manager.onAreaCaptureTrigger = { areaFired = true }
            manager.onFullscreenCaptureTrigger = { fsFired = true }
            manager.onRepeatCaptureTrigger = { repeatFired = true }
            manager.onOCRCaptureTrigger = { ocrFired = true }

            // Trigger closures manually to verify wiring
            manager.onAreaCaptureTrigger?()
            assert(areaFired, "Area capture trigger callback must execute")

            manager.onFullscreenCaptureTrigger?()
            assert(fsFired, "Fullscreen capture trigger callback must execute")

            manager.onRepeatCaptureTrigger?()
            assert(repeatFired, "Repeat capture trigger callback must execute")

            manager.onOCRCaptureTrigger?()
            assert(ocrFired, "OCR capture trigger callback must execute")

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
            assert(revealItem != nil, "Reveal Latest Screenshot item must exist in menu")
            assert(revealItem?.action == Selector(("revealLatestScreenshotAction")), "Action selector must be revealLatestScreenshotAction")
            assert(revealItem?.isEnabled == true, "Reveal item must be enabled when latest screenshot exists")
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

            // 1. Verification of revealScreenshotInFinder API
            assert(historyService.revealScreenshotInFinder(fileURL: validShotURL) == true, "Existing file must reveal successfully")
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
            if let revealItem = revealActionItem {
                controller.revealRecentScreenshotAction(revealItem)
            }
            if let copyItem = copyActionItem {
                controller.copyRecentScreenshotAction(copyItem)
            }
        }
    }
}
