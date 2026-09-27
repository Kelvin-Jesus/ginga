import CoreGraphics
import Foundation
import SwiftUI

// DitherSpace (design/ginga-design/components/DitherSpace.md): a black hole and a spiral galaxy
// in coarse pixels, dithered with a 4×4 Bayer matrix into the brand's six colours, drawn scaled
// up without smoothing. A port of reference/bundle.js (blackHole, galaxy, ditherLoop) as is.
// Cheap: one small buffer (1 pixel = 4 screen px) recomputed ~24 times a second, only while the
// window is visible and motion isn't reduced; otherwise one still frame.

/// The pure part: a scene at time `t` → RGBA pixels. Holds the scene's precomputed geometry and,
/// for the black hole, its orbiting particles (advanced once per rendered frame, as on the site).
final class DitherField {
    enum Scene: Equatable { case galaxy, blackHole }

    let width: Int
    let height: Int
    let scene: Scene

    /// cosmos (transparent: the background shows), Noite, cobalt-brand, Cobalto noturno, stardust, star.
    static let palette: [(UInt8, UInt8, UInt8)] = [(10, 12, 28), (20, 24, 48), (46, 71, 245), (111, 130, 255), (242, 243, 248), (255, 196, 61)]
    static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 }
    /// Galaxy spin of the reference (rad/s).
    static let galaxySpin = 0.35
    /// Seconds per rendered frame (the reference's 42 ms).
    static let frameInterval = 0.042

    // Black hole constants (bundle.js).
    private static let horizon = 0.28, tilt = 0.2, rIn = 0.42, rOut = 1.6

    /// 0…1: how far the orbits have collapsed (the site ties it to the pointer's distance).
    var pullTarget = 0.0
    /// When the particles last burst (seconds on the render clock); -99 = never.
    var burstTime = -99.0
    private var pull = 0.0

    private var values: [Double]
    private var geometry: [Double] = []  // per pixel, scene-specific fields interleaved
    private var particles: [(r: Double, a: Double, w: Double, b: Double, z: Double)] = []
    private var centerX = 0.0, centerY = 0.0

    init(width: Int, height: Int, scene: Scene, seed: UInt64 = 0x6769_6E67_61) {
        self.width = width
        self.height = height
        self.scene = scene
        values = [Double](repeating: 0, count: width * height)
        var random = SeededRandom(seed: seed)
        switch scene {
        case .galaxy: prepareGalaxy()
        case .blackHole: prepareBlackHole(&random)
        }
    }

    // MARK: Galaxy

    private static let galaxyStride = 2  // r, θ

    private func prepareGalaxy() {
        let unit = Double(min(width, height)) / 2
        geometry = [Double](repeating: 0, count: width * height * Self.galaxyStride)
        let c = cos(-0.5), s = sin(-0.5)
        for yy in 0..<height {
            for xx in 0..<width {
                let x = (Double(xx) - Double(width) * 0.5) / unit, y = (Double(yy) - Double(height) * 0.5) / unit
                let u = x * c - y * s, w = (x * s + y * c) / 0.62
                let i = (yy * width + xx) * Self.galaxyStride
                geometry[i] = (u * u + w * w).squareRoot()
                geometry[i + 1] = atan2(w, u)
            }
        }
    }

    private func galaxy(_ index: Int, _ t: Double) -> Double {
        let r = geometry[index * Self.galaxyStride], theta = geometry[index * Self.galaxyStride + 1]
        guard r <= 1.05 else { return 0 }
        let arms = pow(0.5 + 0.5 * cos(2 * theta - 5.2 * log(r + 0.06) - t * Self.galaxySpin), 3)
        let edge = min(1, (1.05 - r) / 0.35)
        return min(1, exp(-r * 2.4) * (0.25 + 1.1 * arms) * edge + 1.15 * exp(-r * r * 60))
    }

    // MARK: Black hole

    private static let holeStride = 7  // x, y, rd, log rd, angle, rs, star

    private func prepareBlackHole(_ random: inout SeededRandom) {
        centerX = Double(width) * 0.5
        centerY = Double(height) * 0.52
        let half = Double(height) / 2
        geometry = [Double](repeating: 0, count: width * height * Self.holeStride)
        for yy in 0..<height {
            for xx in 0..<width {
                let x = (Double(xx) - centerX) / half, y = (Double(yy) - centerY) / half
                let v = y / Self.tilt, rs = (x * x + y * y).squareRoot(), rd = (x * x + v * v).squareRoot()
                // Lensing: the star seen here comes from a point pushed outwards (Einstein).
                let k = rs > Self.horizon ? 1 + 0.09 / (rs * rs) : 0
                let h = Self.hash((x * k * 60).rounded(.down), (y * k * 60).rounded(.down))
                let star = rs > Self.horizon * 1.1 && rs < 1.05 && h > 0.985 ? 0.28 + (h - 0.985) * 40 : 0
                let i = (yy * width + xx) * Self.holeStride
                geometry.replaceSubrange(i..<(i + Self.holeStride), with: [x, y, rd, log(rd + 0.001), atan2(v, x), rs, star])
            }
        }
        let count = min(700, Int((Double(width * height) * 0.03).rounded()))
        particles = (0..<count).map { _ in
            let r0 = Self.rIn * 0.9 + pow(random.unit(), 0.8) * (Self.rOut * 1.25 - Self.rIn)
            return (r0, random.unit() * 6.2832, 0.9 / pow(r0, 1.5), 0.35 + random.unit() * 0.55, (random.unit() - 0.5) * 0.05)
        }
    }

    private static func hash(_ a: Double, _ b: Double) -> Double {
        let x = sin(a * 127.1 + b * 311.7) * 43758.5453
        return x - x.rounded(.down)
    }

    private func blackHole(_ index: Int, _ t: Double) -> Double {
        let g = index * Self.holeStride
        let x = geometry[g], y = geometry[g + 1], rd = geometry[g + 2], lrd = geometry[g + 3], a = geometry[g + 4], rs = geometry[g + 5]
        let doppler = 0.5 - 0.5 * cos(a)
        var disk = 0.0
        if rd > Self.rIn && rd < Self.rOut {
            let f = 1 - (rd - Self.rIn) / (Self.rOut - Self.rIn)
            // Spirals pulling the gas inwards.
            let sw = 0.5 + 0.5 * sin(a * 3 + lrd * 7 + t * 2.2)
            let sw2 = 0.5 + 0.5 * sin(a * 7 - lrd * 11 + t * 3.1)
            disk = pow(f, 1.05) * (0.35 + 0.75 * doppler) * (0.45 + 0.4 * sw + 0.2 * sw2) * min(1, (rd - Self.rIn) / 0.06)
        }
        var lensed = 0.0
        let dr = abs(rs - 0.47)
        if dr < 0.17 && y < 0.05 {
            let la = atan2(y, x)
            lensed = pow(1 - dr / 0.17, 1.4) * (0.55 + 0.45 * (0.5 - 0.5 * cos(la))) * (0.7 + 0.3 * sin(la * 5 + t * 2.4 + rs * 20))
        }
        let ring = max(0, 1 - abs(rs - Self.horizon * 1.04) / 0.02)
        if rs < Self.horizon { return y > 0 && disk > 0 ? disk : 0 }
        let halo = 0.18 * exp(-(rs - Self.horizon) / 0.14) * (1 + 0.6 * pull)
        var back = min(1, max(0, (rs - 0.5) / 0.3))
        back = back * back * (3 - 2 * back)
        var v = max(y > 0 ? disk : max(disk * back, lensed), ring * (0.85 + 0.15 * sin(t * 3)), halo)
        v += geometry[g + 6] * (0.65 + 0.35 * sin(t * 1.7 + Double(index)))
        return min(v, 1)
    }

    /// The orbiting particles, with short trails; they collapse with `pull` and fly out on a burst.
    private func splat(_ t: Double) {
        pull += (pullTarget - pull) * 0.08
        let e = t - burstTime
        let burst = e > 0 && e < 2.2 ? sin(.pi * min(1, e / 2.2)) * exp(-e * 0.6) : 0
        let scale = Double(height) / 2
        for p in particles.indices {
            particles[p].a += particles[p].w * Self.frameInterval * (1 + 1.4 * pull)
            let q = particles[p]
            let r = q.r * (1 - 0.38 * pull) * (1 + 1.6 * burst * (0.6 + q.b))
            for k in 0..<3 {
                let angle = q.a - Double(k) * 0.05 * (1 + pull)
                let x = r * cos(angle), y = r * sin(angle) * Self.tilt + q.z
                if (x * x + y * y).squareRoot() < Self.horizon && sin(angle) < 0 { continue }  // behind the hole
                let px = Int((centerX + x * scale).rounded()), py = Int((centerY + y * scale).rounded())
                guard px >= 0, py >= 0, px < width, py < height else { continue }
                let add = q.b * (k == 0 ? 0.75 : 0.32 / Double(k)) * (0.6 + 0.6 * (0.5 - 0.5 * cos(angle)))
                values[py * width + px] = min(1, values[py * width + px] + add)
            }
        }
    }

    // MARK: Output

    /// Renders time `t` into RGBA bytes (fully transparent where the level is cosmos).
    func render(time t: Double, into pixels: inout [UInt32]) {
        if pixels.count != width * height { pixels = [UInt32](repeating: 0, count: width * height) }
        for i in 0..<values.count {
            values[i] = scene == .galaxy ? galaxy(i, t) : blackHole(i, t)
        }
        if scene == .blackHole { splat(t) }
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = Self.color(values[y * width + x], x: x, y: y)
            }
        }
    }

    /// Ordered dithering: floor(v·5 + threshold) picks one of the six colours.
    static func color(_ value: Double, x: Int, y: Int) -> UInt32 {
        let levels = palette.count - 1
        let level = min(max(Int((value * Double(levels) + bayer[(y & 3) * 4 + (x & 3)]).rounded(.down)), 0), levels)
        guard level > 0 else { return 0 }
        let (r, g, b) = palette[level]
        // Bytes R, G, B, A in memory on a little-endian Mac.
        return 0xFF00_0000 | UInt32(b) << 16 | UInt32(g) << 8 | UInt32(r)
    }

    func image(time t: Double, pixels: inout [UInt32]) -> CGImage? {
        render(time: t, into: &pixels)
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

/// A small deterministic generator (SplitMix64), so particles are the same on every launch and in tests.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func unit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

/// The scene in a view: only in Black espacial on the Mac (the tablet shows it on its brand
/// screens); ~24 fps while the window is visible and motion isn't reduced, else a still frame.
struct GingaDitherScene: View {
    @Environment(\.ginga) private var palette
    @Environment(\.gingaAnimates) private var animates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    let scene: DitherField.Scene
    /// The reference's ~24 fps; the main window's galaxy, on screen for hours, uses 12 (a slow
    /// spin looks the same and costs half: ~0.5 % of a core on an M4).
    var framesPerSecond: Double = 1 / DitherField.frameInterval
    @State private var renderer = DitherRenderer()

    var body: some View {
        if palette.isSpace {
            GeometryReader { geometry in
                let cell = 4 / max(displayScale, 1)  // one dithered pixel = 4 screen pixels
                let columns = max(8, Int(geometry.size.width / cell)), rows = max(8, Int(geometry.size.height / cell))
                let moving = animates && !reduceMotion
                TimelineView(.animation(minimumInterval: 1 / framesPerSecond, paused: !moving)) { context in
                    Canvas { graphics, size in
                        let t = moving ? context.date.timeIntervalSince(renderer.start) : 8
                        guard let image = renderer.frame(scene: scene, columns: columns, rows: rows, time: t) else { return }
                        // Nearest neighbour: the pixels stay square (the look), and scaling costs nothing.
                        graphics.draw(Image(decorative: image, scale: 1).interpolation(.none), in: CGRect(origin: .zero, size: size))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Keeps one field per size (its geometry is precomputed) and the pixel buffer across frames.
@MainActor
final class DitherRenderer {
    let start = Date()
    private var field: DitherField?
    private var pixels: [UInt32] = []

    func frame(scene: DitherField.Scene, columns: Int, rows: Int, time: Double) -> CGImage? {
        if field?.width != columns || field?.height != rows || field?.scene != scene {
            field = DitherField(width: columns, height: rows, scene: scene)
        }
        return field?.image(time: time, pixels: &pixels)
    }
}
