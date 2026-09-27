package dev.ginga.renderer

import android.os.Handler
import android.os.Looper
import dev.ginga.decoder.DecodedFrame
import dev.ginga.decoder.DecodedFrameSink

/**
 * Holds at most one decoded frame (§4: receivers never queue more than one decoded frame for
 * display). A newer frame supersedes the one waiting, which is then dropped. Not thread-safe.
 */
class LatestFrameGate<T : Any> {
    private var waiting: T? = null

    /** Whether a frame is waiting. */
    val hasFrame: Boolean get() = waiting != null

    /** Makes [frame] the waiting frame; returns the frame it superseded, which must be dropped. */
    fun offer(frame: T): T? {
        val superseded = waiting
        waiting = frame
        return superseded
    }

    /** Takes the waiting frame, if any. */
    fun take(): T? {
        val frame = waiting
        waiting = null
        return frame
    }
}

/** End-to-end latency (§3.2): `renderTime − (captureTimeUs − θ)`, θ = Mac clock − Android clock. */
object EndToEnd {
    fun latencyUs(renderTimeNanos: Long, captureTimeUs: Long, clockOffsetUs: Long): Long =
        renderTimeNanos / 1_000 - (captureTimeUs - clockOffsetUs)
}

/** The current clock-sync estimate θ (µs), or null before the first PONG. Must be thread-safe. */
fun interface ClockOffsetProvider {
    fun offsetUs(): Long?
}

/** Per-frame timing for statistics. Called on the decoder's callback thread. */
interface FrameTimingListener {
    /**
     * A frame left the decoder; [decodeLatencyNanos] is queue → output, or -1 when unknown or not
     * sampled this frame (see [LatestFramePresenter.timingSampleInterval]).
     */
    fun onFrameDecoded(frameId: Long, decodeLatencyNanos: Long)

    /** A frame was sent to the display. */
    fun onFrameRendered(frameId: Long)

    /** A decoded frame was superseded before it could be shown. */
    fun onFrameDropped()

    /** Capture on the Mac → on screen, µs. [displayed] is false for the release-time estimate. */
    fun onEndToEndLatency(latencyUs: Long, displayed: Boolean)
}

/**
 * The renderer's [DecodedFrameSink]: latest frame wins, released with
 * `releaseOutputBuffer(index, System.nanoTime())` so it shows at the next vsync.
 *
 * Each decoded frame is parked in a [LatestFrameGate] and a flush is posted to the decoder's own
 * looper. Output callbacks that are already queued run first, so a burst collapses to its newest
 * frame and the older ones are dropped without ever reaching the display.
 *
 * End-to-end latency uses the codec's frame-rendered callbacks (actual display time). Until the
 * first one arrives, the release time is used as a lower-bound estimate.
 */
class LatestFramePresenter(
    private val clockOffset: ClockOffsetProvider,
    private val timing: FrameTimingListener,
) : DecodedFrameSink {
    private val gate = LatestFrameGate<DecodedFrame>()
    private var handler: Handler? = null
    private var flushPosted = false
    private var decodedCount = 0L
    private var renderedCount = 0L

    @Volatile
    private var displayTimesAvailable = false

    /**
     * Record latencies for one frame in this many (counters still count every frame). 1 while
     * someone looks at the numbers; a few while only the Mac's once-a-second report needs them.
     */
    @Volatile
    var timingSampleInterval: Int = 1
        set(value) {
            field = value.coerceAtLeast(1)
        }

    private val flush = Runnable {
        flushPosted = false
        val frame = gate.take() ?: return@Runnable
        val now = System.nanoTime()
        frame.render(now)
        timing.onFrameRendered(frame.frameId)
        if (!displayTimesAvailable && sampled(renderedCount++)) {
            val offset = clockOffset.offsetUs()
            if (offset != null) timing.onEndToEndLatency(EndToEnd.latencyUs(now, frame.presentationTimeUs, offset), displayed = false)
        }
    }

    private fun sampled(count: Long): Boolean = count % timingSampleInterval == 0L

    override fun onFrameDecoded(frame: DecodedFrame) {
        timing.onFrameDecoded(frame.frameId, if (sampled(decodedCount++)) frame.decodeLatencyNanos else -1)
        gate.offer(frame)?.let { superseded ->
            superseded.drop()
            timing.onFrameDropped()
        }
        if (!flushPosted) {
            val looper = Looper.myLooper()
            if (looper == null) {
                // Not on a looper thread (never the case with VideoDecoder): render right away.
                flush.run()
                return
            }
            val target = handler?.takeIf { it.looper == looper } ?: Handler(looper).also { handler = it }
            flushPosted = true
            target.post(flush)
        }
    }

    override fun onFrameRendered(presentationTimeUs: Long, renderTimeNanos: Long) {
        if (!displayTimesAvailable) {
            displayTimesAvailable = true
            RendererLog.i("render.display-times-available")
        }
        if (!sampled(renderedCount++)) return
        val offset = clockOffset.offsetUs() ?: return
        timing.onEndToEndLatency(EndToEnd.latencyUs(renderTimeNanos, presentationTimeUs, offset), displayed = true)
    }
}
