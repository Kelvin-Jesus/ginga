package dev.tab2mac.decoder

/**
 * One access unit to decode: `data[offset until offset + length]`, an Annex‑B byte stream.
 *
 * The bytes may live in a recycled network buffer owned by [owner]: the decoder calls [consumed]
 * exactly once, as soon as it has copied them into a codec input buffer or dropped the frame,
 * which closes the owner and hands the buffer back (see `Incoming`). Nothing may read [data]
 * after that. The owner is an [AutoCloseable] rather than a lambda so nothing is allocated per
 * frame for it.
 *
 * @property captureTimeUs Mac capture time (Mac clock, µs); used as the presentation timestamp so
 *   rendered frames can be matched to their capture time for end-to-end latency.
 * @property receivedAtNanos `System.nanoTime()` when the frame arrived from the network.
 */
class EncodedFrame(
    val frameId: Long,
    val captureTimeUs: Long,
    val receivedAtNanos: Long,
    val isKeyframe: Boolean,
    val data: ByteArray,
    val offset: Int = 0,
    val length: Int = data.size - offset,
    private val owner: AutoCloseable? = null,
) {
    init {
        require(offset >= 0 && length >= 0 && offset + length <= data.size) { "range out of bounds" }
    }

    private var done = false

    /** The decoder is finished with [data]. Idempotent; called under the decoder's lock. */
    fun consumed() {
        if (done) return
        done = true
        owner?.close()
    }
}

/**
 * A decoded output buffer waiting to be shown. Exactly one of [render] or [drop] must be called,
 * promptly: MediaCodec has only a few output buffers.
 *
 * @property presentationTimeUs the timestamp queued with the input: the Mac capture time.
 * @property frameId the protocol frame id, or -1 if unknown.
 * @property queuedAtNanos when the access unit was queued into the codec (0 if unknown).
 * @property decodedAtNanos when the output callback arrived.
 */
class DecodedFrame internal constructor(
    val bufferIndex: Int,
    val presentationTimeUs: Long,
    val frameId: Long,
    val receivedAtNanos: Long,
    val queuedAtNanos: Long,
    val decodedAtNanos: Long,
    internal val generation: Int,
    private val releaser: OutputReleaser,
) {
    /** Decode latency, queue → output, or -1 when unknown (a primitive: no boxing per frame). */
    val decodeLatencyNanos: Long get() = if (queuedAtNanos > 0) decodedAtNanos - queuedAtNanos else -1

    /** Sends the frame to the Surface for display at [timestampNanos] (`System.nanoTime()` base). */
    fun render(timestampNanos: Long) = releaser.release(this, render = true, timestampNanos = timestampNanos)

    /** Returns the buffer to the codec without displaying it. */
    fun drop() = releaser.release(this, render = false, timestampNanos = 0)
}

/** Releases output buffers back to the codec that produced them. */
internal fun interface OutputReleaser {
    fun release(frame: DecodedFrame, render: Boolean, timestampNanos: Long)
}

/** Where decoded frames go; implemented by the renderer. Called on the decoder's callback thread. */
interface DecodedFrameSink {
    /** A new frame is ready; call [DecodedFrame.render] or [DecodedFrame.drop]. */
    fun onFrameDecoded(frame: DecodedFrame)

    /**
     * The frame with [presentationTimeUs] reached the display at [renderTimeNanos]
     * (`System.nanoTime()` base). May arrive late and batched; purely informational.
     */
    fun onFrameRendered(presentationTimeUs: Long, renderTimeNanos: Long)
}
