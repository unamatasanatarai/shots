import Foundation

public struct AppConfig {
    public static let appName: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Shots"
    }()

    public static let version: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }()

    public static let bundleIdentifier: String = {
        Bundle.main.bundleIdentifier ?? "com.local.Shots"
    }()

    public static let copyright: String = {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © \(Calendar.current.component(.year, from: Date())). All rights reserved."
    }()

    public static let minSystemVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "12.0"
    }()
}
