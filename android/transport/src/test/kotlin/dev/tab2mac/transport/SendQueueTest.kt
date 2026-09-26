package dev.tab2mac.transport

import dev.tab2mac.protocol.Frame
import dev.tab2mac.protocol.FrameFlags
import dev.tab2mac.protocol.MessageType
import dev.tab2mac.protocol.StreamId
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

class SendQueueTest {
    private fun frame(type: MessageType, flags: FrameFlags = FrameFlags.NONE, tag: Int = 0) =
        Frame(type, flags, type.defaultStream, byteArrayOf(tag.toByte()))

    private fun SendQueue.drain(): List<Frame> = generateSequence { poll() }.toList()

    @Test
    fun controlAndInputAreNeverDropped() {
        val queue = SendQueue()
        val frames = List(1_000) { frame(if (it % 2 == 0) MessageType.INPUT else MessageType.KEYFRAME_REQUEST, tag = it) }
        frames.forEach { assertTrue(queue.offer(it)) }
        assertEquals(frames, queue.drain())
        assertEquals(0, queue.droppedCount)
    }

    @Test
    fun aNewReportReplacesAQueuedOne() {
        val queue = SendQueue()
        val input = frame(MessageType.INPUT)
        queue.offer(frame(MessageType.RECEIVER_REPORT, tag = 1))
        queue.offer(input)
        queue.offer(frame(MessageType.RECEIVER_REPORT, tag = 2))
        val drained = queue.drain()
        assertEquals(listOf(input, frame(MessageType.RECEIVER_REPORT, tag = 2)), drained)
        assertEquals(1, queue.droppedCount)
    }

    @Test
    fun videoDropsQueuedDiscardableFramesButNeverKeyframes() {
        val queue = SendQueue()
        val key = frame(MessageType.VIDEO_FRAME, FrameFlags.KEYFRAME, tag = 1)
        val discardable = frame(MessageType.VIDEO_FRAME, FrameFlags.DISCARDABLE, tag = 2)
        val reference = frame(MessageType.VIDEO_FRAME, FrameFlags.NONE, tag = 3)
        val latest = frame(MessageType.VIDEO_FRAME, FrameFlags.DISCARDABLE, tag = 4)
        listOf(key, discardable, reference, latest).forEach { queue.offer(it) }
        assertEquals(listOf(key, reference, latest), queue.drain())
        assertEquals(1, queue.droppedCount)
    }

    @Test
    fun takeBlocksUntilAFrameArrives() {
        val queue = SendQueue()
        val taken = CountDownLatch(1)
        var result: Frame? = null
        thread {
            result = queue.take()
            taken.countDown()
        }
        assertFalse(taken.await(50, TimeUnit.MILLISECONDS))
        val ping = frame(MessageType.PING)
        queue.offer(ping)
        assertTrue(taken.await(2, TimeUnit.SECONDS))
        assertSame(ping, result)
    }

    @Test
    fun closeDrainsThenEnds() {
        val queue = SendQueue()
        val goodbye = frame(MessageType.GOODBYE)
        queue.offer(goodbye)
        queue.close()
        assertFalse(queue.offer(frame(MessageType.PING)))
        assertSame(goodbye, queue.take())
        assertNull(queue.take())
    }
}
