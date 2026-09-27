// Gerado de tokens.json (Ginga design system). Não edite à mão: regenere.
import SwiftUI

enum GingaAppearance: String, CaseIterable, Identifiable {
    case system, light, dark, space
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Escuro"
        case .space: return "Black espacial"
        }
    }
}

struct GingaPalette {
    let cobalt: Color
    let onCobalt: Color
    let cobaltBrand: Color
    let cobaltSoft: Color
    let bg: Color
    let surface: Color
    let surface2: Color
    let ink: Color
    let inkMuted: Color
    let line: Color
    let star: Color
    let success: Color
    let warning: Color
    let danger: Color
    let cosmos: Color
    let stardust: Color
}

extension GingaPalette {
    static let light = GingaPalette(
        cobalt: Color(red: 0.1804, green: 0.2784, blue: 0.9608),
        onCobalt: Color(red: 1.0000, green: 1.0000, blue: 1.0000),
        cobaltBrand: Color(red: 0.1804, green: 0.2784, blue: 0.9608),
        cobaltSoft: Color(red: 0.8902, green: 0.9059, blue: 0.9961),
        bg: Color(red: 0.9490, green: 0.9529, blue: 0.9725),
        surface: Color(red: 1.0000, green: 1.0000, blue: 1.0000),
        surface2: Color(red: 0.9098, green: 0.9176, blue: 0.9529),
        ink: Color(red: 0.0784, green: 0.0941, blue: 0.1882),
        inkMuted: Color(red: 0.3373, green: 0.3569, blue: 0.4706),
        line: Color(red: 0.8627, green: 0.8745, blue: 0.9176),
        star: Color(red: 0.9490, green: 0.6627, blue: 0.0000),
        success: Color(red: 0.0745, green: 0.5412, blue: 0.3216),
        warning: Color(red: 0.6980, green: 0.4157, blue: 0.0000),
        danger: Color(red: 0.7608, green: 0.2314, blue: 0.2314),
        cosmos: Color(red: 0.0392, green: 0.0471, blue: 0.1098),
        stardust: Color(red: 0.9490, green: 0.9529, blue: 0.9725)
    )
    static let dark = GingaPalette(
        cobalt: Color(red: 0.4353, green: 0.5098, blue: 1.0000),
        onCobalt: Color(red: 0.0784, green: 0.0941, blue: 0.1882),
        cobaltBrand: Color(red: 0.1804, green: 0.2784, blue: 0.9608),
        cobaltSoft: Color(red: 0.1451, green: 0.1725, blue: 0.4000),
        bg: Color(red: 0.0784, green: 0.0941, blue: 0.1882),
        surface: Color(red: 0.0902, green: 0.1020, blue: 0.2000),
        surface2: Color(red: 0.1255, green: 0.1412, blue: 0.2902),
        ink: Color(red: 0.9490, green: 0.9529, blue: 0.9725),
        inkMuted: Color(red: 0.6431, green: 0.6627, blue: 0.7843),
        line: Color(red: 0.1647, green: 0.1804, blue: 0.3020),
        star: Color(red: 1.0000, green: 0.7686, blue: 0.2392),
        success: Color(red: 0.3098, green: 0.8157, blue: 0.5569),
        warning: Color(red: 0.9490, green: 0.6980, blue: 0.2980),
        danger: Color(red: 0.9412, green: 0.4549, blue: 0.4549),
        cosmos: Color(red: 0.0392, green: 0.0471, blue: 0.1098),
        stardust: Color(red: 0.9490, green: 0.9529, blue: 0.9725)
    )
    static let space = GingaPalette(
        cobalt: Color(red: 0.4353, green: 0.5098, blue: 1.0000),
        onCobalt: Color(red: 0.0000, green: 0.0000, blue: 0.0000),
        cobaltBrand: Color(red: 0.1804, green: 0.2784, blue: 0.9608),
        cobaltSoft: Color(red: 0.0863, green: 0.1059, blue: 0.2706),
        bg: Color(red: 0.0000, green: 0.0000, blue: 0.0000),
        surface: Color(red: 0.0000, green: 0.0000, blue: 0.0000),
        surface2: Color(red: 0.0000, green: 0.0000, blue: 0.0000),
        ink: Color(red: 0.9490, green: 0.9529, blue: 0.9725),
        inkMuted: Color(red: 0.6196, green: 0.6392, blue: 0.7608),
        line: Color(red: 0.1098, green: 0.1255, blue: 0.2510),
        star: Color(red: 1.0000, green: 0.7686, blue: 0.2392),
        success: Color(red: 0.3098, green: 0.8157, blue: 0.5569),
        warning: Color(red: 0.9490, green: 0.6980, blue: 0.2980),
        danger: Color(red: 0.9412, green: 0.4549, blue: 0.4549),
        cosmos: Color(red: 0.0392, green: 0.0471, blue: 0.1098),
        stardust: Color(red: 0.9490, green: 0.9529, blue: 0.9725)
    )
}

// Espaçamento, raios e movimento
enum GingaSpace { static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s6: CGFloat = 24, s8: CGFloat = 32, s12: CGFloat = 48 }
enum GingaRadius { static let sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 18, xl: CGFloat = 28 }
enum GingaMotion {
    /// ease-ginga: cubic-bezier(0.34, 1.36, 0.64, 1) — passa um pouco do ponto e volta
    static let ginga = Animation.timingCurve(0.34, 1.36, 0.64, 1, duration: 0.22)
    static let sheet = Animation.timingCurve(0.34, 1.36, 0.64, 1, duration: 0.42)
    static let easeOut = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)
    static let tap: Double = 0.12, orbit: Double = 2.4, warp: Double = 1.4
}
