package dev.tab2mac.transport

import android.os.Process
import dev.tab2mac.protocol.ByteArrayPool
import dev.tab2mac.protocol.ErrorCode
import dev.tab2mac.protocol.ErrorMessage
import dev.tab2mac.protocol.Fingerprint
import dev.tab2mac.protocol.Frame
import dev.tab2mac.protocol.FrameCodec
import dev.tab2mac.protocol.FrameDecoder
import dev.tab2mac.protocol.Message
import dev.tab2mac.protocol.MessageCodec
import dev.tab2mac.protocol.MessageType
import dev.tab2mac.protocol.PayloadAllocator
import dev.tab2mac.protocol.ProtocolException
import java.io.BufferedOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.thread
import kotlin.concurrent.withLock
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow

/** A bidirectional byte pipe to the Mac: a TCP or TLS socket, or a USB accessory's bulk endpoints. */
interface ByteLink {
    val input: InputStream
    val output: OutputStream

    /** The Mac's certificate fingerprint on an authenticated link (TLS), null otherwise. */
    val peerFingerprint: Fingerprint? get() = null

    /** Ends our sending direction where the link can (TCP half-close); a no-op otherwise. */
    fun shutdownOutput() {}

    /**
     * Closes both directions. Where the platform can, this also wakes a thread blocked in a read
     * or write on the link (sockets; file descriptors on Android); nothing may rely on it.
     */
    fun close()
}

/** The outcome of trying to open a [ByteLink]. */
sealed interface LinkAttempt {
    class Opened(val link: ByteLink) : LinkAttempt

    /** Not possible right now (refused, busy): retry with backoff. */
    data class Failed(val reason: String) : LinkAttempt

    /** The peer is gone for good (for example the accessory was unplugged): stop. */
    data class Gone(val reason: String) : LinkAttempt
}

/** Opens links for a [LinkTransport]; called on its supervisor thread, may block briefly. */
fun interface LinkOpener {
    fun open(): LinkAttempt
}

/** Behaviour shared by every link-based transport. */
data class LinkOptions(
    /** Reconnect after a failure or disconnect, following [reconnectPolicy]. */
    val autoReconnect: Boolean = true,
    val reconnectPolicy: ReconnectPolicy = ReconnectPolicy(),
    /**
     * Received messages buffered for the collector before the reader blocks. Small on purpose:
     * a deep buffer would hide back-pressure and add latency instead of slowing the Mac down (§4).
     */
    val incomingCapacity: Int = 8,
    /** Read size. The kernel's AOA driver returns at most 16 KiB per read, so never less. */
    val readChunkBytes: Int = 256 * 1024,
    /** How long a graceful close / suspend lets queued messages (e.g. GOODBYE) drain. */
    val closeDrainTimeoutMs: Long = 300,
    /**
     * The transport serves one link, then ends (AOA). Use it when a link has no connection
     * boundaries, so reopening it behind the session's back could splice two sessions' bytes;
     * the owner starts a new transport (and a new HELLO) instead. When that link ends, or is
     * dropped or suspended locally, the state becomes [ConnectionState.Closed] at once, without
     * waiting for the pending read to return.
     */
    val singleLink: Boolean = false,
    /** Failed opens in a row after which the transport gives up (Closed); null = keep retrying. */
    val maxOpenAttempts: Int? = null,
    /**
     * Liveness, checked by a watchdog thread that never does I/O: the link is torn down (closed,
     * which unblocks its reader and writer) when nothing has been received for this long on a
     * healthy link ([Transport.markHealthy]: the session streams, PINGs go out at 1 Hz and the Mac
     * answers each at once), or when a single write has been blocked for this long. Over USB
     * accessory this is the only sign of a Mac that went away: no FIN or RST ever comes, reads
     * never return and writes stop completing. Null: no watchdog.
     */
    val silenceTimeoutMs: Long? = null,
    /**
     * The link may start with leftover bytes of an earlier connection (a reopened USB accessory:
     * the tail of the previous link's last write). Bytes are skipped until the first plausible
     * frame header; after the first frame, framing is strict again ([FrameDecoder]).
     */
    val resyncAtStart: Boolean = false,
) {
    init {
        require(readChunkBytes >= MIN_READ_CHUNK) { "readChunkBytes must be at least 16 KiB" }
        require(maxOpenAttempts == null || maxOpenAttempts >= 1) { "maxOpenAttempts must be at least 1" }
        require(silenceTimeoutMs == null || silenceTimeoutMs > 0) { "silenceTimeoutMs must be positive" }
    }

    companion object {
        /** `f_accessory`'s bulk buffer: reads smaller than this could split its transfers. */
        const val MIN_READ_CHUNK: Int = 16 * 1024
    }
}

/**
 * The engine behind [TcpTransport] and [AccessoryTransport]: one supervisor thread opens links
 * through [opener], reads each one with a blocking read (always one read pending), and backs
 * off between attempts; each link has a writer thread draining a [SendQueue]. Both threads run
 * at display priority and sleep when idle — no polling.
 *
 * - Backoff: a link only counts as healthy once the session reports its handshake with
 *   [markHealthy]; links that are accepted and then refused are retried with growing delays.
 * - [LinkOptions.singleLink]: one link, then Closed (AOA); [LinkOptions.maxOpenAttempts] bounds
 *   the retries while opening fails.
 * - Received VIDEO_FRAME payloads come from a [ByteArrayPool] (see [Incoming.release]).
 * - The writer stamps PING `t1` and PONG `t3` right before the bytes are written (§3.4).
 */
open class LinkTransport(
    final override val endpoint: String,
    private val opener: LinkOpener,
    private val options: LinkOptions,
    private val nanoClock: () -> Long,
    private val threadPrefix: String,
) : Transport {

    private val mutableState = MutableStateFlow<ConnectionState>(ConnectionState.Idle)
    final override val state: StateFlow<ConnectionState> = mutableState.asStateFlow()

    private val incomingChannel = Channel<Incoming>(options.incomingCapacity) { undelivered -> undelivered.release() }
    final override val incoming: Flow<Incoming> = incomingChannel.receiveAsFlow()

    private val lock = ReentrantLock()
    private val wake = lock.newCondition()
    private var started = false
    private val finished = AtomicBoolean(false)

    @Volatile
    private var closing = false

    /** Why [closing] was set. */
    @Volatile
    private var closeReason: String? = null

    @Volatile
    private var suspended = false

    /** [retryNow] was called: the next (or current) backoff wait is skipped once. */
    @Volatile
    private var retryRequested = false

    @Volatile
    private var current: LinkConnection? = null

    private val connectionIds = AtomicLong(0)

    /** Recycles VIDEO_FRAME payload buffers across frames and links. */
    private val payloadPool = ByteArrayPool()

    final override fun connect() {
        lock.withLock {
            if (started || closing) return
            started = true
        }
        TransportLog.i("transport.start", "endpoint" to endpoint, "autoReconnect" to options.autoReconnect)
        thread(name = "$threadPrefix-supervisor", isDaemon = true) { supervise() }
    }

    final override fun send(message: Message, connectionId: Long?): Boolean {
        val connection = current ?: return false
        if (connectionId != null && connectionId != connection.id) return false
        return connection.enqueue(message)
    }

    final override fun sendBatch(messages: List<Message>, connectionId: Long?): Boolean {
        val connection = current ?: return false
        if (connectionId != null && connectionId != connection.id) return false
        return connection.enqueueAll(messages)
    }

    final override fun dropConnection(connectionId: Long, reason: String) {
        val connection = current ?: return
        if (connection.id != connectionId) return
        TransportLog.w("connection.drop", "id" to connectionId, "reason" to reason)
        connection.closeGracefully(options.closeDrainTimeoutMs, reason)
        if (options.singleLink) endNow(reason)
    }

    final override fun markHealthy(connectionId: Long) {
        val connection = current ?: return
        if (connection.id == connectionId) connection.healthy = true
    }

    final override fun suspend() {
        if (options.singleLink) {
            // Nothing could resume it: the link can't be reopened. Flush (GOODBYE) and end.
            current?.closeGracefully(options.closeDrainTimeoutMs, "suspended")
            endNow("suspended")
            return
        }
        lock.withLock {
            if (suspended || closing) return
            suspended = true
            wake.signalAll()
        }
        TransportLog.i("transport.suspend", "endpoint" to endpoint)
        current?.closeGracefully(options.closeDrainTimeoutMs, "suspended")
    }

    final override fun retryNow() {
        lock.withLock {
            retryRequested = true
            wake.signalAll()
        }
        TransportLog.i("transport.retry-now", "endpoint" to endpoint)
    }

    final override fun resume() {
        lock.withLock {
            if (!suspended) return
            suspended = false
            wake.signalAll()
        }
        TransportLog.i("transport.resume", "endpoint" to endpoint)
    }

    final override fun close() {
        if (!markClosing("closed")) return
        TransportLog.i("transport.close", "endpoint" to endpoint)
        current?.closeGracefully(options.closeDrainTimeoutMs, "closed locally")
        // Nobody reads after close: unblock a reader waiting for buffer space and drop the backlog.
        incomingChannel.cancel()
        finish("closed")
    }

    /**
     * Ends the transport at once with [reason] (for example the accessory was unplugged): the link
     * is closed without draining, and the state doesn't wait for a read that may never return.
     */
    protected fun terminate(reason: String) {
        if (!markClosing(reason)) return
        TransportLog.i("transport.terminate", "endpoint" to endpoint, "reason" to reason)
        current?.abort(reason)
        incomingChannel.cancel()
        finish(reason)
    }

    /** A single-link transport lost its link on purpose: Closed now, whatever the reader does. */
    private fun endNow(reason: String) {
        if (!markClosing(reason)) return
        TransportLog.i("transport.end", "endpoint" to endpoint, "reason" to reason)
        incomingChannel.cancel()
        finish(reason)
    }

    /**
     * Stops the supervisor for good with [reason] — the Closed reason even if the supervisor,
     * woken by the closing link, gets to finish first; false if something already did.
     */
    private fun markClosing(reason: String): Boolean = lock.withLock {
        if (closing) return false
        closeReason = reason
        closing = true
        wake.signalAll()
        true
    }

    private fun supervise() {
        boostThreadPriority()
        val backoff = Backoff(options.reconnectPolicy)
        var lastError: String? = null
        var failedOpens = 0
        try {
            while (!closing) {
                if (suspended) {
                    publish(ConnectionState.Suspended)
                    waitWhileSuspended()
                    backoff.reset()
                    continue
                }
                publish(ConnectionState.Connecting(backoff.consecutiveFailures + 1))
                when (val attempt = openSafely()) {
                    is LinkAttempt.Gone -> {
                        TransportLog.i("link.gone", "endpoint" to endpoint, "reason" to attempt.reason)
                        finish(attempt.reason)
                        return
                    }
                    is LinkAttempt.Failed -> {
                        lastError = attempt.reason
                        failedOpens++
                        TransportLog.d("link.open-failed", "endpoint" to endpoint, "error" to attempt.reason, "attempt" to failedOpens)
                        if (options.maxOpenAttempts?.let { failedOpens >= it } == true) {
                            finish(attempt.reason)
                            return
                        }
                    }
                    is LinkAttempt.Opened -> {
                        val connection = LinkConnection(connectionIds.incrementAndGet(), attempt.link)
                        current = connection
                        // close(), terminate() or suspend() may have run while this link was
                        // opening, and found no connection to close: do it here.
                        if (closing || suspended) {
                            current = null
                            attempt.link.closeQuietly()
                            continue
                        }
                        failedOpens = 0
                        publish(ConnectionState.Connected(connection.id, attempt.link.peerFingerprint))
                        TransportLog.i("connection.open", "id" to connection.id, "endpoint" to endpoint)
                        val outcome = connection.run()
                        current = null
                        lastError = outcome.error
                        TransportLog.i(
                            "connection.closed", "id" to connection.id, "frames" to outcome.framesReceived,
                            "healthy" to connection.healthy, "reason" to outcome.error,
                        )
                        if (options.singleLink) {
                            finish(if (closing) closeReason ?: "closed" else lastError ?: "disconnected")
                            return
                        }
                        if (connection.healthy) backoff.reset()
                    }
                }
                if (closing) break
                if (suspended) continue
                if (!options.autoReconnect) {
                    finish(lastError ?: "disconnected")
                    return
                }
                val delay = backoff.nextDelayMs()
                publish(ConnectionState.WaitingToRetry(backoff.consecutiveFailures, delay, lastError))
                sleepUnlessInterrupted(delay)
            }
            finish(closeReason ?: "closed")
        } catch (e: Throwable) {
            TransportLog.e("supervisor.crashed", e)
            finish(e.message ?: e.javaClass.simpleName)
        }
    }

    private fun openSafely(): LinkAttempt = try {
        opener.open()
    } catch (e: IOException) {
        LinkAttempt.Failed(e.message ?: e.javaClass.simpleName)
    } catch (e: RuntimeException) {
        LinkAttempt.Failed(e.message ?: e.javaClass.simpleName)
    }

    /** Sleeps [delayMs] unless closed, suspended or asked to [retryNow] meanwhile. */
    private fun sleepUnlessInterrupted(delayMs: Long) {
        lock.withLock {
            var remaining = TimeUnit.MILLISECONDS.toNanos(delayMs)
            while (!closing && !suspended && !retryRequested && remaining > 0) remaining = wake.awaitNanos(remaining)
            retryRequested = false
        }
    }

    private fun waitWhileSuspended() {
        lock.withLock {
            while (suspended && !closing) wake.await()
        }
    }

    /** Sets the state unless the transport already finished: Closed is terminal. */
    private fun publish(state: ConnectionState) = synchronized(mutableState) {
        if (!finished.get()) mutableState.value = state
    }

    private fun finish(reason: String) {
        synchronized(mutableState) {
            if (!finished.compareAndSet(false, true)) return
            mutableState.value = ConnectionState.Closed(reason)
        }
        incomingChannel.close()
    }

    private class Outcome(val framesReceived: Long, val error: String?)

    /** One open link: the supervisor thread reads, a dedicated thread writes. */
    private inner class LinkConnection(val id: Long, private val link: ByteLink) {
        private val queue = SendQueue()
        private val writer = Thread({ writeLoop() }, "$threadPrefix-writer-$id")
        private val readerDone = CountDownLatch(1)

        /** Set by [markHealthy] once the session's handshake completed on this link. */
        @Volatile
        var healthy = false
            set(value) {
                field = value
                watchdogLock.withLock { watchdogWake.signalAll() }
            }

        // Liveness (System.nanoTime, not the injectable clock: the watchdog really waits).

        /**
         * When the read in progress started; 0 while the reader is busy delivering. Only time spent
         * waiting on the link counts as silence: a reader held up by a slow collector isn't the
         * Mac's fault.
         */
        @Volatile
        private var readingSince = 0L

        /** When the write in progress started; 0 while the writer is idle. */
        @Volatile
        private var writingSince = 0L

        @Volatile
        private var ended = false
        private val watchdogLock = ReentrantLock()
        private val watchdogWake = watchdogLock.newCondition()

        @Volatile
        private var failure: String? = null

        fun enqueue(message: Message): Boolean = queue.offer(MessageCodec.encode(message))

        fun enqueueAll(messages: List<Message>): Boolean = queue.offerAll(messages.map(MessageCodec::encode))

        /** Reads until the link ends; returns what happened. */
        fun run(): Outcome {
            writer.isDaemon = true
            writer.start()
            options.silenceTimeoutMs?.let { timeout ->
                thread(name = "$threadPrefix-watchdog-$id", isDaemon = true) { watch(TimeUnit.MILLISECONDS.toNanos(timeout)) }
            }
            var frames = 0L
            try {
                val input = link.input
                val buffer = ByteArray(options.readChunkBytes)
                val decoder = FrameDecoder(allocator = PayloadAllocator.pooledVideo(payloadPool), resyncUntilFirstFrame = options.resyncAtStart)
                var skipReported = false
                while (true) {
                    readingSince = System.nanoTime()
                    val count = input.read(buffer)
                    readingSince = 0L
                    if (count < 0) {
                        if (failure == null) failure = "closed by peer"
                        break
                    }
                    val receivedAt = nanoClock()
                    decoder.feed(buffer, 0, count) { frame ->
                        if (!skipReported) {
                            skipReported = true
                            val skipped = decoder.skippedByteCount
                            if (skipped > 0) TransportLog.w("link.resynced", "id" to id, "skippedBytes" to skipped)
                        }
                        frames++
                        deliver(frame, receivedAt)
                    }
                }
            } catch (e: ProtocolException) {
                // Framing error: the stream is unsynchronised. Tell the Mac and close (§2).
                failure = e.message
                TransportLog.w("frame.invalid", "id" to id, "error" to e.message)
                queue.offer(MessageCodec.encode(ErrorMessage(ErrorCode.BAD_FRAME, e.message ?: "framing error")))
                queue.close()
                writer.join(options.closeDrainTimeoutMs)
            } catch (e: IOException) {
                if (failure == null) failure = e.message ?: e.javaClass.simpleName
            } finally {
                queue.close()
                link.closeQuietly()
                writer.join(options.closeDrainTimeoutMs)
                readerDone.countDown()
                ended = true
                watchdogLock.withLock { watchdogWake.signalAll() }
            }
            return Outcome(frames, failure)
        }

        private fun deliver(frame: Frame, receivedAt: Long) {
            val pooled = if (frame.type == MessageType.VIDEO_FRAME) frame.payload else null
            // While closing or suspending, keep draining (so closing doesn't cut off the Mac before
            // it has read our GOODBYE) but deliver nothing.
            if (closing || suspended || failure != null) {
                pooled?.let(payloadPool::release)
                return
            }
            val message = try {
                MessageCodec.decode(frame)
            } catch (e: ProtocolException) {
                // One bad message: report it and carry on with the next frame. A lost VIDEO_FRAME
                // shows up as a frameId gap, which the session answers with KEYFRAME_REQUEST.
                pooled?.let(payloadPool::release)
                TransportLog.w("message.invalid", "id" to id, "type" to frame.type, "error" to e.message)
                queue.offer(MessageCodec.encode(ErrorMessage(ErrorCode.BAD_FRAME, e.message ?: "invalid message")))
                return
            }
            val incoming = Incoming(id, message, frame.flags, frame.stream, frame.wireSize, receivedAt, pooled, payloadPool)
            // Blocks while the collector is behind, so back-pressure reaches the Mac (§4).
            if (incomingChannel.trySendBlocking(incoming).isClosed) {
                incoming.release()
                throw IOException("transport closed")
            }
        }

        private fun writeLoop() {
            boostThreadPriority()
            try {
                val output = BufferedOutputStream(link.output, 64 * 1024)
                val header = ByteArray(FrameCodec.HEADER_SIZE)
                while (true) {
                    val frame = queue.take() ?: break
                    if (writingSince == 0L) writingSince = System.nanoTime()
                    stampClock(frame)
                    FrameCodec.writeHeader(frame, header)
                    output.write(header)
                    output.write(frame.payload, 0, frame.payloadLength)
                    // Coalesce: one write per burst, e.g. an input batch.
                    if (queue.isEmpty) {
                        output.flush()
                        writingSince = 0L
                    }
                }
                writingSince = System.nanoTime()
                output.flush()
                writingSince = 0L
                link.shutdownOutputQuietly()
            } catch (e: IOException) {
                if (failure == null) failure = "write failed: ${e.message}"
                link.closeQuietly()
            }
        }

        /** PING `t1` / PONG `t3`: "sender clock at send", taken as late as possible (§3.4). */
        private fun stampClock(frame: Frame) {
            val offset = when {
                frame.type == MessageType.PING && frame.payloadLength >= PING_LENGTH -> PING_T1_OFFSET
                frame.type == MessageType.PONG && frame.payloadLength >= PONG_LENGTH -> PONG_T3_OFFSET
                else -> return
            }
            val micros = nanoClock() / 1_000
            for (i in 0 until 8) frame.payload[offset + i] = (micros ushr (56 - 8 * i)).toByte()
        }

        /**
         * Stops accepting messages and lets the queue drain; the writer then half-closes where it
         * can, and the Mac closes its side. Forces the link shut after [timeoutMs]. Doesn't block.
         */
        fun closeGracefully(timeoutMs: Long, reason: String) {
            if (failure == null) failure = reason
            queue.close()
            thread(name = "$threadPrefix-closer-$id", isDaemon = true) {
                val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
                writer.join(timeoutMs)
                val left = TimeUnit.NANOSECONDS.toMillis(deadline - System.nanoTime()).coerceAtLeast(0)
                readerDone.await(left, TimeUnit.MILLISECONDS)
                link.closeQuietly()
            }
        }

        /**
         * [LinkOptions.silenceTimeoutMs] on its own thread, sleeping until the next deadline: the
         * start of the read waiting on the link plus the timeout (on a healthy link), or the start
         * of a blocked write plus the timeout. It wakes about once per timeout while data flows. A wake-up much later
         * than planned means this process was frozen (in the background), which is no fault of
         * the Mac's: the wait starts over.
         */
        private fun watch(timeout: Long) {
            watchdogLock.withLock {
                var planned = System.nanoTime() + timeout
                while (!ended) {
                    val now = System.nanoTime()
                    if (now - planned > STALL_TOLERANCE_NANOS) {
                        if (readingSince != 0L) readingSince = now
                        if (writingSince != 0L) writingSince = now
                    }
                    val writing = writingSince
                    val reading = if (healthy) readingSince else 0L
                    val reason = when {
                        writing != 0L && now - writing >= timeout -> "a write to the Mac was blocked for ${TimeUnit.NANOSECONDS.toMillis(timeout)} ms"
                        reading != 0L && now - reading >= timeout -> "nothing from the Mac for ${TimeUnit.NANOSECONDS.toMillis(timeout)} ms"
                        else -> null
                    }
                    if (reason != null) {
                        TransportLog.w("connection.silent", "id" to id, "reason" to reason)
                        abort(reason)
                        return
                    }
                    planned = minOf(
                        if (reading != 0L) reading + timeout else now + timeout,
                        if (writing != 0L) writing + timeout else Long.MAX_VALUE,
                    )
                    watchdogWake.awaitNanos((planned - now).coerceAtLeast(1))
                }
            }
        }

        /** Closes at once, nothing drained (the peer is gone). */
        fun abort(reason: String) {
            if (failure == null) failure = reason
            queue.close()
            link.closeQuietly()
        }
    }

    private companion object {
        /** A watchdog wake-up this much later than planned means the process was frozen. */
        val STALL_TOLERANCE_NANOS = TimeUnit.SECONDS.toNanos(1)

        const val PING_LENGTH = 12
        const val PING_T1_OFFSET = 4
        const val PONG_LENGTH = 28
        const val PONG_T3_OFFSET = 20
    }
}

internal fun ByteLink.closeQuietly() {
    try {
        close()
    } catch (_: IOException) {
    } catch (_: RuntimeException) {
    }
}

private fun ByteLink.shutdownOutputQuietly() {
    try {
        shutdownOutput()
    } catch (_: IOException) {
    } catch (_: RuntimeException) {
        // For example UnsupportedOperationException from a socket without half-close.
    }
}

/** I/O threads run at display priority: they are on the path to the screen. */
private fun boostThreadPriority() {
    try {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_DISPLAY)
    } catch (e: RuntimeException) {
        TransportLog.w("thread.priority-denied", "error" to e.message)
    }
}
