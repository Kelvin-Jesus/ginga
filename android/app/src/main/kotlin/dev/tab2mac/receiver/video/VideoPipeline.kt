package dev.tab2mac.receiver.video

import android.view.Surface
import dev.tab2mac.decoder.CodecCatalog
import dev.tab2mac.decoder.ColorAspects
import dev.tab2mac.decoder.DecoderConfigPlanner
import dev.tab2mac.decoder.DecoderPlan
import dev.tab2mac.decoder.DecoderRequest
import dev.tab2mac.decoder.EncodedFrame
import dev.tab2mac.decoder.NoDecoderException
import dev.tab2mac.decoder.VideoDecoder
import dev.tab2mac.protocol.Codec
import dev.tab2mac.protocol.KeyframeReason
import dev.tab2mac.protocol.StreamDescription
import dev.tab2mac.protocol.StreamFormat
import dev.tab2mac.protocol.VideoFrame
import dev.tab2mac.receiver.AppLog
import dev.tab2mac.receiver.session.VideoSink
import dev.tab2mac.receiver.stats.StreamStats
import dev.tab2mac.renderer.ClockOffsetProvider
import dev.tab2mac.renderer.LatestFramePresenter
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Width × height of the decoded stream. */
data class VideoSize(val width: Int, val height: Int)

/**
 * Decoder + renderer for the session: a [VideoSink] on the session side, a Surface owner on the
 * UI side. The codec runs only while both a STREAM_FORMAT and a Surface are present; it is
 * recreated when either changes.
 */
class VideoPipeline(
    private val stats: StreamStats,
    /** Asks the Mac for a keyframe; must hop to the session thread. */
    private val keyframeRequester: (KeyframeReason) -> Unit,
    clockOffset: ClockOffsetProvider,
    /** `operating-rate` headroom (1 = power-saving default, 2 = lower latency); read at each decoder start. */
    private val operatingRateFactor: () -> Double = { 1.0 },
) : VideoSink {
    private val presenter = LatestFramePresenter(clockOffset, stats)
    private val decoder = VideoDecoder(presenter, DecoderEvents())

    /** Serialises decoder (re)starts from the session thread with Surface changes from the UI. */
    private val lock = Any()
    private var surface: Surface? = null
    private var format: StreamFormat? = null
    private var stream: StreamDescription? = null

    private val mutableVideoSize = MutableStateFlow<VideoSize?>(null)

    /** The stream's picture size, for the Surface buffer and letterboxing. */
    val videoSize: StateFlow<VideoSize?> = mutableVideoSize.asStateFlow()

    private val mutablePlan = MutableStateFlow<DecoderPlan?>(null)

    /** The running decoder configuration, for diagnostics. */
    val plan: StateFlow<DecoderPlan?> = mutablePlan.asStateFlow()

    private val mutableError = MutableStateFlow<String?>(null)

    /** Why video can't be shown (e.g. no hardware decoder), or null. */
    val error: StateFlow<String?> = mutableError.asStateFlow()

    /** Encoded frames waiting for the codec (RECEIVER_REPORT `decoderQueue`). */
    val pendingInputCount: Int get() = decoder.pendingInputCount

    // VideoSink: session thread.

    override fun onStreamFormat(format: StreamFormat, stream: StreamDescription) {
        mutableVideoSize.value = VideoSize(format.width, format.height)
        synchronized(lock) {
            this.format = format
            this.stream = stream
            // No keyframe request: the Mac sends one right after STREAM_FORMAT (§3.1).
            restartLocked(requestKeyframe = false)
        }
    }

    override fun onVideoFrame(frame: VideoFrame, receivedAtNanos: Long, owner: AutoCloseable) {
        // The decoder copies the access unit into a codec buffer and then closes the owner, which
        // recycles the network buffer (no garbage per frame); it does the same for dropped frames.
        decoder.submit(
            EncodedFrame(
                frameId = frame.frameId,
                captureTimeUs = frame.captureTimeUs,
                receivedAtNanos = receivedAtNanos,
                isKeyframe = frame.isKeyframe,
                data = frame.data,
                offset = frame.dataOffset,
                length = frame.dataLength,
                owner = owner,
            ),
        )
    }

    override fun onStreamStopped() {
        synchronized(lock) {
            format = null
            stream = null
            decoder.stop()
            mutablePlan.value = null
        }
    }

    // Surface lifecycle: main thread.

    /** The output Surface exists; (re)start decoding into it and ask for a keyframe. */
    fun attachSurface(surface: Surface) {
        synchronized(lock) {
            this.surface = surface
            restartLocked(requestKeyframe = true)
        }
    }

    /** The Surface is going away: stop the codec before returning (SurfaceHolder contract). */
    fun detachSurface() {
        synchronized(lock) {
            surface = null
            decoder.stop()
            mutablePlan.value = null
        }
    }

    /** Record latencies for 1 frame in [interval] (1 while the overlay shows them). */
    fun setTimingSampleInterval(interval: Int) {
        presenter.timingSampleInterval = interval
    }

    private fun restartLocked(requestKeyframe: Boolean) {
        try {
            restartOrThrow(requestKeyframe)
        } catch (e: RuntimeException) {
            AppLog.e("video.restart-failed", e)
            decoder.stop()
            mutablePlan.value = null
            mutableError.value = "Video decoder failed: ${e.message ?: e.javaClass.simpleName}"
        }
    }

    private fun restartOrThrow(requestKeyframe: Boolean) {
        val surface = surface
        val format = format
        if (surface == null || format == null) {
            decoder.stop()
            mutablePlan.value = null
            return
        }
        val mime = mimeType(format.codec)
        if (mime == null) {
            AppLog.w("video.codec-unsupported", "codec" to format.codec)
            decoder.stop()
            mutablePlan.value = null
            mutableError.value = "Unsupported codec ${format.codec}"
            return
        }
        val stream = stream
        val request = DecoderRequest(
            mimeType = mime,
            width = format.width,
            height = format.height,
            frameRate = stream?.fps,
            parameterSets = format.parameterSets,
            color = stream?.let { ColorAspects.fromNames(it.primaries, it.transfer, it.range) },
            operatingRateFactor = operatingRateFactor(),
        )
        val plan = try {
            DecoderConfigPlanner.plan(request, CodecCatalog.candidates(mime), CodecCatalog.socInfo())
        } catch (e: NoDecoderException) {
            AppLog.e("video.no-decoder", e, "mime" to mime)
            decoder.stop()
            mutablePlan.value = null
            mutableError.value = e.message
            return
        }
        if (decoder.start(plan, surface)) {
            mutablePlan.value = decoder.currentPlan
            mutableError.value = null
            if (requestKeyframe) keyframeRequester(KeyframeReason.STARTUP)
        } else {
            mutablePlan.value = null
        }
    }

    private inner class DecoderEvents : VideoDecoder.Listener {
        override fun onKeyframeNeeded(reason: VideoDecoder.KeyframeNeed) {
            keyframeRequester(
                when (reason) {
                    VideoDecoder.KeyframeNeed.STARTUP -> KeyframeReason.STARTUP
                    VideoDecoder.KeyframeNeed.DECODER_ERROR -> KeyframeReason.DECODER_ERROR
                    VideoDecoder.KeyframeNeed.LOSS -> KeyframeReason.LOSS
                },
            )
        }

        override fun onInputDropped(count: Int, reason: String) {
            stats.onInputDropped(count)
        }

        override fun onDecoderStarted(plan: DecoderPlan) {
            mutablePlan.value = plan
        }

        override fun onOutputSizeChanged(width: Int, height: Int) {
            AppLog.i("video.output-size", "width" to width, "height" to height)
        }

        override fun onDecoderFailed(message: String) {
            AppLog.w("video.decoder-failed", "message" to message)
            mutablePlan.value = null
            mutableError.value = message
        }
    }

    companion object {
        /** STREAM_FORMAT / WELCOME `codec` → MIME type; null if unsupported. */
        fun mimeType(codec: Codec): String? = when (codec.value.lowercase()) {
            "hevc", "h265", "h.265" -> DecoderConfigPlanner.MIME_HEVC
            "h264", "h.264", "avc" -> DecoderConfigPlanner.MIME_AVC
            else -> null
        }
    }
}
