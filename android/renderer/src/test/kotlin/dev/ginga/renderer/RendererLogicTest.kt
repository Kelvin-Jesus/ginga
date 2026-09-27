package dev.ginga.renderer

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AspectFitTest {
    @Test
    fun exactFitFillsTheContainer() {
        assertEquals(VideoRect(0, 0, 2560, 1600), AspectFit.fit(2560, 1600, 2560, 1600))
        assertEquals(VideoRect(0, 0, 1280, 800), AspectFit.fit(2560, 1600, 1280, 800))
    }

    @Test
    fun landscapeStreamInAPortraitContainerIsLetterboxedTopAndBottom() {
        assertEquals(VideoRect(0, 780, 1600, 1000), AspectFit.fit(2560, 1600, 1600, 2560))
    }

    @Test
    fun portraitStreamInALandscapeContainerIsPillarboxed() {
        assertEquals(VideoRect(780, 0, 1000, 1600), AspectFit.fit(1600, 2560, 2560, 1600))
    }

    @Test
    fun roundsToTheNearestPixelAndCentres() {
        // 1920×1080 into 2560×1600: height 1440, 80 px bars.
        assertEquals(VideoRect(0, 80, 2560, 1440), AspectFit.fit(1920, 1080, 2560, 1600))
        // 16:9 into 1000×1000: 562.5 rounds to 563.
        assertEquals(VideoRect(0, 218, 1000, 563), AspectFit.fit(1600, 900, 1000, 1000))
    }

    @Test
    fun unknownVideoSizeFillsAndEmptyContainerIsEmpty() {
        assertEquals(VideoRect(0, 0, 2560, 1600), AspectFit.fit(0, 0, 2560, 1600))
        assertTrue(AspectFit.fit(2560, 1600, 0, 1600).isEmpty)
    }
}

class LatestFrameGateTest {
    @Test
    fun newerFramesSupersedeWaitingOnes() {
        val gate = LatestFrameGate<String>()
        assertNull(gate.offer("f1"))
        assertEquals("f1", gate.offer("f2"))
        assertEquals("f2", gate.offer("f3"))
        assertTrue(gate.hasFrame)
        assertEquals("f3", gate.take())
        assertFalse(gate.hasFrame)
        assertNull(gate.take())
    }

    @Test
    fun aBurstRendersOnlyTheNewestFrame() {
        val gate = LatestFrameGate<Int>()
        val dropped = (1..5).mapNotNull { gate.offer(it) }
        assertEquals(listOf(1, 2, 3, 4), dropped)
        assertEquals(5, gate.take())
    }
}

class EndToEndTest {
    @Test
    fun convertsTheMacCaptureTimeIntoTheAndroidClock() {
        // θ = Mac − Android = 3 s. Captured at Mac 3_015_000 µs = Android 15_000 µs; shown at 40_000 µs.
        assertEquals(25_000, EndToEnd.latencyUs(renderTimeNanos = 40_000_000, captureTimeUs = 3_015_000, clockOffsetUs = 3_000_000))
        // A negative offset (Mac clock behind) works the same way.
        assertEquals(10_000, EndToEnd.latencyUs(renderTimeNanos = 1_010_000_000, captureTimeUs = 500_000, clockOffsetUs = -500_000))
    }
}
