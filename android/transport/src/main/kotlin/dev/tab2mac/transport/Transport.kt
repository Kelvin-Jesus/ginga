package dev.tab2mac.transport

import dev.tab2mac.protocol.ByteArrayPool
import dev.tab2mac.protocol.Fingerprint
import dev.tab2mac.protocol.FrameFlags
import dev.tab2mac.protocol.Message
import dev.tab2mac.protocol.StreamId
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

/**
 * A reliable, ordered message channel to the Mac (architecture §2.4, "MessageChannel").
 *
 * One instance covers one user-initiated connection: [connect] starts it, it reconnects on its
 * own according to its policy, and [close] ends it for good. Every underlying connection gets a
 * new id, so consumers can tell a reconnection from the connection before it.
 */
interface Transport {
    /** Where this transport connects, for logs and UI (e.g. `tcp://127.0.0.1:47800`). */
    val endpoint: String

    /** Connection lifecycle. Conflated: consumers must compare connection ids, not count events. */
    val state: StateFlow<ConnectionState>

    /**
     * Decoded messages in arrival order, across reconnections. Single collector. Collection
     * applies back-pressure: a slow collector eventually blocks the socket reader.
     * Completes after [close].
     */
    val incoming: Flow<Incoming>

    /** Starts connecting (idempotent). */
    fun connect()

    /**
     * Queues [message] on the current connection. Returns false when there is no connection, or
     * when [connectionId] is given and no longer current: messages never leak into a newer
     * connection that hasn't seen HELLO yet. Thread-safe.
     */
    fun send(message: Message, connectionId: Long? = null): Boolean

    /**
     * Queues [messages] together, so they leave in one write (e.g. the historical samples of one
     * `MotionEvent`). Same rules as [send].
     */
    fun sendBatch(messages: List<Message>, connectionId: Long? = null): Boolean

    /** Closes connection [connectionId] (e.g. a handshake timeout); the transport may reconnect. */
    fun dropConnection(connectionId: Long, reason: String)

    /**
     * Connection [connectionId] completed the handshake (WELCOME). Only then does its loss reset
     * the reconnection backoff: a Mac that accepts and immediately rejects the tablet is retried
     * with growing delays instead of every 250 ms.
     */
    fun markHealthy(connectionId: Long)

    /**
     * Flushes what is queued (e.g. GOODBYE), closes the connection and stops reconnecting until
     * [resume] (state [ConnectionState.Suspended]). Idempotent.
     */
    fun suspend()

    /** Leaves [suspend]: connects again right away. */
    fun resume()

    /**
     * Something that made the last attempts fail changed (for example a new adb loopback token
     * arrived): skip the current (or next) backoff wait and connect again now. No-op by default.
     */
    fun retryNow() {}

    /** Flushes queued messages briefly, then closes for good. Idempotent. */
    fun close()
}

/** Lifecycle of a [Transport]. */
sealed interface ConnectionState {
    /** [Transport.connect] hasn't been called. */
    data object Idle : ConnectionState

    /** Opening a connection; [attempt] counts consecutive attempts, from 1. */
    data class Connecting(val attempt: Int) : ConnectionState

    /**
     * Connected; everything received and sent until the next state belongs to [connectionId].
     * [peer] is the Mac's certificate fingerprint on TLS links (Wi‑Fi), null otherwise.
     */
    data class Connected(val connectionId: Long, val peer: Fingerprint? = null) : ConnectionState

    /** Waiting [delayMs] before attempt [attempt] + 1, after [lastError]. */
    data class WaitingToRetry(val attempt: Int, val delayMs: Long, val lastError: String?) : ConnectionState

    /** Not connected on purpose until [Transport.resume] (e.g. nothing on screen to show video). */
    data object Suspended : ConnectionState

    /** Terminal: closed by the user, or dropped with reconnection disabled. */
    data class Closed(val reason: String?) : ConnectionState
}

/**
 * One received message.
 *
 * The receiver owns it and must call [release] (or [close]) once it no longer needs the message's
 * bytes: a VIDEO_FRAME's data is a view into a pooled buffer that is recycled on release (so
 * video doesn't create per-frame garbage). Releasing is idempotent; forgetting it only costs a
 * GC'd buffer. It is an [AutoCloseable] so it can be handed on as the buffer's owner without
 * allocating a callback per frame.
 *
 * @property connectionId the connection it arrived on.
 * @property flags the frame header flags (e.g. KEYFRAME).
 * @property wireSize header + payload bytes.
 * @property receivedAtNanos `System.nanoTime()` when the read that completed the frame returned;
 *   the §3.4 receive timestamp (t2 of a PING, t4 of a PONG).
 */
class Incoming(
    val connectionId: Long,
    val message: Message,
    val flags: FrameFlags,
    val stream: StreamId,
    val wireSize: Int,
    val receivedAtNanos: Long,
    private val pooledPayload: ByteArray? = null,
    private val pool: ByteArrayPool? = null,
) : AutoCloseable {
    private var released = false

    /** Returns a pooled payload for reuse; afterwards a VIDEO_FRAME's data must not be read. */
    fun release() {
        synchronized(this) {
            if (released) return
            released = true
        }
        if (pooledPayload != null) pool?.release(pooledPayload)
    }

    /** Same as [release]. */
    override fun close() = release()

    override fun toString(): String = "Incoming(connection=$connectionId, message=$message, bytes=$wireSize)"
}
