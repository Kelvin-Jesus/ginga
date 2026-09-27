import AppKit
import SwiftUI

// The Ginga design system in the app: which palette is in effect, whether motion may run, and
// the strings. `GingaTheme.swift` is generated from tokens.json and stays untouched.

// Plain keys: the Command Line Tools toolchain has no SwiftUI macro plugin for `@Entry`.
private struct GingaPaletteKey: EnvironmentKey { static let defaultValue = GingaPalette.light }
private struct GingaAppearanceKey: EnvironmentKey { static let defaultValue = GingaAppearance.system }
private struct GingaAnimatesKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// The palette of the current appearance (Claro, Escuro, Black espacial).
    var ginga: GingaPalette {
        get { self[GingaPaletteKey.self] }
        set { self[GingaPaletteKey.self] = newValue }
    }
    var gingaAppearance: GingaAppearance {
        get { self[GingaAppearanceKey.self] }
        set { self[GingaAppearanceKey.self] = newValue }
    }
    /// False while the window is hidden or covered: orbits and pulses stop (nothing animates off screen).
    var gingaAnimates: Bool {
        get { self[GingaAnimatesKey.self] }
        set { self[GingaAnimatesKey.self] = newValue }
    }
}

extension GingaAppearance {
    /// The stored choice (`@AppStorage("appearance")`), for code outside SwiftUI views.
    static var stored: GingaAppearance {
        GingaAppearance(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    static let storageKey = "appearance"

    func palette(for scheme: ColorScheme) -> GingaPalette {
        switch self {
        case .system: scheme == .dark ? .dark : .light
        case .light: .light
        case .dark: .dark
        case .space: .space
        }
    }

    /// Black espacial is a dark appearance; Sistema follows macOS.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .space: .dark
        }
    }

    var localizedLabel: String {
        switch self {
        case .system: tr("Sistema", "System")
        case .light: tr("Claro", "Light")
        case .dark: tr("Escuro", "Dark")
        case .space: tr("Black espacial", "Space black")
        }
    }

    /// The window's AppKit appearance (title bar, sheets, menus inside the window).
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark, .space: NSAppearance(named: .darkAqua)
        }
    }
}

/// Applies the stored appearance to a window's content: palette in the environment, forced
/// color scheme, and the `bg` behind everything.
struct GingaThemed<Content: View>: View {
    @AppStorage(GingaAppearance.storageKey) private var appearance: GingaAppearance = .system
    /// Read so a language change redraws every string at once.
    @AppStorage(GingaLanguage.storageKey) private var language: GingaLanguage = .system
    @Environment(\.colorScheme) private var systemScheme
    var animates = true
    @ViewBuilder var content: Content

    var body: some View {
        let palette = appearance.palette(for: appearance.colorScheme ?? systemScheme)
        content
            .id(language)
            .environment(\.ginga, palette)
            .environment(\.gingaAppearance, appearance)
            .environment(\.gingaAnimates, animates)
            .foregroundStyle(palette.ink)
            .tint(palette.cobalt)
            .background(palette.bg.ignoresSafeArea())
            .preferredColorScheme(appearance.colorScheme)
    }
}

extension GingaPalette {
    /// Dark palettes (Escuro, Black espacial) use the light-on-dark logo variants.
    var isDark: Bool { bg == GingaPalette.dark.bg || bg == GingaPalette.space.bg }
    var isSpace: Bool { bg == GingaPalette.space.bg }
}

extension GingaPalette: Equatable {
    static func == (lhs: GingaPalette, rhs: GingaPalette) -> Bool {
        lhs.bg == rhs.bg && lhs.surface == rhs.surface && lhs.cobalt == rhs.cobalt
    }
}

// MARK: Strings

/// pt-BR first, English as the second language (brand book). Ajustes › Aparência › Idioma picks
/// one; Sistema follows the Mac's preferred language.
enum GingaLanguage: String, CaseIterable {
    case system, portuguese = "pt", english = "en"

    static let storageKey = "language"
    private static let systemIsPortuguese = Locale.preferredLanguages.first?.lowercased().hasPrefix("pt") ?? false

    static var isPortuguese: Bool {
        switch GingaLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system {
        case .system: systemIsPortuguese
        case .portuguese: true
        case .english: false
        }
    }

    var label: String {
        switch self {
        case .system: tr("Sistema", "System")
        case .portuguese: "Português"
        case .english: "English"
        }
    }
}

/// A user-facing string in Portuguese and English.
func tr(_ portuguese: String, _ english: String) -> String {
    GingaLanguage.isPortuguese ? portuguese : english
}
