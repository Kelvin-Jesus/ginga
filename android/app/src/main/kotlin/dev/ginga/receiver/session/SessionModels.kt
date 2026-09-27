package dev.ginga.receiver.session

import dev.ginga.protocol.CursorPosition
import dev.ginga.protocol.CursorShape
import dev.ginga.protocol.DirectLink
import dev.ginga.protocol.DisplayDescription
import dev.ginga.protocol.ErrorMessage
import dev.ginga.protocol.Fingerprint
import dev.ginga.protocol.GoodbyeReason
import dev.ginga.protocol.PairingCode
import dev.ginga.protocol.ReceiverReport
import dev.ginga.protocol.StreamDescription
import dev.ginga.protocol.StreamFormat
import dev.ginga.protocol.VideoFrame
import dev.ginga.protocol.Welcome
import java.util.concurrent.TimeUnit

/** The §5 Android clock: `System.nanoTime()` (CLOCK_MONOTONIC). Injectable for tests. */
fun interface MonotonicClock {
    fun nanoTime(): Long
}

/** Where the session sends the video stream. Called on the session thread. */
interface VideoSink {
    /** A new codec configuration; a keyframe follows (§3.1). */
    fun onStreamFormat(format: StreamFormat, stream: StreamDescription)

    /**
     * One encoded frame. The sink owns it: [frame]'s data lives in a recycled network buffer and
     * [owner] must be closed exactly once, as soon as the data has been copied or dropped.
     */
    fun onVideoFrame(frame: VideoFrame, receivedAtNanos: Long, owner: AutoCloseable)

    /** The stream ended (disconnect, GOODBYE, new connection): release the decoder. */
    fun onStreamStopped()
}

/**
 * Where the session sends the pointer when the Mac draws it as a side channel (§3.3b, feature
 * `cursor`). Called on the session thread, only while streaming.
 */
interface CursorSink {
    /** A pointer image, once per shape per session: cache it by id. */
    fun onCursorShape(shape: CursorShape)

    /** Where the pointer is now (latest wins). */
    fun onCursor(position: CursorPosition)

    /** The stream stopped (disconnect, new connection): forget the shapes and hide the pointer. */
    fun onCursorReset()

    companion object {
        /** Draws nothing. */
        val NONE: CursorSink = object : CursorSink {
            override fun onCursorShape(shape: CursorShape) = Unit

            override fun onCursor(position: CursorPosition) = Unit

            override fun onCursorReset() = Unit
        }
    }
}

/** Receiver statistics the session feeds and reports. Thread-safe. */
interface SessionStats {
    /** Every received frame, for `bytesReceived`. */
    fun onMessageReceived(wireSize: Int)

    fun onVideoFrameReceived(frameId: Long)

    /** Builds the RECEIVER_REPORT for the interval since the previous call. */
    fun intervalReport(clockOffsetUs: Long?, rttUs: Long?): ReceiverReport

    /** For KEYFRAME_REQUEST `lastDecodedFrameId`. */
    val lastDecodedFrameId: Long?
}

/** Where a session is. */
sealed interface SessionState {
    /** Not connected (or waiting for the transport to reconnect). */
    data object Idle : SessionState

    /** Connected, HELLO sent, waiting for WELCOME. */
    data class Handshaking(val connectionId: Long) : SessionState

    /**
     * Wi‑Fi: the Mac asked to pair (PROTOCOL.md §6). [code] is null while the nonces are being
     * exchanged, then both screens show it (6 digits). When the user says it matches
     * ([Session.confirmPairing]), [confirmed] is set and the session waits for the Mac's user;
     * PAIRING `paired` then WELCOME follow.
     */
    data class Pairing(val connectionId: Long, val macName: String, val code: String? = null, val confirmed: Boolean = false) : SessionState

    /**
     * WELCOME received. [display]/[stream] follow Mac CONFIGURE announcements. [paused]: nothing
     * on screen shows video, and the Mac was asked to stop sending it (feature `pause`).
     */
    data class Streaming(
        val connectionId: Long,
        val welcome: Welcome,
        val display: DisplayDescription,
        val stream: StreamDescription,
        val format: StreamFormat?,
        val paused: Boolean = false,
    ) : SessionState

    /**
     * Disconnected on purpose because nothing could show video for a while and the Mac can't
     * pause; reconnects as soon as a video Surface exists again.
     */
    data object Suspended : SessionState

    /** Terminal: the user disconnected, the Mac said goodbye for good or refused the tablet. */
    data class Ended(val reason: String) : SessionState
}

/**
 * Wi‑Fi pairing (PROTOCOL.md §6) for a session over TLS: the tablet's certificate fingerprint,
 * for the code, and where the Mac's pin goes once both users confirmed. USB sessions have none,
 * and ignore PAIRING.
 */
class PairingContext(
    val tabletFingerprint: Fingerprint,
    /** Whether [mac] (the certificate fingerprint the Mac presented) is pinned: no trust on first use. */
    val isPinned: (mac: Fingerprint) -> Boolean,
    /** PAIRING `paired`: pin [mac]. */
    val onPaired: (mac: Fingerprint, macName: String) -> Unit,
    /** A fresh 32-byte nonce per attempt; injectable for tests. */
    val newNonce: () -> ByteArray = PairingCode::newNonce,
)

/** The [SessionState.Ended] reason when the Mac said GOODBYE [reason] for good (`user`, `replaced`). */
fun endedByMac(reason: GoodbyeReason): String = "Mac: $reason"

/** Session events for the UI. Called on the session thread. */
interface SessionListener {
    fun onStateChanged(state: SessionState)

    /** A new clock-sync estimate: θ of the best sample and δ of the latest one (µs). */
    fun onClockSync(offsetUs: Long, rttUs: Long) {}

    fun onRemoteError(error: ErrorMessage) {}

    /** DIRECT_LINK (§6b) on this authenticated, streaming session: keep the Mac's no-router key. */
    fun onDirectLink(message: DirectLink) {}
}

/** Structured event logging (`event key=value …`), injectable so the session stays JVM-testable. */
fun interface SessionLog {
    fun event(name: String, fields: List<Pair<String, Any?>>)
}

/**
 * Timing of the session's periodic work (§3.1). Power: nothing runs more often than once a
 * second. RECEIVER_REPORTs feed the Mac's bitrate controller, which only Wi‑Fi uses (architecture
 * §2.5: USB runs a fixed bitrate), so over USB they go out once a second, together with the
 * clock-sync PING, and every 5 s while paused; a Wi‑Fi transport (M7) uses the protocol's 250 ms.
 */
data class SessionConfig(
    val pingIntervalNanos: Long = TimeUnit.SECONDS.toNanos(1),
    val reportIntervalNanos: Long = TimeUnit.SECONDS.toNanos(1),
    val pausedReportIntervalNanos: Long = TimeUnit.SECONDS.toNanos(5),
    /**
     * Drop the connection if WELCOME doesn't arrive (the Mac also closes after 5 s without HELLO).
     * Null waits as long as the link lasts: over USB accessory the Mac reads HELLO whenever it
     * (re)opens its side of the link, and has no HELLO timeout either.
     */
    val handshakeTimeoutNanos: Long? = TimeUnit.SECONDS.toNanos(5),
    /** Rate limit for KEYFRAME_REQUEST; a decoder waiting for a keyframe asks on every delta frame. */
    val keyframeRequestIntervalNanos: Long = TimeUnit.MILLISECONDS.toNanos(500),
    /** How long the video Surface may be missing before the stream is paused (debounces flapping). */
    val pauseAfterNanos: Long = TimeUnit.SECONDS.toNanos(1),
    /** Without the `pause` feature: how long without a Surface before saying GOODBYE and suspending. */
    val goodbyeWithoutSurfaceNanos: Long = TimeUnit.SECONDS.toNanos(10),
    /** A pairing attempt ends after this long (§6), as it does on the Mac. */
    val pairingTimeoutNanos: Long = TimeUnit.SECONDS.toNanos(120),
    /** PINGs awaiting a PONG that are remembered. */
    val maxOutstandingPings: Int = 16,
)
