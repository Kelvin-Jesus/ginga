import Foundation
import SwiftUI
import Testing
@testable import GingaApp

@Suite("Ginga presentation")
struct GingaPresentationTests {
    /// The link, from the connection's endpoint: what the StatusOrbit says after "Conectado".
    @Test func theLinkComesFromTheEndpoint() {
        #expect(AppModel.Link(endpoint: "usb-accessory:R52Y80EE15V") == .usb)
        #expect(AppModel.Link(endpoint: "127.0.0.1:52050") == .adb)
        #expect(AppModel.Link(endpoint: "192.168.49.1:52610") == .wifi)
        #expect(AppModel.Link(endpoint: "[fe80::1%en0]:5000") == .wifi)
    }

    /// Friendly names, never the raw model alone (DeviceRow).
    @Test @MainActor func tabletsGetFriendlyNames() {
        #expect(AppModel.friendlyName("SM-X730") == "Galaxy Tab S11")
        #expect(AppModel.friendlyName("samsung SM-X730") == "Galaxy Tab S11")  // a stored pairing name
        #expect(AppModel.friendlyName("Pixel_Tablet") == "Pixel-Tablet")
        #expect(AppModel.friendlyName(nil) == "tablet")
    }

    /// Black espacial is pure black everywhere that is an area, and a dark appearance.
    @Test func themes() {
        #expect(GingaAppearance.space.palette(for: .light).bg == Color(red: 0, green: 0, blue: 0))
        #expect(GingaAppearance.space.palette(for: .light).surface == GingaAppearance.space.palette(for: .light).bg)
        #expect(GingaAppearance.space.colorScheme == .dark)
        #expect(GingaAppearance.system.colorScheme == nil)
        #expect(GingaAppearance.system.palette(for: .dark) == .dark)
        #expect(GingaAppearance.system.palette(for: .light) == .light)
        #expect(GingaPalette.space.isSpace && GingaPalette.space.isDark && !GingaPalette.light.isDark)
    }

    @Test func languageChoiceOverridesTheSystem() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: GingaLanguage.storageKey)
        defer { defaults.set(saved, forKey: GingaLanguage.storageKey) }
        defaults.set("pt", forKey: GingaLanguage.storageKey)
        #expect(tr("Criar display", "Create display") == "Criar display")
        defaults.set("en", forKey: GingaLanguage.storageKey)
        #expect(tr("Criar display", "Create display") == "Create display")
    }
}
