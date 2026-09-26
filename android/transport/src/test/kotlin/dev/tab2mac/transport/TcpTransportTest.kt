package dev.tab2mac.transport

import dev.tab2mac.protocol.ErrorCode
import dev.tab2mac.protocol.ErrorMessage
import dev.tab2mac.protocol.Frame
import dev.tab2mac.protocol.FrameCodec
import dev.tab2mac.protocol.FrameDecoder
import dev.tab2mac.protocol.Goodbye
import dev.tab2mac.protocol.GoodbyeReason
import dev.tab2mac.protocol.Message
import dev.tab2mac.protocol.MessageCodec
import dev.tab2mac.protocol.Ping
import dev.tab2mac.protocol.Pong
import dev.tab2mac.protocol.VideoFrame
import java.io.EOFException
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Test

/** Runs [TcpTransport] against a real loopback socket standing in for the Mac. */
class TcpTransportTest {
    private val server = ServerSocket(0, 4, InetAddress.getLoopbackAddress())
    private val transports = mutableListOf<TcpTransport>()

    @After
    fun tearDown() {
        transports.forEach { it.close() }
        server.close()
    }

    private fun transport(
        autoReconnect: Boolean = true,
        policy: ReconnectPolicy = ReconnectPolicy(initialDelayMs = 10, maxDelayMs = 40),
        nanoClock: () -> Long = System::nanoTime,
        silenceTimeoutMs: Long? = 5_000,
    ) = TcpTransport(
        TcpTransportConfig(
            port = server.localPort,
            autoReconnect = autoReconnect,
            reconnectPolicy = policy,
            closeDrainTimeoutMs = 500,
            silenceTimeoutMs = silenceTimeoutMs,
        ),
        nanoClock,
    ).also { transports += it }

    private fun TcpTransport.awaitRetry(minimumAttempt: Int): ConnectionState.WaitingToRetry = runBlocking {
        withTimeout(10_000) {
            state.first { it is ConnectionState.WaitingToRetry && it.attempt >= minimumAttempt } as ConnectionState.WaitingToRetry
        }
    }

    private fun accept(): Socket = server.accept().apply { soTimeout = 5_000 }

    private fun TcpTransport.awaitConnected(after: Long = 0): Long = runBlocking {
        withTimeout(5_000) {
            (state.first { it is ConnectionState.Connected && it.connectionId > after } as ConnectionState.Connected).connectionId
        }
    }

    private fun Socket.readMessage(decoder: FrameDecoder): Message {
        val buffer = ByteArray(1)
        while (true) {
            val count = getInputStream().read(buffer)
            if (count < 0) throw EOFException()
            val frames = decoder.feed(buffer, 0, count)
            if (frames.isNotEmpty()) return MessageCodec.decode(frames.single())
        }
    }

    private fun Socket.write(vararg messages: Message) {
        val bytes = messages.map { FrameCodec.encode(MessageCodec.encode(it)) }.reduce(ByteArray::plus)
        getOutputStream().apply { write(bytes); flush() }
    }

    @Test(timeout = 20_000)
    fun sendsAndReceivesFramedMessages() {
        val transport = transport()
        transport.connect()
        val peer = accept()
        val id = transport.awaitConnected()

        assertTrue(transport.send(Ping(1, 2), id))
        assertEquals(1, assertIs<Ping>(peer.readMessage(FrameDecoder())).id, "t1 is stamped at write time")

        val video = VideoFrame(7, 123, 4, isKeyframe = true, data = ByteArray(300_000) { it.toByte() })
        peer.write(Pong(1, 2, 3, 4), video, Goodbye(GoodbyeReason.SHUTDOWN))
        val received = runBlocking { withTimeout(5_000) { transport.incoming.take(3).toList() } }
        assertEquals(listOf<Message>(Pong(1, 2, 3, 4), video, Goodbye(GoodbyeReason.SHUTDOWN)), received.map { it.message })
        assertTrue(received.all { it.connectionId == id })
        assertTrue(received[1].flags.isKeyframe)
        assertEquals(FrameCodec.HEADER_SIZE + 18 + 300_000, received[1].wireSize)
    }

    @Test(timeout = 20_000)
    fun aSilentMacIsDroppedAndReconnected() {
        val transport = transport(silenceTimeoutMs = 200)
        transport.connect()
        val silent = accept() // accepts, then never sends or answers
        val first = transport.awaitConnected()
        transport.markHealthy(first)
        accept()
        assertTrue(transport.awaitConnected(after = first) > first)
        val eof = try {
            silent.getInputStream().read()
        } catch (_: java.io.IOException) {
            -1
        }
        assertEquals(-1, eof, "the tablet closed the silent connection")
    }

    @Test(timeout = 20_000)
    fun retryNowSkipsTheBackoffWait() {
        val transport = transport(policy = ReconnectPolicy(initialDelayMs = 60_000, maxDelayMs = 60_000))
        transport.connect()
        accept().close() // refused, e.g. without the adb loopback token
        val waiting = transport.awaitRetry(minimumAttempt = 1)
        assertEquals(60_000, waiting.delayMs)
        transport.retryNow() // a new token arrived
        accept()
        assertTrue(transport.awaitConnected(after = 1) > 1)
    }

    @Test(timeout = 20_000)
    fun reconnectsWithANewConnectionIdAndRejectsStaleSends() {
        val transport = transport()
        transport.connect()
        val first = accept()
        val firstId = transport.awaitConnected()
        first.write(Pong(1, 1, 1, 1))
        runBlocking { withTimeout(5_000) { transport.incoming.first() } }
        first.close()

        val second = accept()
        val secondId = transport.awaitConnected(after = firstId)
        assertTrue(secondId > firstId)
        assertFalse(transport.send(Ping(9, 9), firstId), "a message for the old connection must not leak")
        assertTrue(transport.send(Ping(10, 10), secondId))
        assertEquals(10, assertIs<Ping>(second.readMessage(FrameDecoder())).id)
    }

    @Test(timeout = 20_000)
    fun staysClosedWhenReconnectionIsOff() {
        val transport = transport(autoReconnect = false)
        transport.connect()
        accept().close()
        val closed = runBlocking { withTimeout(5_000) { transport.state.first { it is ConnectionState.Closed } } }
        assertIs<ConnectionState.Closed>(closed)
        assertFalse(transport.send(Ping(1, 1)))
    }

    @Test(timeout = 20_000)
    fun answersAFramingErrorWithErrorAndCloses() {
        val transport = transport(autoReconnect = false)
        transport.connect()
        val peer = accept()
        transport.awaitConnected()
        peer.getOutputStream().apply { write(ByteArray(12) { 0x7F }); flush() }

        val decoder = FrameDecoder()
        val error = assertIs<ErrorMessage>(peer.readMessage(decoder))
        assertEquals(ErrorCode.BAD_FRAME, error.code)
        assertEquals(-1, peer.getInputStream().read())
    }

    @Test(timeout = 20_000)
    fun reportsAnUndecodableMessageButKeepsTheConnection() {
        val transport = transport()
        transport.connect()
        val peer = accept()
        transport.awaitConnected()
        val broken = Frame(dev.tab2mac.protocol.MessageType.WELCOME, dev.tab2mac.protocol.FrameFlags.NONE,
            dev.tab2mac.protocol.StreamId.CONTROL, "{".encodeToByteArray())
        peer.getOutputStream().apply { write(FrameCodec.encode(broken)); flush() }
        peer.write(Pong(5, 5, 5, 5))

        val decoder = FrameDecoder()
        assertEquals(ErrorCode.BAD_FRAME, assertIs<ErrorMessage>(peer.readMessage(decoder)).code)
        val next = runBlocking { withTimeout(5_000) { transport.incoming.first() } }
        assertEquals(Pong(5, 5, 5, 5), next.message)
    }

    @Test(timeout = 30_000)
    fun aMacThatRejectsTheTabletIsRetriedWithGrowingDelays() {
        // The Mac's fail(): ERROR + GOODBYE "error" + close, before any WELCOME.
        val rejecting = thread {
            try {
                while (true) {
                    server.accept().use { peer ->
                        peer.write(ErrorMessage(ErrorCode.INTERNAL, "cannot create display"), Goodbye(GoodbyeReason.ERROR))
                    }
                }
            } catch (_: java.io.IOException) {
                // server closed by tearDown
            }
        }
        val policy = ReconnectPolicy(initialDelayMs = 50, maxDelayMs = 400)
        val transport = transport(policy = policy)
        transport.connect()
        val third = transport.awaitRetry(minimumAttempt = 3)
        assertEquals(policy.delayMs(third.attempt), third.delayMs, "backoff keeps growing: no reset without a handshake")
        transport.close()
        server.close()
        rejecting.join(5_000)
    }

    @Test(timeout = 20_000)
    fun aHealthyConnectionResetsTheBackoff() {
        val policy = ReconnectPolicy(initialDelayMs = 50, maxDelayMs = 400)
        val transport = transport(policy = policy)
        transport.connect()
        accept().close() // unhealthy: attempt 1
        assertEquals(1, transport.awaitRetry(1).attempt)
        val peer = accept()
        val id = transport.awaitConnected()
        transport.markHealthy(id)
        peer.close()
        // The state has moved past the first retry (it reached Connected), so this is the second one.
        val retry = transport.awaitRetry(minimumAttempt = 1)
        assertEquals(1, retry.attempt, "reset after WELCOME, so the next retry is quick")
        assertEquals(50, retry.delayMs)
    }

    @Test(timeout = 20_000)
    fun suspendFlushesClosesAndHoldsUntilResume() {
        val transport = transport()
        transport.connect()
        val peer = accept()
        val id = transport.awaitConnected()
        assertTrue(transport.send(Goodbye(GoodbyeReason.USER), id))
        transport.suspend()
        assertEquals(Goodbye(GoodbyeReason.USER), peer.readMessage(FrameDecoder()))
        assertEquals(-1, peer.getInputStream().read())
        runBlocking { withTimeout(5_000) { transport.state.first { it == ConnectionState.Suspended } } }

        server.soTimeout = 300
        assertFailsWith<java.net.SocketTimeoutException>("no reconnection while suspended") { server.accept() }
        server.soTimeout = 0

        transport.resume()
        accept()
        assertTrue(transport.awaitConnected(after = id) > id)
    }

    @Test(timeout = 20_000)
    fun pingAndPongClocksAreStampedAtWriteTime() {
        val transport = transport(nanoClock = { 7_000_000L })
        transport.connect()
        val peer = accept()
        val id = transport.awaitConnected()
        assertTrue(transport.send(Ping(1, 999), id))
        assertTrue(transport.send(Pong(2, 10, 20, 999), id))
        val decoder = FrameDecoder()
        assertEquals(Ping(1, 7_000), peer.readMessage(decoder))
        assertEquals(Pong(2, 10, 20, 7_000), peer.readMessage(decoder))
    }

    @Test(timeout = 20_000)
    fun closeFlushesQueuedMessagesFirst() {
        val transport = transport()
        transport.connect()
        val peer = accept()
        val id = transport.awaitConnected()
        assertTrue(transport.send(Goodbye(GoodbyeReason.USER), id))
        transport.close()

        val decoder = FrameDecoder()
        assertEquals(Goodbye(GoodbyeReason.USER), peer.readMessage(decoder))
        assertEquals(-1, peer.getInputStream().read())
        val closed = runBlocking { withTimeout(5_000) { transport.state.first { it is ConnectionState.Closed } } }
        assertIs<ConnectionState.Closed>(closed)
    }
}
