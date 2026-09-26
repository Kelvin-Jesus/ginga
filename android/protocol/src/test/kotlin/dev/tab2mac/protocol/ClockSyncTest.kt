package dev.tab2mac.protocol

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ClockSyncTest {

    @Test
    fun computesOffsetAndRoundTrip() {
        // Android pings at 1_000 (its clock). The Mac clock is 5_000_000 µs ahead; 100 µs each way,
        // 50 µs processing on the Mac.
        val t1 = 1_000L
        val t2 = t1 + 100 + 5_000_000
        val t3 = t2 + 50
        val t4 = t1 + 100 + 50 + 100
        val sample = ClockSyncEstimator.sample(t1, t2, t3, t4)
        assertEquals(5_000_000, sample.offsetUs)
        assertEquals(200, sample.roundTripUs)
    }

    @Test
    fun offsetIsResponderMinusInitiator() {
        // Mac clock = Android clock + 3 s, 5 ms each way, instant reply. The PING reaches the Mac at
        // Android time 15_000 = Mac time 3_015_000.
        val sample = ClockSyncEstimator.sample(t1 = 10_000, t2 = 3_015_000, t3 = 3_015_000, t4 = 20_000)
        assertEquals(3_000_000, sample.offsetUs)
        assertEquals(10_000, sample.roundTripUs)
        // A Mac timestamp T corresponds to Android time T − θ (§3.4).
        val macCaptureUs = 3_015_000L
        assertEquals(15_000, macCaptureUs - sample.offsetUs)
    }

    @Test
    fun usesTheLowestRoundTripSample() {
        val estimator = ClockSyncEstimator()
        estimator.add(0, 1_000_600, 1_000_600, 1_000) // δ 1000, θ 1_000_100
        estimator.add(0, 1_000_060, 1_000_060, 100) // δ 100, θ 1_000_010
        estimator.add(0, 1_000_400, 1_000_400, 700) // δ 700
        assertEquals(ClockSample(1_000_010, 100), estimator.best)
        assertEquals(700, estimator.latest?.roundTripUs)
    }

    @Test
    fun slidingWindowForgetsOldSamples() {
        val estimator = ClockSyncEstimator(windowSize = 4)
        estimator.add(0, 10, 10, 2) // δ 2, the best, will age out
        repeat(4) { estimator.add(0, 50, 50, 20) } // δ 20
        assertEquals(4, estimator.sampleCount)
        assertEquals(20, estimator.best?.roundTripUs)
    }

    @Test
    fun ignoresImpossibleSamples() {
        val estimator = ClockSyncEstimator()
        val bogus = estimator.add(t1 = 100, t2 = 0, t3 = 500, t4 = 200) // δ = 100 − 500 < 0
        assertEquals(-400, bogus.roundTripUs)
        assertEquals(0, estimator.sampleCount)
        assertNull(estimator.best)
        assertNull(estimator.latest)
    }

    @Test
    fun resetForgetsEverything() {
        val estimator = ClockSyncEstimator()
        estimator.add(0, 10, 10, 2)
        estimator.reset()
        assertNull(estimator.best)
        assertEquals(0, estimator.sampleCount)
    }
}
