import Foundation

/// This build's version, as the Mac reports it to tablets (WELCOME `mac.app`) and in reports.
public enum AppVersion {
    /// Compiled in for tools without an app bundle (`t2m`, tests). `Resources/Info.plist` carries
    /// the same value; a test keeps the two in step.
    public static let compiled = "0.1.0"

    /// The app bundle's `CFBundleShortVersionString` when running as Tab2Mac.app, else `compiled`.
    public static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? compiled
    }
}
