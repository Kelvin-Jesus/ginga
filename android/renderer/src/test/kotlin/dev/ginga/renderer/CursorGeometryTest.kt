package dev.ginga.renderer

import kotlin.test.Test
import kotlin.test.assertEquals

class CursorGeometryTest {
    @Test
    fun theHotspotLandsOnTheNormalizedPosition() {
        // 2560×1600 stream shown at 1280×800 inside a view letterboxed 40 px from the top.
        val rect = VideoRect(0, 40, 1280, 800)
        val scale = CursorGeometry.scale(rect.width, streamWidth = 2560)
        assertEquals(0.5f, scale)
        // Centre of the display, hotspot (8, 6) stream pixels → (4, 3) view pixels up-left.
        assertEquals(640f - 4f, CursorGeometry.left(32768, 8, rect, scale), 0.02f)
        assertEquals(40f + 400f - 3f, CursorGeometry.top(32768, 6, rect, scale), 0.02f)
    }

    @Test
    fun theCornersMapToTheVideoEdges() {
        val rect = VideoRect(100, 0, 2000, 1250)
        val scale = CursorGeometry.scale(rect.width, streamWidth = 2000)
        assertEquals(1f, scale)
        assertEquals(100f, CursorGeometry.left(0, 0, rect, scale))
        assertEquals(2100f, CursorGeometry.left(65535, 0, rect, scale))
        assertEquals(1250f, CursorGeometry.top(65535, 0, rect, scale))
    }

    @Test
    fun anUnknownStreamSizeDrawsAtOneToOne() {
        assertEquals(1f, CursorGeometry.scale(1280, 0))
    }
}
