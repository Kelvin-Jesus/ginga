import Testing
@testable import GingaApp

@Suite("DitherField")
struct DitherFieldTests {
    static let allowed: Set<UInt32> = Set(DitherField.palette.dropFirst().map { r, g, b in
        0xFF00_0000 | UInt32(b) << 16 | UInt32(g) << 8 | UInt32(r)
    } + [0])

    /// Every pixel is transparent (the darkest level, cosmos) or one of the five other brand
    /// colours: dithering picks levels, it never blends.
    @Test func pixelsAreFromThePalette() {
        for scene in [DitherField.Scene.galaxy, .blackHole] {
            var pixels: [UInt32] = []
            DitherField(width: 190, height: 122, scene: scene).render(time: 12, into: &pixels)
            #expect(pixels.count == 190 * 122)
            #expect(pixels.allSatisfy(Self.allowed.contains))
            let lit = pixels.filter { $0 != 0 }.count
            #expect(lit > 500 && lit < 190 * 122 * 2 / 3)  // a scene on a mostly dark sky
        }
    }

    /// The hottest level is gold (star): the galaxy's core, the disk's approaching side.
    @Test func theHottestLevelIsGold() {
        let (r, g, b) = DitherField.palette[5]
        let gold = 0xFF00_0000 | UInt32(b) << 16 | UInt32(g) << 8 | UInt32(r)
        var pixels: [UInt32] = []
        DitherField(width: 120, height: 80, scene: .galaxy).render(time: 0, into: &pixels)
        #expect(pixels[40 * 120 + 60] == gold)  // the core
    }

    /// Ordered dithering: a flat value between two levels becomes a pattern of exactly those two.
    @Test func midTonesDither() {
        let colors = Set((0..<4).flatMap { y in (0..<4).map { x in DitherField.color(0.5, x: x, y: y) } })
        #expect(colors.count == 2)
        #expect(DitherField.color(0, x: 0, y: 0) == 0)
    }

    /// The particles are seeded: two fields render the same frames.
    @Test func deterministic() {
        var a: [UInt32] = [], b: [UInt32] = []
        let one = DitherField(width: 90, height: 60, scene: .blackHole), two = DitherField(width: 90, height: 60, scene: .blackHole)
        for t in [0.0, 0.042, 0.084] {
            one.render(time: t, into: &a)
            two.render(time: t, into: &b)
        }
        #expect(a == b)
    }

    /// Inside the horizon only the disk's near side shows; the far side is hidden by the hole.
    @Test func theHorizonIsDark() {
        var pixels: [UInt32] = []
        let field = DitherField(width: 190, height: 122, scene: .blackHole)
        field.render(time: 3, into: &pixels)
        let cx = 95, cy = Int(122 * 0.52)
        let above = (cy - 12..<cy - 4).flatMap { y in (cx - 4..<cx + 4).map { pixels[y * 190 + $0] } }
        #expect(above.filter { $0 != 0 }.count <= 2)
    }
}
