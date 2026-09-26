package dev.tab2mac.transport

import dev.tab2mac.protocol.Frame
import dev.tab2mac.protocol.MessageType
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * The outgoing queue of one connection, with the §4 policies:
 * - control and input messages are never discarded (unbounded, FIFO);
 * - a new RECEIVER_REPORT replaces one that is still queued (latest wins);
 * - a new VIDEO_FRAME drops queued DISCARDABLE video frames, never keyframes (latest frame wins).
 *
 * Thread-safe: any thread offers, one writer thread takes.
 */
class SendQueue {
    /** How an offered frame treats frames already queued. */
    enum class Policy {
        /** Keep everything. */
        RELIABLE,

        /** Replace queued frames of the same type and stream. */
        LATEST_WINS,

        /** Drop queued DISCARDABLE non-key frames of the same stream. */
        VIDEO,
    }

    private val lock = ReentrantLock()
    private val available = lock.newCondition()
    private val items = ArrayDeque<Frame>()
    private var closed = false
    private var dropped = 0L

    /** Whether nothing is waiting. */
    val isEmpty: Boolean get() = lock.withLock { items.isEmpty() }

    /** Frames removed by a latest-wins policy so far. */
    val droppedCount: Long get() = lock.withLock { dropped }

    /** Queues [frame]; false once [close]d. */
    fun offer(frame: Frame): Boolean = lock.withLock {
        if (closed) return false
        enqueueLocked(frame)
        available.signal()
        true
    }

    /** Queues [frames] atomically, so the writer sends them in one write; false once [close]d. */
    fun offerAll(frames: List<Frame>): Boolean = lock.withLock {
        if (closed) return false
        for (frame in frames) enqueueLocked(frame)
        available.signal()
        true
    }

    private fun enqueueLocked(frame: Frame) {
        when (policyFor(frame)) {
            Policy.RELIABLE -> Unit
            Policy.LATEST_WINS -> dropWhere { it.type == frame.type && it.stream == frame.stream }
            Policy.VIDEO -> dropWhere { it.stream == frame.stream && it.flags.isDiscardable && !it.flags.isKeyframe }
        }
        items.addLast(frame)
    }

    private fun dropWhere(predicate: (Frame) -> Boolean) {
        if (items.isEmpty()) return
        val before = items.size
        items.removeAll(predicate)
        dropped += before - items.size
    }

    /** The next frame, blocking while empty; null once closed and drained. */
    fun take(): Frame? = lock.withLock {
        while (items.isEmpty() && !closed) available.await()
        items.removeFirstOrNull()
    }

    /** The next frame without blocking. */
    fun poll(): Frame? = lock.withLock { items.removeFirstOrNull() }

    /** Rejects further offers; queued frames can still be taken. */
    fun close() = lock.withLock {
        closed = true
        available.signalAll()
    }

    companion object {
        /** The §4 policy for [frame]. */
        fun policyFor(frame: Frame): Policy = when (frame.type) {
            MessageType.RECEIVER_REPORT -> Policy.LATEST_WINS
            MessageType.VIDEO_FRAME -> Policy.VIDEO
            else -> Policy.RELIABLE
        }
    }
}
