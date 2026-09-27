package dev.tab2mac.receiver.ui

import dev.tab2mac.receiver.ui.widget.BlackHoleShader
import dev.tab2mac.receiver.ui.widget.BlackHoleTouch
import dev.tab2mac.receiver.ui.widget.DitherLoop
import dev.tab2mac.receiver.ui.widget.DitherShader
import dev.tab2mac.receiver.ui.widget.GalaxyShader
import dev.tab2mac.receiver.ui.widget.PixelSky
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * The port of design/ginga-design/reference/bundle.js (DitherSpace). The expected values come
 * from running the reference itself (node, 190×122 buffer, before the particles' splat).
 */
class DitherSpaceTest {
    private val w = 190
    private val h = 122
    private val points = listOf(95 to 63, 95 to 40, 60 to 63, 30 to 66, 150 to 60, 95 to 100, 120 to 50, 70 to 45, 10 to 10, 180 to 110)

    private fun values(shader: DitherShader, t: Double) = points.map { (x, y) -> shader.at(y * w + x, t) }

    private fun assertClose(expected: List<Double>, actual: List<Double>) {
        expected.zip(actual).forEachIndexed { i, (e, a) -> assertTrue(abs(e - a) < 2e-6, "point ${points[i]}: expected $e, got $a") }
    }

    /** Pixels per level (0–5) of the dithered values, without the splat. */
    private fun levels(shader: DitherShader, t: Double): List<Int> {
        val counts = IntArray(6)
        for (y in 0 until h) for (x in 0 until w) counts[DitherLoop.level(shader.at(y * w + x, t).toFloat().toDouble(), x, y)]++
        return counts.toList()
    }

    private fun assertLevels(expected: List<Int>, actual: List<Int>) {
        expected.zip(actual).forEach { (e, a) -> assertTrue(abs(e - a) <= 3, "levels: expected $expected, got $actual") }
    }

    @Test
    fun galaxyMatchesTheReference() {
        val galaxy = GalaxyShader().apply { init(w, h) }
        assertClose(listOf(1.0, 0.2402196, 0.2555415, 0.0, 0.0, 0.0068803, 0.2734038, 0.0774162, 0.0, 0.0), values(galaxy, 0.0))
        assertClose(listOf(1.0, 0.142183, 0.2145798, 0.0, 0.0, 0.0077385, 0.2000259, 0.0774171, 0.0, 0.0), values(galaxy, 1.3))
        assertLevels(listOf(19803, 2407, 549, 208, 86, 127), levels(galaxy, 0.0))
        assertLevels(listOf(19788, 2416, 571, 194, 77, 134), levels(galaxy, 1.3))
    }

    @Test
    fun blackHoleMatchesTheReference() {
        val hole = BlackHoleShader().apply { init(w, h) }
        assertClose(listOf(0.0, 0.1884598, 0.2554, 0.3770985, 0.0905603, 0.0183922, 0.4761584, 0.3213985, 0.0000104, 0.0000157), values(hole, 0.0))
        assertClose(listOf(0.0, 0.2195406, 0.1418515, 0.2722676, 0.1995405, 0.0183922, 0.3034226, 0.6022978, 0.0000104, 0.0000157), values(hole, 1.3))
        assertLevels(listOf(18523, 2929, 1037, 502, 165, 24), levels(hole, 0.0))
        assertLevels(listOf(18498, 2970, 1126, 436, 132, 18), levels(hole, 1.3))
    }

    @Test
    fun bayerThresholdsAndMidTone() {
        assertEquals((0..15).toList(), DitherLoop.BAYER.sorted())
        // A value halfway between two levels lights exactly half of every 4×4 tile.
        val mid = (2 + 0.5) / 5
        val tile = (0..3).flatMap { y -> (0..3).map { x -> DitherLoop.level(mid, x, y) } }
        assertEquals(8, tile.count { it == 2 })
        assertEquals(8, tile.count { it == 3 })
        // A quarter of the way from level 0: 4 of 16 pixels at level 1.
        val quarter = (0..3).flatMap { y -> (0..3).map { x -> DitherLoop.level(0.25 / 5, x, y) } }
        assertEquals(4, quarter.count { it == 1 })
        assertEquals(0, DitherLoop.level(-1.0, 0, 0))
        assertEquals(5, DitherLoop.level(1.0, 0, 0))
        assertEquals(5, DitherLoop.level(3.0, 3, 3))
    }

    @Test
    fun onlyTheSixColoursAndLevelZeroIsTransparent() {
        assertEquals(0, DitherLoop.PALETTE[0] ushr 24, "cosmos is transparent")
        assertTrue(DitherLoop.PALETTE.drop(1).all { it ushr 24 == 0xFF })
        assertEquals(0xFFFFC43D.toInt(), DitherLoop.PALETTE[5], "the hottest level is star gold")
        for (shader in listOf(BlackHoleShader(), GalaxyShader())) {
            val loop = DitherLoop(w, h, shader)
            for (t in listOf(0.0, 2.5, 30.0)) {
                loop.render(t)
                assertTrue(loop.pixels.all { it in DitherLoop.PALETTE })
                assertTrue(loop.pixels.any { it == DitherLoop.PALETTE[0] })
                assertTrue(loop.pixels.any { it == DitherLoop.PALETTE[5] }, "$shader at $t has gold")
            }
        }
    }

    @Test
    fun particlesAreSeededAndDeterministic() {
        val a = DitherLoop(w, h, BlackHoleShader())
        val b = DitherLoop(w, h, BlackHoleShader())
        assertEquals(minOf(700, Math.round(w * h * 0.03).toInt()), (a.shader as BlackHoleShader).particleCount)
        for (frame in 0 until 5) {
            a.render(frame * 0.042)
            b.render(frame * 0.042)
        }
        assertContentEquals(a.pixels, b.pixels)
        // A small buffer has fewer particles: 3% of its pixels.
        assertEquals(Math.round(60 * 40 * 0.03).toInt(), BlackHoleShader().apply { init(60, 40) }.particleCount)
    }

    @Test
    fun pullEasesTowardsItsTargetAndTheBurstPushesParticlesOut() {
        val shader = BlackHoleShader()
        val loop = DitherLoop(w, h, shader)
        shader.pullT = 1.0
        loop.render(0.0)
        assertEquals(0.08, shader.pull, 1e-12)
        loop.render(0.042)
        assertEquals(0.08 + (1 - 0.08) * 0.08, shader.pull, 1e-12)

        fun litOutside(l: DitherLoop, s: BlackHoleShader): Int {
            var n = 0
            for (y in 0 until h) for (x in 0 until w) {
                val dx = (x - s.cx) / (h / 2.0)
                val dy = (y - s.cy) / (h / 2.0)
                // Off the disc's plane and outside the stars' ring: only thrown particles get here.
                if (kotlin.math.abs(dy) > 0.45 && dx * dx + dy * dy > 1.05 * 1.05 && l.pixels[y * w + x] != DitherLoop.PALETTE[0]) n++
            }
            return n
        }
        val calm = BlackHoleShader()
        val burst = BlackHoleShader().apply { tb = 0.0 }
        val calmLoop = DitherLoop(w, h, calm)
        val burstLoop = DitherLoop(w, h, burst)
        calmLoop.render(1.1)
        burstLoop.render(1.1)
        assertEquals(0, litOutside(calmLoop, calm))
        assertTrue(litOutside(burstLoop, burst) > 20, "the burst throws particles outwards")
    }

    @Test
    fun theFingerCollapsesTheOrbitsAndATapOnTheHorizonBursts() {
        // 760 × 488 px hole: 1 at the horizon, 0 beyond 1.25 half-widths.
        assertEquals(1.0, BlackHoleTouch.pull(0f, 0f, 760f))
        assertEquals(0.25, BlackHoleTouch.pull(380f, 0f, 760f), 1e-9)
        assertEquals(0.0, BlackHoleTouch.pull(600f, 0f, 760f))
        assertEquals(0.0, BlackHoleTouch.pull(0f, 0f, 0f))
        // Horizon: R = 0.28 half-heights → 68 px on a 488 px hole, taps count up to 1.4 R.
        assertTrue(BlackHoleTouch.onHorizon(0f, 60f, 488f))
        assertTrue(BlackHoleTouch.onHorizon(90f, 0f, 488f))
        assertFalse(BlackHoleTouch.onHorizon(100f, 0f, 488f))
    }

    @Test
    fun galaxyTurns() {
        val loop = DitherLoop(80, 80, GalaxyShader())
        loop.render(0.0)
        val first = loop.pixels.copyOf()
        loop.render(4.0)
        assertFalse(first.contentEquals(loop.pixels))
    }

    @Test
    fun pixelSkyTwinklesWithItsOwnColours() {
        val sky = PixelSky(341, 213)
        assertEquals(Math.round(341 * 213 * 0.0048).toInt(), sky.starCount)
        sky.render(0.0)
        val lit = sky.pixels.count { it != 0 }
        assertTrue(lit in sky.starCount / 3..sky.starCount * 3, "lit $lit")
        assertTrue(sky.pixels.all { it == 0 || it in PixelSky.COLORS })
        val first = sky.pixels.copyOf()
        sky.render(1.0)
        assertFalse(first.contentEquals(sky.pixels), "twinkles")
        val again = PixelSky(341, 213).apply { render(0.0) }
        assertContentEquals(first, again.pixels, "seeded")
    }
}
