package dev.tab2mac.receiver.stats

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PercentilesTest {
    @Test
    fun nearestRankPercentiles() {
        val summary = assertNotNull(LatencySummary.of(doubleArrayOf(5.0, 1.0, 4.0, 2.0, 3.0)))
        assertEquals(3.0, summary.p50)
        assertEquals(5.0, summary.p95)
        assertEquals(5, summary.count)
        assertEquals(95.0, LatencySummary.percentile(DoubleArray(100) { it + 1.0 }, 95.0))
        assertNull(LatencySummary.of(DoubleArray(0)))
    }

    @Test
    fun windowKeepsOnlyTheMostRecentSamples() {
        val window = PercentileWindow(3)
        listOf(100.0, 1.0, 2.0, 3.0).forEach(window::add)
        assertEquals(3, window.count)
        assertEquals(3.0, window.summary()?.p95)
        window.clear()
        assertNull(window.summary())
    }

    @Test
    fun intervalSamplesStartOverAfterDraining() {
        val samples = IntervalSamples(initialCapacity = 1)
        repeat(10) { samples.add(it.toDouble()) }
        assertEquals(10, samples.drain()?.count)
        assertNull(samples.drain())
    }
}

class StreamStatsTest {
    private var now = 0L
    private val stats = StreamStats(nanoClock = { now }, decoderQueue = { 2 })

    @Test
    fun reportsCoverOneIntervalEach() {
        repeat(3) { stats.onVideoFrameReceived(it.toLong() + 10) }
        stats.onMessageReceived(1_000)
        stats.onFrameDecoded(10, 6_000_000)
        stats.onFrameDecoded(11, 8_000_000)
        stats.onFrameRendered(11)
        stats.onFrameDropped()
        stats.onInputDropped(2)
        stats.onEndToEndLatency(24_000, displayed = true)

        val report = stats.intervalReport(clockOffsetUs = -5, rttUs = 800)
        assertEquals(12, report.lastFrameId)
        assertEquals(3, report.framesReceived)
        assertEquals(2, report.framesDecoded)
        assertEquals(1, report.framesRendered)
        assertEquals(3, report.framesDropped)
        assertEquals(1_000, report.bytesReceived)
        assertEquals(6.0, report.decodeMs?.p50)
        assertEquals(8.0, report.decodeMs?.p95)
        assertEquals(24.0, report.endToEndMs?.p50)
        assertEquals(2, report.decoderQueue)
        assertEquals(-5, report.clockOffsetUs)
        assertEquals(800, report.rttUs)
        assertEquals(11, stats.lastDecodedFrameId)

        val next = stats.intervalReport(null, null)
        assertEquals(0, next.framesReceived)
        assertNull(next.decodeMs)
        assertNull(next.endToEndMs)
    }

    @Test
    fun displayedLatenciesReplaceReleaseTimeEstimates() {
        stats.onEndToEndLatency(10_000, displayed = false)
        stats.onEndToEndLatency(30_000, displayed = true)
        stats.onEndToEndLatency(12_000, displayed = false) // ignored from now on
        val rates = stats.overlayRates()
        assertTrue(rates.endToEndDisplayed)
        assertEquals(30.0, rates.endToEndMs?.p50)
    }

    @Test
    fun overlayRatesAreComputedOverElapsedTime() {
        stats.overlayRates()
        repeat(30) { stats.onFrameRendered(it.toLong()) }
        stats.onMessageReceived(500_000)
        now += 500_000_000 // 0.5 s
        val rates = stats.overlayRates()
        assertEquals(60.0, rates.fps, 1e-9)
        assertEquals(8_000.0, rates.bitrateKbps, 1e-9)
    }
}

class DiagnosticsFormatterTest {
    @Test
    fun formatsEveryLine() {
        val text = DiagnosticsFormatter.format(
            DiagnosticsSnapshot(
                connection = "streaming",
                width = 2560,
                height = 1600,
                codec = "hevc",
                decoderName = "c2.mtk.hevc.decoder",
                lowLatencyDecoder = true,
                rates = StreamRates(
                    fps = 59.94,
                    bitrateKbps = 38_512.4,
                    decodeMs = LatencySummary(6.1, 9.8, 60),
                    endToEndMs = LatencySummary(24.0, 31.5, 60),
                    endToEndDisplayed = true,
                    totals = StreamCounters(framesReceived = 3_600, framesDropped = 12),
                ),
                rttUs = 850,
                clockOffsetUs = -1_234_567,
            ),
        )
        assertEquals(
            """
            Tab2Mac · streaming
            2560×1600 hevc · c2.mtk.hevc.decoder (low-latency)
            59.9 fps · 38,512 kbps
            decode p50 6.1 ms · p95 9.8 ms
            end-to-end p50 24.0 ms · p95 31.5 ms
            dropped 12 · received 3,600 · input 0
            RTT 0.85 ms · clock offset -1,234,567 µs
            """.trimIndent(),
            text,
        )
    }

    @Test
    fun showsPanelRefreshBatteryAndErrors() {
        val text = DiagnosticsFormatter.format(
            DiagnosticsSnapshot(
                connection = "streaming", width = null, height = null, codec = null, decoderName = null,
                lowLatencyDecoder = false, rates = null, rttUs = null, clockOffsetUs = null,
                displayRefreshHz = 60.0f, votedFrameRate = 60f,
                power = PowerSample(currentMa = -850, voltageMv = 4_000, charging = false),
                error = "no hardware decoder for video/hevc",
            ),
        )
        assertTrue("⚠ no hardware decoder for video/hevc" in text, text)
        assertTrue("panel 60 Hz (voted 60)" in text, text)
        assertTrue("battery -850 mA · -3.40 W" in text, text)
    }

    @Test
    fun batteryCurrentIsNormalisedToMilliamps() {
        assertEquals(-850, PowerMonitor.normalizeToMilliamps(-850_000))
        assertEquals(1_200, PowerMonitor.normalizeToMilliamps(1_200))
        assertEquals(null, PowerSample(100, null, true).watts)
    }

    @Test
    fun showsDashesBeforeDataArrives() {
        val text = DiagnosticsFormatter.format(DiagnosticsSnapshot("connecting", null, null, null, null, false, null, null, null))
        assertEquals("Tab2Mac · connecting\n— —\nRTT — · clock offset —", text)
    }
}
