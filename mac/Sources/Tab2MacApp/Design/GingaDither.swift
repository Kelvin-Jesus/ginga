import CoreGraphics
import Foundation
import SwiftUI

// The Black espacial theme's space scenery, like the site's: a spiral galaxy and a black hole
// in coarse pixels with ordered (Bayer) dithering. Cheap by construction: a small grid (one
// cell ≈ 3 pt) computed on the CPU into one bitmap, drawn scaled up without smoothing, about
// ten times a second, only while visible and when motion isn't reduced; otherwise one still frame.

/// The pure part: a scene at time `t` → RGBA pixels (premultiplied, row-major, top row first).
struct DitherField {
    enum Scene { case galaxy, blackHole }

    let width: Int
    let height: Int
    let scene: Scene

    /// Brightness levels on black: deep blue → cobalt → night cobalt → pale → white.
    static let blues: [UInt32] = [0x000000, 0x161B45, 0x2E47F5, 0x6F82FF, 0xC8D0FF, 0xF2F3F8]
    static let gold: UInt32 = 0xFFC43D
    /// 4×4 Bayer matrix, thresholds in [0, 1).
    static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 }

    /// Seconds for the galaxy to turn once: slow enough not to draw the eye.
    static let galaxyTurn: Double = 120

    func render(time t: Double, into pixels: inout [UInt32]) {
        if pixels.count != width * height { pixels = [UInt32](repeating: 0, count: width * height) }
        let cx = Double(width) / 2, cy = Double(height) / 2
        let scale = min(Double(width), Double(height) * 2) / 2  // the scenes are wider than tall
        for y in 0..<height {
            for x in 0..<width {
                let dx = (Double(x) + 0.5 - cx) / scale
                let dy = (Double(y) + 0.5 - cy) / scale
                let (intensity, hot) = switch scene {
                case .galaxy: galaxy(dx, dy, t)
                case .blackHole: blackHole(dx, dy, t)
                }
                let star = Self.star(x, y, t)
                pixels[y * width + x] = Self.color(intensity: max(intensity, star), hot: hot, x: x, y: y)
            }
        }
    }

    /// Two logarithmic arms around a gold core, seen at an angle.
    private func galaxy(_ dx: Double, _ dy: Double, _ t: Double) -> (Double, Bool) {
        let tilt = 0.5
        let rotation = t / Self.galaxyTurn * 2 * .pi
        let ex = dx * cos(0.45) + dy * sin(0.45)
        let ey = (-dx * sin(0.45) + dy * cos(0.45)) / tilt
        let r = (ex * ex + ey * ey).squareRoot()
        guard r < 1.05 else { return (0, false) }
        let theta = atan2(ey, ex) - rotation
        let arm = pow(0.5 + 0.5 * cos(2 * (theta + 2.7 * log(r + 0.03))), 5)
        let falloff = exp(-2.4 * r) * max(0, 1 - r)
        let core = exp(-pow(r / 0.13, 2))
        let haze = 0.12 * exp(-3.5 * r)
        return (arm * falloff * 1.7 + haze + core * 1.1, core > 0.35)
    }

    /// A dark disc with its photon ring, and an accretion disk crossing it, brighter on the
    /// approaching (left) side; the disk's far side shows lensed above the hole.
    private func blackHole(_ dx: Double, _ dy: Double, _ t: Double) -> (Double, Bool) {
        let horizon = 0.28
        let r = (dx * dx + dy * dy).squareRoot()
        let ring = exp(-pow((r - horizon) / 0.025, 2)) * 0.9
        let diskY = dy / 0.2
        let rd = (dx * dx + diskY * diskY).squareRoot()
        let angle = atan2(diskY, dx)
        let texture = 0.65 + 0.35 * sin(9 * angle - t * 0.8 + 7 * rd)
        let doppler = 1 + 0.7 * (-dx / max(rd, 0.001))
        var disk = exp(-pow((rd - 0.62) / 0.3, 2)) * texture * doppler * 0.8
        let behind = dy < 0 && r < horizon * 1.02
        if behind { disk = 0 }  // the far half of the disk is hidden by the hole
        let lensed = dy < 0 ? exp(-pow((r - horizon * 1.35) / 0.05, 2)) * 0.55 * (0.8 + 0.2 * sin(6 * atan2(dy, dx) + t * 0.5)) : 0
        let inside = r < horizon * 0.97 && !(dy >= 0 && disk > 0.15)
        if inside { return (ring * 0.2, false) }
        let intensity = max(disk, ring, lensed)
        return (intensity, disk > 0.75 && dx < 0.1)
    }

    /// Sparse star pixels, each twinkling on its own slow period.
    private static func star(_ x: Int, _ y: Int, _ t: Double) -> Double {
        var h = UInt32(truncatingIfNeeded: x &* 73_856_093 ^ y &* 19_349_663)
        h ^= h >> 13
        h = h &* 0x5bd1e995
        h ^= h >> 15
        guard h % 97 == 0 else { return 0 }
        let phase = Double(h % 628) / 100
        return 0.35 + 0.3 * sin(t * (0.6 + Double(h % 7) / 10) + phase)
    }

    /// Ordered dithering between two neighbouring levels, then the palette.
    static func color(intensity: Double, hot: Bool, x: Int, y: Int) -> UInt32 {
        let threshold = bayer[(y & 3) * 4 + (x & 3)]
        let scaled = min(max(intensity, 0), 1) * Double(blues.count - 1)
        let level = min(Int(scaled + threshold), blues.count - 1)  // floor(value + threshold)
        guard level > 0 else { return 0 }  // transparent: the black behind shows
        let rgb = hot && level >= 3 ? (level == blues.count - 1 ? blues[level] : gold) : blues[level]
        // Fully opaque; the word A·B·G·R puts the bytes R, G, B, A in memory (little-endian).
        let r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF
        return 0xFF00_0000 | (b << 16) | (g << 8) | r
    }

    func image(time t: Double, pixels: inout [UInt32]) -> CGImage? {
        render(time: t, into: &pixels)
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            // Bytes R, G, B, A in memory (the words above are A·B·G·R on a little-endian Mac).
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

/// The scenery in a view: only in Black espacial; animated at ~10 fps while the window is
/// visible and motion isn't reduced, else a still frame.
struct GingaDitherScene: View {
    @Environment(\.ginga) private var palette
    @Environment(\.gingaAnimates) private var animates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let scene: DitherField.Scene
    /// Points per dithered pixel.
    var cell: CGFloat = 3

    var body: some View {
        if palette.isSpace {
            GeometryReader { geometry in
                let field = DitherField(
                    width: max(8, Int(geometry.size.width / cell)), height: max(8, Int(geometry.size.height / cell)), scene: scene
                )
                if animates && !reduceMotion {
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        DitherFrame(field: field, time: context.date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    DitherFrame(field: field, time: 40)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct DitherFrame: View {
    let field: DitherField
    let time: Double

    var body: some View {
        Canvas { context, size in
            var pixels: [UInt32] = []
            guard let image = field.image(time: time, pixels: &pixels) else { return }
            // Nearest neighbour: the pixels stay square (the look), and scaling costs nothing.
            context.draw(Image(decorative: image, scale: 1).interpolation(.none), in: CGRect(origin: .zero, size: size))
        }
    }
}
