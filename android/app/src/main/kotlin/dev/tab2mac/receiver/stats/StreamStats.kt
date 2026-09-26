package dev.tab2mac.receiver.stats

import dev.tab2mac.protocol.ReceiverReport
import dev.tab2mac.receiver.session.SessionStats
import dev.tab2mac.renderer.FrameTimingListener
import java.util.concurrent.atomic.AtomicLong

/** Cumulative counters at one instant. */
data class StreamCounters(
    val framesReceived: Long = 0,
    val bytesReceived: Long = 0,
    val framesDecoded: Long = 0,
    val framesRendered: Long = 0,
    val framesDropped: Long = 0,
    /** INPUT messages sent to the Mac. */
    val inputMessages: Long = 0,
) {
    operator fun minus(other: StreamCounters) = StreamCounters(
        framesReceived - other.framesReceived,
        bytesReceived - other.bytesReceived,
        framesDecoded - other.framesDecoded,
        framesRendered - other.framesRendered,
        framesDropped - other.framesDropped,
        inputMessages - other.inputMessages,
    )
}

/** What the diagnostics overlay shows about the stream itself. */
data class StreamRates(
    val fps: Double,
    val bitrateKbps: Double,
    val decodeMs: LatencySummary?,
    val endToEndMs: LatencySummary?,
    val endToEndDisplayed: Boolean,
    val totals: StreamCounters,
)

/**
 * Receiver statistics, fed from the network (session thread), the decoder and the renderer
 * (decoder thread). RECEIVER_REPORTs use per-interval counters and latencies; the overlay uses
 * rates since its previous refresh and a window of recent latencies.
 */
class StreamStats(
    private val nanoClock: () -> Long = System::nanoTime,
    private val decoderQueue: () -> Int = { 0 },
) : SessionStats, FrameTimingListener {
    private val framesReceived = AtomicLong()
    private val bytesReceived = AtomicLong()
    private val framesDecoded = AtomicLong()
    private val framesRendered = AtomicLong()
    private val framesDropped = AtomicLong()
    private val inputMessages = AtomicLong()

    // Primitives with a -1 sentinel: updated per frame, so no boxing.
    @Volatile
    private var lastFrameIdValue = NONE

    @Volatile
    private var lastDecodedFrameIdValue = NONE

    override val lastDecodedFrameId: Long? get() = lastDecodedFrameIdValue.takeIf { it != NONE }

    private val lock = Any()
    private val decodeInterval = IntervalSamples()
    private val endToEndInterval = IntervalSamples()
    private val decodeRecent = PercentileWindow(RECENT_SAMPLES)
    private val endToEndRecent = PercentileWindow(RECENT_SAMPLES)
    private var endToEndDisplayed = false
    private var reportBaseline = StreamCounters()
    private var overlayBaseline = StreamCounters()
    private var overlayBaselineAt = nanoClock()

    /** Starts over, e.g. for a new session. */
    fun reset() {
        synchronized(lock) {
            framesReceived.set(0)
            bytesReceived.set(0)
            framesDecoded.set(0)
            framesRendered.set(0)
            framesDropped.set(0)
            inputMessages.set(0)
            lastFrameIdValue = NONE
            lastDecodedFrameIdValue = NONE
            decodeInterval.drain()
            endToEndInterval.drain()
            decodeRecent.clear()
            endToEndRecent.clear()
            endToEndDisplayed = false
            reportBaseline = StreamCounters()
            overlayBaseline = StreamCounters()
            overlayBaselineAt = nanoClock()
        }
    }

    // SessionStats (session thread)

    override fun onMessageReceived(wireSize: Int) {
        bytesReceived.addAndGet(wireSize.toLong())
    }

    override fun onVideoFrameReceived(frameId: Long) {
        framesReceived.incrementAndGet()
        lastFrameIdValue = frameId
    }

    override fun intervalReport(clockOffsetUs: Long?, rttUs: Long?): ReceiverReport {
        val now = counters()
        val (delta, decode, endToEnd) = synchronized(lock) {
            val delta = now - reportBaseline
            reportBaseline = now
            Triple(delta, decodeInterval.drain(), endToEndInterval.drain())
        }
        return ReceiverReport(
            lastFrameId = lastFrameIdValue.takeIf { it != NONE },
            framesReceived = delta.framesReceived.toInt(),
            framesDecoded = delta.framesDecoded.toInt(),
            framesRendered = delta.framesRendered.toInt(),
            framesDropped = delta.framesDropped.toInt(),
            bytesReceived = delta.bytesReceived,
            decodeMs = decode?.let { ReceiverReport.Percentiles(round2(it.p50), round2(it.p95)) },
            endToEndMs = endToEnd?.let { ReceiverReport.Percentiles(round2(it.p50), round2(it.p95)) },
            decoderQueue = decoderQueue(),
            clockOffsetUs = clockOffsetUs,
            rttUs = rttUs,
        )
    }

    // FrameTimingListener (decoder thread)

    override fun onFrameDecoded(frameId: Long, decodeLatencyNanos: Long) {
        framesDecoded.incrementAndGet()
        if (frameId >= 0) lastDecodedFrameIdValue = frameId
        if (decodeLatencyNanos >= 0) {
            val ms = decodeLatencyNanos / 1_000_000.0
            synchronized(lock) {
                decodeInterval.add(ms)
                decodeRecent.add(ms)
            }
        }
    }

    override fun onFrameRendered(frameId: Long) {
        framesRendered.incrementAndGet()
    }

    override fun onFrameDropped() {
        framesDropped.incrementAndGet()
    }

    override fun onEndToEndLatency(latencyUs: Long, displayed: Boolean) {
        val ms = latencyUs / 1_000.0
        synchronized(lock) {
            if (displayed && !endToEndDisplayed) {
                // Switch from release-time estimates to real display times.
                endToEndDisplayed = true
                endToEndRecent.clear()
            }
            if (displayed != endToEndDisplayed) return
            endToEndInterval.add(ms)
            endToEndRecent.add(ms)
        }
    }

    /** Encoded frames discarded before decoding (no decoder, waiting for a keyframe, backlog). */
    fun onInputDropped(count: Int) {
        framesDropped.addAndGet(count.toLong())
    }

    /** INPUT messages queued for the Mac. */
    fun onInputSent(count: Int) {
        inputMessages.addAndGet(count.toLong())
    }

    /** Rates since the previous call, for the overlay (UI thread). */
    fun overlayRates(): StreamRates {
        val now = counters()
        val at = nanoClock()
        return synchronized(lock) {
            val delta = now - overlayBaseline
            val seconds = ((at - overlayBaselineAt) / 1e9).coerceAtLeast(1e-3)
            overlayBaseline = now
            overlayBaselineAt = at
            StreamRates(
                fps = delta.framesRendered / seconds,
                bitrateKbps = delta.bytesReceived * 8 / 1_000.0 / seconds,
                decodeMs = decodeRecent.summary(),
                endToEndMs = endToEndRecent.summary(),
                endToEndDisplayed = endToEndDisplayed,
                totals = now,
            )
        }
    }

    private fun counters() = StreamCounters(
        framesReceived.get(), bytesReceived.get(), framesDecoded.get(), framesRendered.get(), framesDropped.get(),
        inputMessages.get(),
    )

    private companion object {
        const val NONE = -1L

        /** About two seconds at 120 fps. */
        const val RECENT_SAMPLES = 240

        fun round2(value: Double): Double = Math.round(value * 100) / 100.0
    }
}
