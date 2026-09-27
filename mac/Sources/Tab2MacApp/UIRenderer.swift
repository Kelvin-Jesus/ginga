import AppKit
import SwiftUI
import Tab2MacCore

/// `--render-ui <dir>`: renders the main window and Ajustes in every appearance to PNGs and
/// quits, for design review. Starts nothing (no display, no listeners, no network changes).
@MainActor
enum UIRenderer {
    static func render(model: AppModel, to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let saved = UserDefaults.standard.string(forKey: GingaAppearance.storageKey)
        let savedLanguage = UserDefaults.standard.string(forKey: GingaLanguage.storageKey)
        defer {
            UserDefaults.standard.set(saved, forKey: GingaAppearance.storageKey)
            UserDefaults.standard.set(savedLanguage, forKey: GingaLanguage.storageKey)
        }
        // Portuguese, the brand's first language (English is the system's choice on most Macs).
        UserDefaults.standard.set(GingaLanguage.portuguese.rawValue, forKey: GingaLanguage.storageKey)
        for appearance in [GingaAppearance.light, .dark, .space] {
            UserDefaults.standard.set(appearance.rawValue, forKey: GingaAppearance.storageKey)
            snapshot(GingaThemed(animates: false) { MainWindowView(model: model, showSettings: {}) },
                     size: NSSize(width: 480, height: 700), appearance: appearance,
                     to: directory.appendingPathComponent("mac-main-\(appearance.rawValue).png"))
            snapshot(GingaThemed(animates: false) { SettingsView(model: model, showPreview: {}) },
                     size: NSSize(width: 540, height: 1500), appearance: appearance,
                     to: directory.appendingPathComponent("mac-settings-\(appearance.rawValue).png"))
        }
    }

    private static func snapshot<V: View>(_ view: V, size: NSSize, appearance: GingaAppearance, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance.nsAppearance
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))  // let SwiftUI settle its first layout
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        Log.app.info("app.render-ui file=\(url.lastPathComponent, privacy: .public)")
    }
}
