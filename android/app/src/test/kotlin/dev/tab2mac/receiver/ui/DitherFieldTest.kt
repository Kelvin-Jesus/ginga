package dev.tab2mac.receiver.ui

import dev.tab2mac.receiver.ui.widget.DitherField
import dev.tab2mac.receiver.ui.widget.DitherField.Palette
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DitherFieldTest {
    private val blueRamp = intArrayOf(Palette.BLACK, Palette.DEEP, Palette.COBALT, Palette.NIGHT, Palette.PALE, Palette.WHITE)

    @Test
    fun bayerMatrixIsAPermutationOfSixteenLevels() {
        assertEquals((0..15).toList(), DitherField.BAYER_4.sorted())
        val thresholds = (0..3).flatMap { y -> (0..3).map { x -> DitherField.threshold(x, y) } }
        assertTrue(thresholds.all { it > 0f && it < 1f })
        // It tiles every four cells.
        assertEquals(DitherField.threshold(1, 2), DitherField.threshold(5, 6))
    }

    @Test
    fun quantizationDithersBetweenNeighbouringColoursInProportion() {
        assertEquals(Palette.BLACK, DitherField.quantize(0f, blueRamp, 0.5f))
        assertEquals(Palette.WHITE, DitherField.quantize(1f, blueRamp, 0.01f))
        assertEquals(Palette.WHITE, DitherField.quantize(2f, blueRamp, 0.99f))
        // Halfway between cobalt (2) and night cobalt (3): half of a 4×4 tile each.
        val value = 2.5f / (blueRamp.size - 1)
        val tile = (0..3).flatMap { y -> (0..3).map { x -> DitherField.quantize(value, blueRamp, DitherField.threshold(x, y)) } }
        assertEquals(8, tile.count { it == Palette.NIGHT })
        assertEquals(8, tile.count { it == Palette.COBALT })
        // A quarter of the way: 4 of 16.
        val quarter = (0..3).flatMap { y -> (0..3).map { x -> DitherField.quantize(0.25f / 5f, blueRamp, DitherField.threshold(x, y)) } }
        assertEquals(4, quarter.count { it == Palette.DEEP })
    }

    @Test
    fun onlyPaletteColoursAreDrawn() {
        for (scene in DitherField.Scene.entries) {
            val field = DitherField(120, 60, scene)
            for (t in listOf(0L, 12_345L, 99_000L)) {
                field.render(t, shimmer = (t % 4).toInt())
                assertTrue(field.pixels.all { it in Palette.ALL }, "$scene at $t")
            }
        }
    }

    @Test
    fun galaxyHasAGoldCoreDarkCornersAndTurnsSlowly() {
        val field = DitherField(120, 60, DitherField.Scene.GALAXY)
        field.render(0)
        // The core: gold, white at its hottest.
        val core = (28..31).flatMap { y -> (56..63).map { x -> field.pixels[y * 120 + x] } }
        assertTrue(core.all { it == Palette.GOLD || it == Palette.WHITE }, "core")
        assertTrue(core.count { it == Palette.GOLD } > 10)
        assertEquals(Palette.BLACK, field.pixels[0])
        assertEquals(Palette.BLACK, field.pixels[59 * 120 + 119])
        val start = field.pixels.copyOf()
        field.render(0)
        assertContentEquals(start, field.pixels, "deterministic")
        // A full turn takes two minutes: after a quarter the arms moved; after a turn they are back.
        field.render(DitherField.GALAXY_TURN_MS / 4)
        assertFalse(start.contentEquals(field.pixels))
        field.render(DitherField.GALAXY_TURN_MS)
        assertContentEquals(start, field.pixels)
    }

    @Test
    fun blackHoleIsDarkInsideAndBrighterOnTheApproachingSide() {
        val field = DitherField(120, 60, DitherField.Scene.BLACK_HOLE)
        field.render(0)
        // Just above the centre: inside the shadow (the disc crosses the middle row).
        assertEquals(Palette.BLACK, field.pixels[24 * 120 + 60])
        fun brightness(color: Int) = ((color shr 16) and 255) + ((color shr 8) and 255) + (color and 255)
        val middle = 30
        val left = (middle - 3..middle + 3).sumOf { y -> (8 until 40).sumOf { x -> brightness(field.pixels[y * 120 + x]) } }
        val right = (middle - 3..middle + 3).sumOf { y -> (80 until 112).sumOf { x -> brightness(field.pixels[y * 120 + x]) } }
        assertTrue(left > right * 1.2, "left $left right $right")
        // The disc's texture drifts.
        val start = field.pixels.copyOf()
        field.render(DitherField.DISK_DRIFT_MS / 8)
        assertFalse(start.contentEquals(field.pixels))
    }

    @Test
    fun shimmerMovesTheDitherNotThePicture() {
        val field = DitherField(120, 60, DitherField.Scene.GALAXY)
        field.render(5_000, shimmer = 0)
        val a = field.pixels.copyOf()
        field.render(5_000, shimmer = 1)
        val changed = a.indices.filter { a[it] != field.pixels[it] }
        // Only dithered cells flip, between neighbouring colours; black sky and solid areas stay.
        assertTrue(changed.size in 1 until a.size / 3, "changed ${changed.size} cells")
        assertEquals(Palette.BLACK, field.pixels[0])
    }
}
