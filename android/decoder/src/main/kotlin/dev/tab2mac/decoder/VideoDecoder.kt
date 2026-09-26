package dev.tab2mac.decoder

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.os.Process
import android.view.Surface
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * MediaCodec in asynchronous mode, decoding straight into a [Surface] (zero-copy: the CPU never
 * touches decoded pixels) with the lowest latency the device allows (research §4).
 *
 * - Input: frames arrive on any thread via [submit] and are copied into a codec input buffer as
 *   soon as one is free; the network buffer is handed back right after ([EncodedFrame.consumed]).
 *   Until a keyframe arrives, delta frames are dropped and a keyframe requested. A keyframe
 *   supersedes frames still waiting for input buffers.
 * - Backlog: frames wait for input buffers only briefly. When the oldest waiting delta frame is
 *   more than two frame intervals old, the decoder is behind: the backlog is dropped and a
 *   keyframe requested, instead of letting latency pile up.
 * - Output: every decoded buffer goes to the [DecodedFrameSink] (the renderer), which decides
 *   what to show. Decode latency (queue → output) is measured per frame without allocating.
 * - Errors: the codec is recreated with the same plan (at most [MAX_RECOVERIES] times per 10 s)
 *   and a keyframe is requested. A frame larger than the input buffers restarts the codec with
 *   twice that size.
 *
 * Threading: callbacks run on a dedicated display-priority thread that sleeps when no frames
 * arrive; [start]/[stop] may be called from any thread and are serialised. The codec is never
 * stopped while the state lock is held, so callbacks can't deadlock against [stop].
 */
class VideoDecoder(
    private val sink: DecodedFrameSink,
    private val listener: Listener,
) {
    /** Events for the session. Called on internal threads, never while the state lock is held. */
    interface Listener {
        /** The stream can't continue without a keyframe. */
        fun onKeyframeNeeded(reason: KeyframeNeed)

        /** Encoded frames were discarded before decoding. */
        fun onInputDropped(count: Int, reason: String) {}

        fun onDecoderStarted(plan: DecoderPlan) {}

        /** The decoded picture size changed (after cropping). */
        fun onOutputSizeChanged(width: Int, height: Int) {}

        /** Unrecoverable: no configuration works, or errors keep recurring. */
        fun onDecoderFailed(message: String) {}
    }

    /** Why a keyframe is needed. */
    enum class KeyframeNeed {
        /** A new decoder (or surface) is waiting for its first keyframe. */
        STARTUP,

        /** The codec failed and was recreated. */
        DECODER_ERROR,

        /** Frames were dropped because the decoder fell behind or a frame didn't fit. */
        LOSS,
    }

    private val callbackThread = HandlerThread("t2m-decoder", Process.THREAD_PRIORITY_URGENT_DISPLAY).apply { start() }
    private val callbackHandler = Handler(callbackThread.looper)
    private val control = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "t2m-decoder-control") }

    /** Serialises start/stop/recovery. */
    private val controlLock = Any()

    /** Guards the state shared with codec callbacks. */
    private val lock = Any()
    private var codec: MediaCodec? = null
    private var generation = 0
    private var activePlan: DecoderPlan? = null
    private var activeSurface: Surface? = null
    private val freeInputs = ArrayDeque<Int>()
    private val pending = ArrayDeque<EncodedFrame>()
    private var awaitingKeyframe = true
    private var lastPresentationUs = Long.MIN_VALUE
    private var maxBacklogAgeNanos = backlogAge(DEFAULT_FRAME_RATE)
    private val inFlight = InFlightRing(IN_FLIGHT_CAPACITY)
    private val recoveryTimes = ArrayDeque<Long>()

    /** When the codec last took an input (or started): see [isStalled]. */
    private var lastInputNanos = 0L

    /** Encoded frames waiting for an input buffer (RECEIVER_REPORT `decoderQueue`). */
    val pendingInputCount: Int get() = synchronized(lock) { pending.size }

    /** The plan in use, if running. */
    val currentPlan: DecoderPlan? get() = synchronized(lock) { activePlan }

    /**
     * (Re)creates the codec for [plan] on [surface]. Falls back to a configuration without
     * optional keys if the codec rejects the full one. Returns whether a codec is running.
     */
    fun start(plan: DecoderPlan, surface: Surface): Boolean {
        synchronized(controlLock) {
            stopLocked()
            if (startWithFallback(plan, surface)) return true
        }
        listener.onDecoderFailed("${plan.codecName} rejected every configuration")
        return false
    }

    /** Stops and releases the codec. Call before the Surface goes away. */
    fun stop() {
        synchronized(controlLock) { stopLocked() }
    }

    /** Stops the codec and ends the decoder's threads. */
    fun release() {
        stop()
        control.shutdown()
        callbackThread.quitSafely()
    }

    /** Queues [frame] for decoding. Thread-safe and non-blocking; takes ownership of [frame]. */
    fun submit(frame: EncodedFrame) {
        var need: KeyframeNeed? = null
        var droppedCount = 0
        var dropReason = ""
        var stalledGeneration = -1
        synchronized(lock) {
            val current = codec
            when {
                current == null -> {
                    frame.consumed()
                    droppedCount = 1
                    dropReason = "no-decoder"
                }
                isStalled(frame.receivedAtNanos, lastInputNanos, freeInputs.size) -> {
                    // The codec stopped taking input without reporting an error (MediaTek after
                    // a stream error): keyframes would only pile up behind it. Recreate it.
                    droppedCount = discardPendingLocked() + 1
                    frame.consumed()
                    dropReason = "codec-stalled"
                    awaitingKeyframe = true
                    lastInputNanos = frame.receivedAtNanos  // one recovery per stall
                    stalledGeneration = generation
                }
                awaitingKeyframe && !frame.isKeyframe -> {
                    frame.consumed()
                    droppedCount = 1
                    dropReason = "awaiting-keyframe"
                    need = KeyframeNeed.STARTUP
                }
                frame.isKeyframe -> {
                    // An IRAP frame references nothing before it: whatever still waits is obsolete.
                    awaitingKeyframe = false
                    if (pending.isNotEmpty()) {
                        droppedCount = discardPendingLocked()
                        dropReason = "superseded-by-keyframe"
                    }
                    pending.addLast(frame)
                    need = drainLocked(current)
                }
                isBehindLocked(frame.receivedAtNanos) || pending.size >= MAX_PENDING -> {
                    // The oldest waiting delta frame is stale: resynchronise on a keyframe
                    // instead of letting latency pile up behind a slow decoder.
                    droppedCount = discardPendingLocked() + 1
                    frame.consumed()
                    dropReason = "decoder-backlog"
                    awaitingKeyframe = true
                    need = KeyframeNeed.LOSS
                }
                else -> {
                    pending.addLast(frame)
                    need = drainLocked(current)
                }
            }
        }
        if (droppedCount > 0) listener.onInputDropped(droppedCount, dropReason)
        if (stalledGeneration >= 0) {
            DecoderLog.w("codec.stalled", "thresholdMs" to STALL_NANOS / 1_000_000)
            scheduleRecovery("codec-stalled", stalledGeneration)
        }
        need?.let(listener::onKeyframeNeeded)
    }

    /** Whether the oldest waiting delta frame has waited longer than two frame intervals. Holds [lock]. */
    private fun isBehindLocked(nowNanos: Long): Boolean {
        val oldest = pending.firstOrNull() ?: return false
        return !oldest.isKeyframe && nowNanos - oldest.receivedAtNanos > maxBacklogAgeNanos
    }

    private fun startWithFallback(plan: DecoderPlan, surface: Surface): Boolean {
        if (startAttempt(plan, surface)) return true
        val minimal = plan.withoutOptionalEntries()
        return minimal.entries != plan.entries && startAttempt(minimal, surface)
    }

    private fun startAttempt(plan: DecoderPlan, surface: Surface): Boolean {
        val created = try {
            MediaCodec.createByCodecName(plan.codecName)
        } catch (e: Exception) {
            DecoderLog.e("codec.create-failed", e, "codec" to plan.codecName)
            return false
        }
        try {
            created.setCallback(callback, callbackHandler)
            created.setOnFrameRenderedListener(renderedListener, callbackHandler)
            created.configure(plan.toMediaFormat(), surface, null, 0)
        } catch (e: Exception) {
            DecoderLog.w("codec.configure-failed", "codec" to plan.codecName, "entries" to plan.entries.size, "error" to e.toString())
            created.release()
            return false
        }
        logVendorParameters(created)
        synchronized(lock) {
            codec = created
            generation++
            activePlan = plan
            activeSurface = surface
            freeInputs.clear()
            discardPendingLocked()
            inFlight.clear()
            awaitingKeyframe = true
            lastPresentationUs = Long.MIN_VALUE
            lastInputNanos = System.nanoTime()
            maxBacklogAgeNanos = backlogAge(plan.frameRate ?: DEFAULT_FRAME_RATE)
        }
        try {
            created.start()
        } catch (e: Exception) {
            DecoderLog.e("codec.start-failed", e, "codec" to plan.codecName)
            synchronized(lock) {
                codec = null
                activePlan = null
            }
            created.release()
            return false
        }
        DecoderLog.i("codec.started", "plan" to plan, "notes" to plan.notes.joinToString("; "))
        listener.onDecoderStarted(plan)
        return true
    }

    private fun stopLocked() {
        val stopping = synchronized(lock) {
            val current = codec ?: return
            codec = null
            generation++
            activePlan = null
            activeSurface = null
            freeInputs.clear()
            discardPendingLocked()
            inFlight.clear()
            current
        }
        try {
            stopping.stop()
        } catch (e: Exception) {
            DecoderLog.w("codec.stop-failed", "error" to e.toString())
        }
        stopping.release()
        DecoderLog.i("codec.released")
    }

    /** Drops every waiting frame, handing its buffer back. Returns how many. Holds [lock]. */
    private fun discardPendingLocked(): Int {
        val count = pending.size
        while (pending.isNotEmpty()) pending.removeFirst().consumed()
        return count
    }

    /** Pairs waiting frames with free input buffers. Returns a keyframe need, if any. Holds [lock]. */
    private fun drainLocked(current: MediaCodec): KeyframeNeed? {
        var unusableSlots = 0
        while (freeInputs.isNotEmpty() && pending.isNotEmpty()) {
            val index = freeInputs.removeFirst()
            val buffer: ByteBuffer? = try {
                current.getInputBuffer(index)
            } catch (e: IllegalStateException) {
                freeInputs.addFirst(index)
                DecoderLog.w("input.buffer-failed", "error" to e.toString())
                scheduleRecovery("input-buffer-failed", generation)
                return null
            }
            if (buffer == null) {
                // Keep the slot (the codec still counts it as ours) and the frame; try the next slot.
                freeInputs.addLast(index)
                if (++unusableSlots >= freeInputs.size) {
                    DecoderLog.w("input.buffers-unavailable", "slots" to freeInputs.size)
                    scheduleRecovery("input-buffers-unavailable", generation)
                    return null
                }
                continue
            }
            unusableSlots = 0
            val frame = pending.removeFirst()
            if (frame.length > buffer.capacity()) {
                DecoderLog.w("input.too-large", "frameId" to frame.frameId, "bytes" to frame.length, "capacity" to buffer.capacity())
                freeInputs.addFirst(index)
                discardPendingLocked()
                awaitingKeyframe = true
                // Restart with room for it; a keyframe is decoded right after, a delta frame can't be.
                val carried = if (frame.isKeyframe) frame else null
                if (carried == null) frame.consumed()
                scheduleResize(frame.length.toLong() * 2, carried, generation)
                return if (carried == null) KeyframeNeed.LOSS else null
            }
            try {
                buffer.clear()
                buffer.put(frame.data, frame.offset, frame.length)
                val presentationUs = if (frame.captureTimeUs > lastPresentationUs) frame.captureTimeUs else lastPresentationUs + 1
                lastPresentationUs = presentationUs
                inFlight.put(presentationUs, frame.frameId, frame.receivedAtNanos, System.nanoTime())
                val flags = if (frame.isKeyframe) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                current.queueInputBuffer(index, 0, frame.length, presentationUs, flags)
                lastInputNanos = System.nanoTime()
            } catch (e: IllegalStateException) {
                DecoderLog.w("input.queue-failed", "error" to e.toString())
                scheduleRecovery("queue-failed", generation)
                return null
            } finally {
                // The bytes are in the codec's buffer (or the frame is gone): recycle the network buffer.
                frame.consumed()
            }
        }
        return null
    }

    private val callback = object : MediaCodec.Callback() {
        override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
            val need = synchronized(lock) {
                if (codec !== this@VideoDecoder.codec) return
                freeInputs.addLast(index)
                drainLocked(codec)
            }
            need?.let(listener::onKeyframeNeeded)
        }

        override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
            val frame = synchronized(lock) {
                if (codec !== this@VideoDecoder.codec) return
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    codec.releaseOutputBuffer(index, false)
                    return
                }
                val slot = inFlight.find(info.presentationTimeUs)
                DecodedFrame(
                    bufferIndex = index,
                    presentationTimeUs = info.presentationTimeUs,
                    frameId = if (slot >= 0) inFlight.frameId(slot) else -1,
                    receivedAtNanos = if (slot >= 0) inFlight.receivedAtNanos(slot) else 0,
                    queuedAtNanos = if (slot >= 0) inFlight.queuedAtNanos(slot) else 0,
                    decodedAtNanos = System.nanoTime(),
                    generation = generation,
                    releaser = releaser,
                )
            }
            sink.onFrameDecoded(frame)
        }

        override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
            val failedGeneration = synchronized(lock) { if (codec === this@VideoDecoder.codec) generation else -1 }
            DecoderLog.w(
                "codec.error", "current" to (failedGeneration >= 0), "recoverable" to e.isRecoverable, "transient" to e.isTransient,
                "code" to e.errorCode, "diagnostic" to e.diagnosticInfo,
            )
            if (failedGeneration >= 0) scheduleRecovery("codec-error", failedGeneration)
        }

        override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
            if (synchronized(lock) { codec !== this@VideoDecoder.codec }) return
            val width = croppedSize(format, "crop-left", "crop-right", MediaFormat.KEY_WIDTH)
            val height = croppedSize(format, "crop-top", "crop-bottom", MediaFormat.KEY_HEIGHT)
            DecoderLog.i("codec.output-format", "width" to width, "height" to height, "format" to format)
            if (width > 0 && height > 0) listener.onOutputSizeChanged(width, height)
        }
    }

    private val renderedListener = MediaCodec.OnFrameRenderedListener { codec, presentationTimeUs, nanoTime ->
        if (synchronized(lock) { codec === this.codec }) sink.onFrameRendered(presentationTimeUs, nanoTime)
    }

    private val releaser = OutputReleaser { frame, render, timestampNanos ->
        synchronized(lock) {
            val current = codec
            if (current == null || frame.generation != generation) return@OutputReleaser
            try {
                if (render) current.releaseOutputBuffer(frame.bufferIndex, timestampNanos)
                else current.releaseOutputBuffer(frame.bufferIndex, false)
            } catch (e: IllegalStateException) {
                DecoderLog.w("output.release-failed", "error" to e.toString())
            }
        }
    }

    /**
     * Recreates the codec of [failedGeneration] on the control thread. Errors often come in
     * bursts; the generation check makes the second recovery of a burst a no-op instead of
     * killing the codec the first one just started.
     */
    private fun scheduleRecovery(reason: String, failedGeneration: Int) {
        control.execute { recover(reason, failedGeneration) }
    }

    private fun recover(reason: String, failedGeneration: Int) {
        synchronized(controlLock) {
            val (plan, surface) = synchronized(lock) {
                if (generation != failedGeneration) return
                activePlan to activeSurface
            }
            if (plan == null || surface == null) return
            val now = System.nanoTime()
            while (recoveryTimes.isNotEmpty() && now - recoveryTimes.first() > RECOVERY_WINDOW_NANOS) recoveryTimes.removeFirst()
            recoveryTimes.addLast(now)
            if (recoveryTimes.size > MAX_RECOVERIES) {
                DecoderLog.e("codec.giving-up", null, "reason" to reason, "recoveries" to recoveryTimes.size)
                stopLocked()
                listener.onDecoderFailed("decoder keeps failing ($reason)")
                return
            }
            DecoderLog.w("codec.recovering", "reason" to reason, "codec" to plan.codecName)
            stopLocked()
            if (startWithFallback(plan, surface)) {
                listener.onKeyframeNeeded(KeyframeNeed.DECODER_ERROR)
            } else {
                listener.onDecoderFailed("decoder could not be restarted ($reason)")
            }
        }
    }

    /** Restarts codec [oldGeneration] with `max-input-size` ≥ [bytes], then decodes [carried]. */
    private fun scheduleResize(bytes: Long, carried: EncodedFrame?, oldGeneration: Int) {
        control.execute {
            synchronized(controlLock) {
                val (plan, surface) = synchronized(lock) {
                    if (generation != oldGeneration) null to null else activePlan to activeSurface
                }
                if (plan == null || surface == null) {
                    synchronized(lock) { carried?.consumed() }
                    return@execute
                }
                val size = bytes.coerceAtMost(MAX_INPUT_SIZE_LIMIT.toLong()).toInt()
                DecoderLog.i("codec.resizing-input", "maxInputSize" to size)
                stopLocked()
                if (startWithFallback(plan.withMaxInputSize(size), surface)) {
                    carried?.let(::submit)
                } else {
                    synchronized(lock) { carried?.consumed() }
                    listener.onDecoderFailed("decoder rejected max-input-size $size")
                }
            }
        }
    }

    private fun logVendorParameters(codec: MediaCodec) {
        try {
            val names = codec.supportedVendorParameters
            DecoderLog.i("codec.vendor-parameters", "codec" to codec.name, "count" to names.size)
            names.chunked(20).forEach { chunk -> DecoderLog.d("codec.vendor-parameters.list", "names" to chunk.joinToString(",")) }
        } catch (e: Exception) {
            DecoderLog.w("codec.vendor-parameters-failed", "error" to e.toString())
        }
    }

    companion object {
        /** Hard cap on frames waiting for input buffers (the age limit normally triggers first). */
        const val MAX_PENDING: Int = 8

        /** Codec recreations allowed per 10 s before giving up. */
        const val MAX_RECOVERIES: Int = 3

        private const val IN_FLIGHT_CAPACITY = 64
        private const val DEFAULT_FRAME_RATE = 60f
        private const val MAX_INPUT_SIZE_LIMIT = 64 * 1024 * 1024
        private val RECOVERY_WINDOW_NANOS = TimeUnit.SECONDS.toNanos(10)

        /** A codec holding every input buffer this long, with frames to decode, is stuck. */
        val STALL_NANOS: Long = TimeUnit.SECONDS.toNanos(1)

        /**
         * Whether the codec is stuck: a frame arrives, the codec holds every input buffer, and it
         * hasn't taken one for [STALL_NANOS]. A healthy codec hands buffers back within a frame;
         * a static screen sends nothing, so it never looks stuck.
         */
        internal fun isStalled(nowNanos: Long, lastInputNanos: Long, freeInputs: Int): Boolean =
            freeInputs == 0 && nowNanos - lastInputNanos > STALL_NANOS

        /** Two frame intervals. */
        private fun backlogAge(frameRate: Float): Long =
            (2 * 1_000_000_000L / frameRate.coerceIn(1f, 1000f).toDouble()).toLong()

        private fun croppedSize(format: MediaFormat, lowKey: String, highKey: String, sizeKey: String): Int = when {
            format.containsKey(lowKey) && format.containsKey(highKey) -> format.getInteger(highKey) - format.getInteger(lowKey) + 1
            format.containsKey(sizeKey) -> format.getInteger(sizeKey)
            else -> 0
        }
    }
}

/**
 * Timing of frames inside the codec, keyed by presentation time, in fixed arrays (no allocation
 * per frame). Holds the most recent [capacity] frames; older entries are overwritten.
 */
internal class InFlightRing(private val capacity: Int) {
    private val presentationUs = LongArray(capacity) { Long.MIN_VALUE }
    private val frameIds = LongArray(capacity)
    private val receivedAt = LongArray(capacity)
    private val queuedAt = LongArray(capacity)
    private var next = 0

    fun put(presentationTimeUs: Long, frameId: Long, receivedAtNanos: Long, queuedAtNanos: Long) {
        presentationUs[next] = presentationTimeUs
        frameIds[next] = frameId
        receivedAt[next] = receivedAtNanos
        queuedAt[next] = queuedAtNanos
        next = (next + 1) % capacity
    }

    /** The slot holding [presentationTimeUs] (most recent first), or -1. */
    fun find(presentationTimeUs: Long): Int {
        for (step in 1..capacity) {
            val slot = (next - step + capacity) % capacity
            if (presentationUs[slot] == presentationTimeUs) return slot
        }
        return -1
    }

    fun frameId(slot: Int): Long = frameIds[slot]

    fun receivedAtNanos(slot: Int): Long = receivedAt[slot]

    fun queuedAtNanos(slot: Int): Long = queuedAt[slot]

    fun clear() {
        presentationUs.fill(Long.MIN_VALUE)
        next = 0
    }
}

/** The `MediaFormat` a [DecoderPlan] describes. */
fun DecoderPlan.toMediaFormat(): MediaFormat {
    val format = MediaFormat.createVideoFormat(mimeType, width, height)
    for (entry in entries) {
        when (val value = entry.value) {
            is FormatValue.IntValue -> format.setInteger(entry.key, value.value)
            is FormatValue.FloatValue -> format.setFloat(entry.key, value.value)
        }
    }
    for ((key, bytes) in codecSpecificData) format.setByteBuffer(key, ByteBuffer.wrap(bytes))
    return format
}
