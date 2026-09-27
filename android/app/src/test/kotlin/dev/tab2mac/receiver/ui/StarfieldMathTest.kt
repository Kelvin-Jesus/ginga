package dev.tab2mac.receiver.ui

import dev.tab2mac.receiver.ui.widget.StarfieldMath
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class StarfieldMathTest {
    @Test
    fun aboutPointTwoTwoStarsPerThousandDp2() {
        // Galaxy Tab S11 at 300 dpi (density 1.875): 1365 × 853 dp → ~256 stars.
        assertEquals(256, StarfieldMath.starCount(2560, 1600, 1.875f))
        // The same area at another density has the same sky.
        assertEquals(StarfieldMath.starCount(1000, 1000, 1f), StarfieldMath.starCount(2000, 2000, 2f))
        assertEquals(220, StarfieldMath.starCount(1000, 1000, 1f))
        assertEquals(0, StarfieldMath.starCount(0, 1600, 2f))
        assertEquals(0, StarfieldMath.starCount(100, 100, 0f))
    }

    @Test
    fun reducedMotionIsOneStillFrame() {
        val a = StarfieldMath.alpha(phase = 1f, speed = 1.3f, z = 0.5f, timeMs = 0f, reduced = true)
        val b = StarfieldMath.alpha(phase = 1f, speed = 1.3f, z = 0.5f, timeMs = 5_000f, reduced = true)
        assertEquals(a, b)
        assertEquals(0.7f * 0.7f, a, 1e-6f)
    }

    @Test
    fun twinkleStaysInRange() {
        for (t in 0..10_000 step 250) {
            val alpha = StarfieldMath.alpha(phase = 2f, speed = 2.2f, z = 1f, timeMs = t.toFloat(), reduced = false)
            assertTrue(alpha in 0.35f..0.9f + 1e-6f, "alpha $alpha at $t")
        }
    }

    @Test
    fun starsDriftRightAndWrap() {
        assertEquals(10f, StarfieldMath.driftX(10f, 0.7f, 0f, 2f, 100f))
        // 1000 ms × 0.012 dp/ms × 2 px/dp × (0.3 + 0.7) = 24 px.
        assertEquals(34f, StarfieldMath.driftX(10f, 0.7f, 1_000f, 2f, 100f), 1e-4f)
        assertEquals(14f, StarfieldMath.driftX(90f, 0.7f, 1_000f, 2f, 100f), 1e-4f)
    }

    @Test
    fun warpAcceleratesOverItsDuration() {
        assertEquals(1f, StarfieldMath.warpSpeed(0f))
        assertEquals(7.5f, StarfieldMath.warpSpeed(0.5f))
        assertEquals(27f, StarfieldMath.warpSpeed(1f))
        assertEquals(27f, StarfieldMath.warpSpeed(3f))
    }
}
