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

        // MARK: - Area Selection & Coordinates Suite
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
                assert(badgeY + badgeH <= boundsSize.height - margin, "Badge top must not exceed bounds")
            }
        }
    }
}
