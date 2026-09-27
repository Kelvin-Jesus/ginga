package dev.ginga.transport

import dev.ginga.protocol.Codec
import dev.ginga.protocol.DisplayDescription
import dev.ginga.protocol.ErrorCode
import dev.ginga.protocol.ErrorMessage
import dev.ginga.protocol.Orientation
import dev.ginga.protocol.PixelDimensions
import dev.ginga.protocol.StreamDescription
import dev.ginga.protocol.Welcome
import dev.ginga.protocol.FrameCodec
import dev.ginga.protocol.FrameDecoder
import dev.ginga.protocol.Goodbye
import dev.ginga.protocol.GoodbyeReason
import dev.ginga.protocol.Hello
import dev.ginga.protocol.Message
import dev.ginga.protocol.MessageCodec
import dev.ginga.protocol.Ping
import dev.ginga.protocol.Pong
import dev.ginga.protocol.StreamFormat
import dev.ginga.protocol.TransportKind
import dev.ginga.protocol.VersionRange
import dev.ginga.protocol.VideoFrame
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.thread
import kotlin.concurrent.withLock
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Test

/**
 * [AccessoryTransport] over a fake accessory link that behaves like the kernel's `f_accessory`:
 * a read returns at most 16 KiB and never spans two of the Mac's bulk transfers, and a pending
 * read doesn't return when the link is closed locally (the worst case), only when the Mac sends
 * or the cable is pulled.
 */
class AccessoryTransportTest {
    private val transports = mutableListOf<AccessoryTransport>()

    @After
    fun tearDown() {
        transports.forEach { it.close() }
    }

    /**
     * The tablet's view of the accessory's bulk pipes; the test plays the Mac. With
     * [closeWakesRead], closing wakes a pending read as on Android (the descriptor's close signals
     * blocked threads); without, it is the worst case.
     */
    private class FakeAccessoryLink(
        private val closeWakesRead: Boolean = false,
        /** Writes never complete (the Mac stopped reading), until the link is closed. */
        private val writeBlocks: Boolean = false,
    ) : ByteLink {
        private val lock = ReentrantLock()
        private val changed = lock.newCondition()
        private val transfers = ArrayDeque<ByteArray>()
        private var head: ByteArray? = null
        private var headOffset = 0
        private var unplugged = false
        private val written = ByteArrayOutputStream()
        private val sizes = mutableListOf<Int>()

        @Volatile
        var closed = false
            private set

        /** Sizes of the reads that returned data. */
        val readSizes: List<Int> get() = lock.withLock { sizes.toList() }

        /** The Mac writes [messages] in one bulk transfer. */
        fun macWrites(vararg messages: Message) {
            val bytes = messages.map { FrameCodec.encode(MessageCodec.encode(it)) }.reduce(ByteArray::plus)
            lock.withLock {
                transfers.addLast(bytes)
                changed.signalAll()
            }
        }

        /** Raw bytes in one bulk transfer (for example the tail of an earlier link's write). */
        fun macWritesRaw(bytes: ByteArray) = lock.withLock {
            transfers.addLast(bytes)
            changed.signalAll()
        }

        /** The cable is pulled: the pending read fails, as `f_accessory` fails it with EIO. */
        fun unplug() = lock.withLock {
            unplugged = true
            changed.signalAll()
        }

        /** Everything the tablet has written so far, decoded. */
        fun tabletMessages(): List<Message> {
            val bytes = synchronized(written) { written.toByteArray() }
            return FrameDecoder().feed(bytes).map(MessageCodec::decode)
        }

        override val input: InputStream = object : InputStream() {
            override fun read(): Int = throw UnsupportedOperationException("the transport reads in chunks")

            override fun read(b: ByteArray, off: Int, len: Int): Int {
                lock.lock()
                try {
                    while (true) {
                        if (unplugged) throw IOException("read failed: EIO (I/O error)")
                        if (closed && closeWakesRead) throw IOException("read interrupted")
                        val transfer = head ?: transfers.removeFirstOrNull()?.also {
                            head = it
                            headOffset = 0
                        }
                        if (transfer != null) {
                            val count = minOf(len, BULK_BUFFER_SIZE, transfer.size - headOffset)
                            System.arraycopy(transfer, headOffset, b, off, count)
                            headOffset += count
                            if (headOffset == transfer.size) head = null
                            sizes += count
                            return count
                        }
                        changed.await() // close() deliberately doesn't wake this
                    }
                } finally {
                    lock.unlock()
                }
            }
        }

        override val output: OutputStream = object : OutputStream() {
            override fun write(b: Int) = write(byteArrayOf(b.toByte()), 0, 1)

            override fun write(b: ByteArray, off: Int, len: Int) {
                if (writeBlocks) {
                    lock.withLock { while (!closed && !unplugged) changed.await() }
                }
                if (closed || unplugged) throw IOException("write failed: EIO (I/O error)")
                synchronized(written) { written.write(b, off, len) }
            }
        }

        override fun close() {
            closed = true
            if (closeWakesRead || writeBlocks) lock.withLock { changed.signalAll() }
        }
    }

    /** Hands out [attempts] in order, then reports the accessory gone. */
    private class ScriptedOpener(vararg attempts: LinkAttempt) : LinkOpener {
        private val script = ArrayDeque(attempts.toList())
        val calls = AtomicInteger()

        override fun open(): LinkAttempt {
            calls.incrementAndGet()
            return synchronized(script) { script.removeFirstOrNull() } ?: LinkAttempt.Gone("script ended")
        }
    }

    private fun transport(
        opener: LinkOpener,
        maxOpenAttempts: Int = 4,
        policy: ReconnectPolicy = ReconnectPolicy(initialDelayMs = 5, maxDelayMs = 20),
    ) = AccessoryTransport(
        opener,
        AccessoryTransport.SINGLE_LINK_OPTIONS.copy(
            reconnectPolicy = policy,
            maxOpenAttempts = maxOpenAttempts,
            closeDrainTimeoutMs = 200,
        ),
    ).also { transports += it }

    private fun AccessoryTransport.awaitConnected(): Long = runBlocking {
        withTimeout(5_000) { (state.first { it is ConnectionState.Connected } as ConnectionState.Connected).connectionId }
    }

    private fun AccessoryTransport.awaitClosed(timeoutMs: Long = 5_000): ConnectionState.Closed = runBlocking {
        withTimeout(timeoutMs) { state.first { it is ConnectionState.Closed } as ConnectionState.Closed }
    }

    private fun FakeAccessoryLink.awaitTabletMessages(count: Int): List<Message> {
        val deadline = System.nanoTime() + 5_000_000_000L
        while (true) {
            val messages = tabletMessages()
            if (messages.size >= count || System.nanoTime() > deadline) return messages
            Thread.sleep(5)
        }
    }

    private val hello = Hello(
        versions = VersionRange(1, 1),
        app = Hello.App("Ginga for Android", "0.1.0"),
        device = Hello.Device("samsung", "SM-X730", "16", "id"),
        display = Hello.Display(2560, 1600, 274, listOf(60.0, 120.0), 0),
        decoders = emptyList(),
        transport = TransportKind.AOA,
    )

    @Test(timeout = 20_000)
    fun reassemblesFramesSplitAcross16KiBReads() {
        val link = FakeAccessoryLink()
        val transport = transport(ScriptedOpener(LinkAttempt.Opened(link)))
        transport.connect()
        val id = transport.awaitConnected()

        val format = StreamFormat(Codec.HEVC, 2560, 1600, listOf(ByteArray(24) { it.toByte() }, ByteArray(9) { 7 }))
        val keyframe = VideoFrame(1, 1_000, 4, isKeyframe = true, data = ByteArray(100_000) { (it * 31).toByte() })
        val delta = VideoFrame(2, 17_667, 3, isKeyframe = false, data = ByteArray(20_000) { (it * 7).toByte() })
        // One transfer whose frames straddle the 16 KiB read boundaries, then one per message.
        link.macWrites(format, keyframe, delta)
        link.macWrites(Ping(1, 2))
        link.macWrites(Goodbye(GoodbyeReason.SHUTDOWN))

        val received = runBlocking { withTimeout(5_000) { transport.incoming.take(5).toList() } }
        assertEquals(listOf(format, keyframe, delta, Ping(1, 2), Goodbye(GoodbyeReason.SHUTDOWN)), received.map { it.message })
        assertTrue(received.all { it.connectionId == id })
        assertTrue(received[1].flags.isKeyframe)
        received.forEach(Incoming::release)

        val sizes = link.readSizes
        assertTrue(sizes.all { it <= BULK_BUFFER_SIZE }, "$sizes")
        assertTrue(sizes.count { it == BULK_BUFFER_SIZE } >= 7, "the video needed many full reads: $sizes")
    }

    @Test(timeout = 20_000)
    fun writesWhatTheSessionSendsHelloFirst() {
        val link = FakeAccessoryLink()
        val transport = transport(ScriptedOpener(LinkAttempt.Opened(link)))
        transport.connect()
        val id = transport.awaitConnected()

        assertTrue(transport.send(hello, id))
        assertTrue(transport.send(Ping(1, 0), id))
        val written = link.awaitTabletMessages(2)
        assertEquals(TransportKind.AOA, assertIs<Hello>(written[0]).transport)
        assertEquals(1, assertIs<Ping>(written[1]).id)
    }

    @Test(timeout = 20_000)
    fun detachEndsAtOnceWhileAReadIsPending() {
        val link = FakeAccessoryLink()
        val opener = ScriptedOpener(LinkAttempt.Opened(link))
        val transport = transport(opener)
        transport.connect()
        val id = transport.awaitConnected()
        Thread.sleep(50) // the reader is now blocked in read(), which close() won't wake

        transport.onAccessoryDetached()
        assertEquals(ConnectionState.Closed(AccessoryTransport.DETACHED), transport.awaitClosed(timeoutMs = 500))
        assertTrue(link.closed)
        assertFalse(transport.send(Ping(2, 0), id))
        // Completes (cancelled: nothing is delivered after the end) instead of waiting for the read.
        assertEquals(emptyList(), runBlocking { withTimeout(1_000) { transport.incoming.catch { }.toList() } })
        transport.onAccessoryDetached() // idempotent
        Thread.sleep(50)
        assertEquals(1, opener.calls.get(), "never reopened")
    }

    @Test(timeout = 20_000)
    fun theLinkFailingClosesTheTransportWithoutReopening() {
        val link = FakeAccessoryLink()
        val opener = ScriptedOpener(LinkAttempt.Opened(link), LinkAttempt.Opened(FakeAccessoryLink()))
        val transport = transport(opener)
        transport.connect()
        transport.awaitConnected()

        link.unplug() // the kernel fails the pending read before the detach broadcast arrives
        val closed = transport.awaitClosed()
        assertTrue(closed.reason.orEmpty().contains("EIO"), "$closed")
        Thread.sleep(50)
        assertEquals(1, opener.calls.get(), "a USB accessory link is never reopened")
    }

    @Test(timeout = 20_000)
    fun aGoneAccessoryClosesWithoutRetrying() {
        val opener = ScriptedOpener(LinkAttempt.Gone("no access to the USB accessory"))
        val transport = transport(opener)
        transport.connect()
        assertEquals(ConnectionState.Closed("no access to the USB accessory"), transport.awaitClosed())
        Thread.sleep(50)
        assertEquals(1, opener.calls.get())
    }

    @Test(timeout = 20_000)
    fun aBusyAccessoryIsRetriedUntilItOpens() {
        val busy = LinkAttempt.Failed("could not open the USB accessory (busy)")
        val link = FakeAccessoryLink()
        val opener = ScriptedOpener(busy, busy, LinkAttempt.Opened(link))
        val transport = transport(opener)
        transport.connect()
        transport.awaitConnected()
        assertEquals(3, opener.calls.get())
    }

    @Test(timeout = 20_000)
    fun aBusyAccessoryIsGivenUpAfterTheLastAttempt() {
        val busy = LinkAttempt.Failed("could not open the USB accessory (busy)")
        val opener = ScriptedOpener(busy, busy, busy, busy, LinkAttempt.Opened(FakeAccessoryLink()))
        val transport = transport(opener, maxOpenAttempts = 3)
        transport.connect()
        assertEquals(ConnectionState.Closed(busy.reason), transport.awaitClosed())
        Thread.sleep(50)
        assertEquals(3, opener.calls.get())
    }

    @Test(timeout = 20_000)
    fun aLocalDropFlushesAndEndsWithoutWaitingForTheRead() {
        val link = FakeAccessoryLink()
        val opener = ScriptedOpener(LinkAttempt.Opened(link))
        val transport = transport(opener)
        transport.connect()
        val id = transport.awaitConnected()

        assertTrue(transport.send(Goodbye(GoodbyeReason.ERROR), id))
        transport.dropConnection(id, "no WELCOME within 5 s")
        assertEquals(ConnectionState.Closed("no WELCOME within 5 s"), transport.awaitClosed(timeoutMs = 500))
        assertEquals(listOf<Message>(Goodbye(GoodbyeReason.ERROR)), link.awaitTabletMessages(1))
        Thread.sleep(50)
        assertEquals(1, opener.calls.get(), "never reopened")
    }

    @Test(timeout = 20_000)
    fun suspendingEndsTheTransportSinceItCannotResume() {
        val link = FakeAccessoryLink()
        val transport = transport(ScriptedOpener(LinkAttempt.Opened(link)))
        transport.connect()
        val id = transport.awaitConnected()
        assertTrue(transport.send(Goodbye(GoodbyeReason.USER), id))
        transport.suspend()
        assertEquals(ConnectionState.Closed("suspended"), transport.awaitClosed(timeoutMs = 500))
        transport.resume() // no effect
        assertIs<ConnectionState.Closed>(transport.state.value)
        assertEquals(listOf<Message>(Goodbye(GoodbyeReason.USER)), link.awaitTabletMessages(1))
    }

    @Test(timeout = 20_000)
    fun afterADisconnectANewTransportReopensTheAccessoryAndSaysHelloAgain() {
        // The device node stays busy until the previous descriptor is closed, like f_accessory.
        val first = FakeAccessoryLink()
        val second = FakeAccessoryLink()
        val links = ArrayDeque(listOf(first, second))
        var inUse: FakeAccessoryLink? = null
        val opener = LinkOpener {
            synchronized(links) {
                if (inUse?.closed == false) return@LinkOpener LinkAttempt.Failed("could not open the USB accessory (busy)")
                LinkAttempt.Opened(links.removeFirst().also { inUse = it })
            }
        }

        val before = transport(opener)
        before.connect()
        val firstId = before.awaitConnected()
        assertTrue(before.send(Goodbye(GoodbyeReason.USER), firstId))
        before.close() // Disconnect: GOODBYE, then the descriptor is closed (the read is stuck: after the drain timeout)

        // Retries (0, 50, 150, 350 ms) outlast the 200 ms drain, as the defaults (1.75 s) outlast 300 ms.
        val after = transport(opener, policy = ReconnectPolicy(initialDelayMs = 50, maxDelayMs = 200))
        after.connect()
        val secondId = after.awaitConnected()
        assertTrue(after.send(hello, secondId))
        assertEquals(listOf<Message>(Goodbye(GoodbyeReason.USER)), first.awaitTabletMessages(1))
        assertTrue(first.closed)
        assertEquals(TransportKind.AOA, assertIs<Hello>(second.awaitTabletMessages(1).single()).transport)
    }

    // "Reconnect automatically": reopened while attached

    private fun reconnecting(opener: LinkOpener, silenceTimeoutMs: Long? = null) = AccessoryTransport(
        opener,
        AccessoryTransport.RECONNECTING_OPTIONS.copy(
            reconnectPolicy = ReconnectPolicy(initialDelayMs = 5, maxDelayMs = 20),
            closeDrainTimeoutMs = 100,
            silenceTimeoutMs = silenceTimeoutMs,
        ),
    ).also { transports += it }

    private fun AccessoryTransport.awaitConnected(after: Long): Long = runBlocking {
        withTimeout(5_000) { (state.first { it is ConnectionState.Connected && it.connectionId > after } as ConnectionState.Connected).connectionId }
    }

    // A fresh link may start with leftovers of the previous one

    private val welcome = Welcome(
        1, "s1", Welcome.Mac("MacBook Air", "26.6.2", "0.3.0"),
        DisplayDescription(17, "Galaxy Tab S11", PixelDimensions(1280, 800), true, 60.0, Orientation.LANDSCAPE),
        StreamDescription(Codec.HEVC, 2560, 1600, 60.0, 40_000),
    )

    @Test(timeout = 20_000)
    fun aLinkThatStartsWithLeftoverBytesResynchronisesOnTheFirstFrame() {
        val link = FakeAccessoryLink()
        val transport = reconnecting(ScriptedOpener(LinkAttempt.Opened(link)))
        transport.connect()
        transport.awaitConnected()
        link.macWritesRaw(byteArrayOf(0xB0.toByte(), 0xB4.toByte()) + ByteArray(300) { (it * 13).toByte() }) // "bad magic 0xb0b4"
        link.macWrites(welcome, Ping(9, 1))
        val received = runBlocking { withTimeout(5_000) { transport.incoming.take(2).toList() } }
        assertEquals(listOf<Message>(welcome, Ping(9, 1)), received.map { it.message })
    }

    @Test(timeout = 20_000)
    fun afterTheFirstFrameGarbageIsStillAFramingError() {
        val link = FakeAccessoryLink()
        val transport = transport(ScriptedOpener(LinkAttempt.Opened(link)))
        transport.connect()
        transport.awaitConnected()
        link.macWrites(welcome)
        link.macWritesRaw(ByteArray(12) { 0x7F })
        val closed = transport.awaitClosed()
        assertTrue(closed.reason.orEmpty().contains("bad magic"), "$closed")
        assertEquals(ErrorCode.BAD_FRAME, assertIs<ErrorMessage>(link.awaitTabletMessages(1).single()).code)
    }

    // Liveness: a Mac that went away over USB (no FIN, reads never return, writes stop completing)

    @Test(timeout = 20_000)
    fun aMacThatStopsReadingIsDroppedEvenWhileAWriteIsBlockedAndTheAccessoryReopens() {
        val stuck = FakeAccessoryLink(closeWakesRead = true, writeBlocks = true)
        val fresh = FakeAccessoryLink(closeWakesRead = true)
        val opener = ScriptedOpener(LinkAttempt.Opened(stuck), LinkAttempt.Opened(fresh))
        val transport = reconnecting(opener, silenceTimeoutMs = 200)
        transport.connect()
        val firstId = transport.awaitConnected()
        transport.markHealthy(firstId) // streaming
        assertTrue(transport.send(Ping(1, 0), firstId)) // this write never completes

        val secondId = transport.awaitConnected(after = firstId)
        assertTrue(stuck.closed, "torn down, which unblocks its reader and writer")
        assertTrue(transport.send(hello, secondId))
        assertEquals(TransportKind.AOA, assertIs<Hello>(fresh.awaitTabletMessages(1).single()).transport)
    }

    @Test(timeout = 20_000)
    fun aSilentMacIsDroppedAndTheAccessoryReopens() {
        val silent = FakeAccessoryLink(closeWakesRead = true)
        val opener = ScriptedOpener(LinkAttempt.Opened(silent), LinkAttempt.Opened(FakeAccessoryLink(closeWakesRead = true)))
        val transport = reconnecting(opener, silenceTimeoutMs = 200)
        transport.connect()
        val firstId = transport.awaitConnected()
        transport.markHealthy(firstId)
        transport.awaitConnected(after = firstId)
        assertTrue(silent.closed)
    }

    @Test(timeout = 20_000)
    fun dataFromTheMacKeepsTheLinkAlive() {
        val link = FakeAccessoryLink(closeWakesRead = true)
        val opener = ScriptedOpener(LinkAttempt.Opened(link), LinkAttempt.Opened(FakeAccessoryLink()))
        val transport = reconnecting(opener, silenceTimeoutMs = 200)
        transport.connect()
        val id = transport.awaitConnected()
        transport.markHealthy(id)
        val received = AtomicInteger()
        thread(isDaemon = true) { runBlocking { transport.incoming.collect { received.incrementAndGet(); it.release() } } }
        repeat(16) {
            link.macWrites(Pong(it.toLong(), 0, 0, 0)) // the Mac answers the 1 Hz PING, faster here
            Thread.sleep(50)
        }
        assertEquals(1, opener.calls.get())
        assertFalse(link.closed)
        assertEquals(16, received.get(), "the session got every answer")
    }

    @Test(timeout = 20_000)
    fun silenceBeforeTheHandshakeIsNotAVerdict() {
        // HELLO waits for the Mac as long as it takes over USB; only a blocked write would count.
        val link = FakeAccessoryLink(closeWakesRead = true)
        val opener = ScriptedOpener(LinkAttempt.Opened(link), LinkAttempt.Opened(FakeAccessoryLink()))
        val transport = reconnecting(opener, silenceTimeoutMs = 150)
        transport.connect()
        transport.awaitConnected()
        Thread.sleep(600)
        assertEquals(1, opener.calls.get())
        assertFalse(link.closed)
    }

    @Test(timeout = 20_000)
    fun aSilentMacEndsASingleLinkTransport() {
        val link = FakeAccessoryLink(closeWakesRead = true)
        val transport = AccessoryTransport(
            ScriptedOpener(LinkAttempt.Opened(link)),
            AccessoryTransport.SINGLE_LINK_OPTIONS.copy(silenceTimeoutMs = 150),
        ).also { transports += it }
        transport.connect()
        transport.markHealthy(transport.awaitConnected())
        val closed = transport.awaitClosed()
        assertEquals("nothing from the Mac for 150 ms", closed.reason)
    }

    @Test(timeout = 20_000)
    fun reconnectingReopensTheFreshLinkTheMacOffersAndSaysHelloAgain() {
        val first = FakeAccessoryLink(closeWakesRead = true)
        val second = FakeAccessoryLink(closeWakesRead = true)
        val opener = ScriptedOpener(LinkAttempt.Opened(first), LinkAttempt.Opened(second))
        val transport = reconnecting(opener)
        transport.connect()
        val firstId = transport.awaitConnected()

        // The session drops the link (the Mac said GOODBYE shutdown, or went silent).
        transport.dropConnection(firstId, "goodbye shutdown")
        val secondId = runBlocking {
            withTimeout(5_000) { (transport.state.first { it is ConnectionState.Connected && it.connectionId > firstId } as ConnectionState.Connected).connectionId }
        }
        assertTrue(first.closed)
        assertTrue(transport.send(hello, secondId))
        assertEquals(TransportKind.AOA, assertIs<Hello>(second.awaitTabletMessages(1).single()).transport)
        assertEquals(2, opener.calls.get())
    }

    @Test(timeout = 20_000)
    fun reconnectingStopsWhenTheAccessoryDetaches() {
        val opener = ScriptedOpener(LinkAttempt.Opened(FakeAccessoryLink(closeWakesRead = true)), LinkAttempt.Opened(FakeAccessoryLink()))
        val transport = reconnecting(opener)
        transport.connect()
        transport.awaitConnected()
        transport.onAccessoryDetached()
        assertEquals(ConnectionState.Closed(AccessoryTransport.DETACHED), transport.awaitClosed(timeoutMs = 500))
        Thread.sleep(100)
        assertEquals(1, opener.calls.get(), "never reopened after a detach")
    }

    @Test(timeout = 20_000)
    fun reconnectingStopsWhenTheAccessoryIsGone() {
        val link = FakeAccessoryLink()
        val opener = ScriptedOpener(LinkAttempt.Opened(link), LinkAttempt.Gone(AccessoryTransport.DETACHED))
        val transport = reconnecting(opener)
        transport.connect()
        transport.awaitConnected()
        link.unplug() // the kernel fails the read before the detach broadcast
        assertEquals(ConnectionState.Closed(AccessoryTransport.DETACHED), transport.awaitClosed())
        assertEquals(2, opener.calls.get())
    }

    @Test(timeout = 20_000)
    fun reconnectingKeepsTryingABusyAccessory() {
        val busy = LinkAttempt.Failed("could not open the USB accessory (busy)")
        val opener = ScriptedOpener(busy, busy, busy, busy, busy, busy, LinkAttempt.Opened(FakeAccessoryLink()))
        val transport = reconnecting(opener)
        transport.connect()
        transport.awaitConnected()
        assertEquals(7, opener.calls.get(), "no attempt limit while attached")
    }

    @Test(timeout = 20_000)
    fun aLinkThatOpensAfterCloseIsClosedAndTheStateStaysClosed() {
        val link = FakeAccessoryLink()
        val opening = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = transport(
            LinkOpener {
                opening.countDown()
                release.await()
                LinkAttempt.Opened(link)
            },
        )
        transport.connect()
        opening.await()
        transport.close()
        release.countDown()
        Thread.sleep(100)
        assertEquals(ConnectionState.Closed("closed"), transport.state.value)
        assertTrue(link.closed, "nobody else would ever close it")
    }

    @Test
    fun rejectsInvalidOptions() {
        assertFailsWith<IllegalArgumentException> { LinkOptions(readChunkBytes = 4_096) }
        assertFailsWith<IllegalArgumentException> { LinkOptions(maxOpenAttempts = 0) }
    }

    @Test(timeout = 20_000)
    fun pongsAreStampedWhenWritten() {
        val link = FakeAccessoryLink()
        val transport = AccessoryTransport(ScriptedOpener(LinkAttempt.Opened(link)), nanoClock = { 9_000_000L }).also { transports += it }
        transport.connect()
        val id = transport.awaitConnected()
        assertTrue(transport.send(Pong(3, 10, 20, 0), id))
        assertEquals(Pong(3, 10, 20, 9_000), link.awaitTabletMessages(1).single())
    }

    private companion object {
        /** `f_accessory`'s BULK_BUFFER_SIZE. */
        const val BULK_BUFFER_SIZE = 16 * 1024
    }
}
