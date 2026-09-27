import AppKit
import CoreText
import Foundation
import SwiftUI

/// The brand fonts (brand/fonts, SIL OFL): Unbounded for the title and the brand, IBM Plex Mono
/// for numbers, specs and the pairing code. The app bundle registers them through
/// `ATSApplicationFontsPath`; a development build run from `.build` registers them from the
/// source tree. The rest of the UI stays in SF Pro, as the brand book allows on the Mac.
enum GingaFonts {
    static let display = "Unbounded"
    static let mono = "IBM Plex Mono"

    /// Once, at launch: only needed outside the app bundle.
    static func registerIfNeeded() {
        guard NSFont(name: "IBMPlexMono-Regular", size: 12) == nil else { return }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
            executable.deletingLastPathComponent().appendingPathComponent("../../../Resources/Fonts").standardized,  // mac/.build/<config>/
        ].compactMap { $0 }
        for directory in candidates {
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "ttf" {
                CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
            }
            return
        }
    }
}

extension Font {
    /// Unbounded (variable), for titles and the brand only.
    static func gingaDisplay(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom(GingaFonts.display, size: size).weight(weight)
    }

    /// IBM Plex Mono, for numbers, specs and codes.
    static func gingaMono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular", size: size)
    }
}
