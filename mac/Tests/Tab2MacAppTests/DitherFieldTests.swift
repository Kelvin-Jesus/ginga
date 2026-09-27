import Testing
@testable import Tab2MacApp

@Suite("DitherField")
struct DitherFieldTests {
    /// Every pixel is transparent (the black shows) or one of the palette's colors: dithering
    /// picks levels, it never blends.
    @Test func pixelsAreFromThePalette() {
        let allowed = Set((DitherField.blues.dropFirst() + [DitherField.gold]).map { rgb -> UInt32 in
            0xFF00_0000 | ((rgb & 0xFF) << 16) | (((rgb >> 8) & 0xFF) << 8) | ((rgb >> 16) & 0xFF)
        } + [0])
        for scene in [DitherField.Scene.galaxy, .blackHole] {
            var pixels: [UInt32] = []
            DitherField(width: 80, height: 40, scene: scene).render(time: 12, into: &pixels)
            #expect(pixels.count == 80 * 40)
            #expect(pixels.allSatisfy(allowed.contains))
            #expect(pixels.filter { $0 != 0 }.count > 80)  // something is drawn
            #expect(pixels.filter { $0 != 0 }.count < 80 * 40 / 2)  // mostly black: it's scenery
        }
    }

    /// Ordered dithering: a flat mid intensity becomes a pattern of the two nearest levels.
    @Test func midTonesDither() {
        let colors = Set((0..<4).flatMap { y in (0..<4).map { x in DitherField.color(intensity: 0.5, hot: false, x: x, y: y) } })
        #expect(colors.count == 2)
        #expect(DitherField.color(intensity: 0, hot: false, x: 0, y: 0) == 0)
    }

    /// The galaxy turns slowly: one turn takes `galaxyTurn` seconds.
    @Test func theGalaxyTurnsSlowly() {
        var a: [UInt32] = [], b: [UInt32] = []
        let field = DitherField(width: 60, height: 30, scene: .galaxy)
        field.render(time: 0, into: &a)
        field.render(time: DitherField.galaxyTurn / 2, into: &b)  // half a turn: two arms map onto each other
        let same = zip(a, b).filter { $0 == $1 }.count
        #expect(Double(same) / Double(a.count) > 0.9)
    }
}
