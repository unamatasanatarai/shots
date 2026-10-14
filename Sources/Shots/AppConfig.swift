import Foundation

public struct AppConfig {
    public static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Shots"
    }

    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    public static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.local.Shots"
    }

    public static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © \(Calendar.current.component(.year, from: Date())). All rights reserved."
    }

    public static var minSystemVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "12.0"
    }
}
