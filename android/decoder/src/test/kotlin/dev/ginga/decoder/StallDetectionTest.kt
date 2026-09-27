package dev.ginga.decoder

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StallDetectionTest {
    private val ms = 1_000_000L

    /** Seen on the Tab S11: after a stream error the MediaTek decoder kept every input buffer. */
    @Test
    fun aCodecHoldingEveryBufferForASecondIsStuck() {
        assertTrue(VideoDecoder.isStalled(nowNanos = 1_500 * ms, lastInputNanos = 400 * ms, freeInputs = 0))
    }

    @Test
    fun aBusyButHealthyCodecIsNot() {
        assertFalse(VideoDecoder.isStalled(nowNanos = 1_000 * ms, lastInputNanos = 990 * ms, freeInputs = 0))
    }

    /** A static screen sends nothing for minutes; the next frame finds free buffers. */
    @Test
    fun freeBuffersMeanItIsNotStuckHoweverLongTheScreenWasStill() {
        assertFalse(VideoDecoder.isStalled(nowNanos = 600_000 * ms, lastInputNanos = 0, freeInputs = 4))
    }
}
