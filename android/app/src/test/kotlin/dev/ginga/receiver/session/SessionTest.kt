package dev.ginga.receiver.session

import dev.ginga.protocol.ByteArrayPool
import dev.ginga.protocol.Codec
import dev.ginga.protocol.Configure
import dev.ginga.protocol.DirectLink
import dev.ginga.protocol.CursorPosition
import dev.ginga.protocol.CursorShape
import dev.ginga.protocol.DisplayDescription
import dev.ginga.protocol.ErrorCode
import dev.ginga.protocol.ErrorMessage
import dev.ginga.protocol.Feature
import dev.ginga.protocol.Fingerprint
import dev.ginga.protocol.FrameFlags
import dev.ginga.protocol.Goodbye
import dev.ginga.protocol.GoodbyeReason
import dev.ginga.protocol.Hello
import dev.ginga.protocol.InputAction
import dev.ginga.protocol.InputKind
import dev.ginga.protocol.InputMessage
import dev.ginga.protocol.KeyAction
import dev.ginga.protocol.KeyMessage
import dev.ginga.protocol.KeyframeReason
import dev.ginga.protocol.KeyframeRequest
import dev.ginga.protocol.Message
import dev.ginga.protocol.MessageType
import dev.ginga.protocol.Orientation
import dev.ginga.protocol.Pairing
import dev.ginga.protocol.PairingState
import dev.ginga.protocol.PixelDimensions
import dev.ginga.protocol.Ping
import dev.ginga.protocol.Pong
import dev.ginga.protocol.ReceiverReport
import dev.ginga.protocol.StreamDescription
import dev.ginga.protocol.StreamFormat
import dev.ginga.protocol.StreamId
import dev.ginga.protocol.TransportKind
import dev.ginga.protocol.UnknownMessage
import dev.ginga.protocol.VersionRange
import dev.ginga.protocol.VideoFrame
import dev.ginga.protocol.Welcome
import dev.ginga.transport.ConnectionState
import dev.ginga.transport.Incoming
import dev.ginga.transport.Transport
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.emptyFlow

class SessionTest {

    private class FakeTransport : Transport {
        override val endpoint = "fake://mac"
        override val state: StateFlow<ConnectionState> = MutableStateFlow(ConnectionState.Idle)
        override val incoming: Flow<Incoming> = emptyFlow()
        var current: Long? = null
        val sent = mutableListOf<Pair<Long, Message>>()
        val batches = mutableListOf<List<Message>>()
        val dropped = mutableListOf<Long>()
        val healthy = mutableListOf<Long>()
        var closed = false
        var suspended = false
        var resumes = 0

        override fun connect() = Unit

        override fun send(message: Message, connectionId: Long?): Boolean {
            val id = current ?: return false
            if (closed || (connectionId != null && connectionId != id)) return false
            sent += id to message
            return true
        }

        override fun sendBatch(messages: List<Message>, connectionId: Long?): Boolean {
            val id = current ?: return false
            if (closed || (connectionId != null && connectionId != id)) return false
            batches += messages
            messages.forEach { sent += id to it }
            return true
        }

        override fun dropConnection(connectionId: Long, reason: String) {
            dropped += connectionId
        }

        override fun markHealthy(connectionId: Long) {
            healthy += connectionId
        }

        override fun suspend() {
            suspended = true
        }

        override fun resume() {
            suspended = false
            resumes++
        }

        override fun close() {
            closed = true
        }

        inline fun <reified T : Message> sentOf(): List<T> = sent.map { it.second }.filterIsInstance<T>()

        fun clear() = sent.clear()
    }

    private class FakeVideo : VideoSink {
        val formats = mutableListOf<StreamFormat>()
        val frames = mutableListOf<VideoFrame>()
        val owners = mutableListOf<AutoCloseable>()
        var stops = 0

        override fun onStreamFormat(format: StreamFormat, stream: StreamDescription) {
            formats += format
        }

        override fun onVideoFrame(frame: VideoFrame, receivedAtNanos: Long, owner: AutoCloseable) {
            frames += frame
            owners += owner
        }

        override fun onStreamStopped() {
            stops++
        }
    }

    private class FakeStats : SessionStats {
        var bytes = 0L
        var frames = 0
        val reports = mutableListOf<Pair<Long?, Long?>>()
        override var lastDecodedFrameId: Long? = 41

        override fun onMessageReceived(wireSize: Int) {
            bytes += wireSize
        }

        override fun onVideoFrameReceived(frameId: Long) {
            frames++
        }

        override fun intervalReport(clockOffsetUs: Long?, rttUs: Long?): ReceiverReport {
            reports += clockOffsetUs to rttUs
            return ReceiverReport(framesReceived = frames, clockOffsetUs = clockOffsetUs, rttUs = rttUs)
        }
    }

    private class FakeListener : SessionListener {
        val states = mutableListOf<SessionState>()
        val offsets = mutableListOf<Long>()
        val errors = mutableListOf<ErrorMessage>()

        override fun onStateChanged(state: SessionState) {
            states += state
        }

        override fun onClockSync(offsetUs: Long, rttUs: Long) {
            offsets += offsetUs
        }

        override fun onRemoteError(error: ErrorMessage) {
            errors += error
        }
    }

    private var nowNanos = TimeUnit.SECONDS.toNanos(100)
    private val transport = FakeTransport()
    private val video = FakeVideo()
    private val stats = FakeStats()
    private val listener = FakeListener()
    private val resumeTokens = mutableListOf<String?>()
    private val session = Session(
        transport = transport,
        hello = { resume -> resumeTokens += resume; hello(resume) },
        video = video,
        stats = stats,
        clock = { nowNanos },
        listener = listener,
    )

    private val display = DisplayDescription(17, "Galaxy Tab S11", PixelDimensions(1280, 800), true, 60.0, Orientation.LANDSCAPE)
    private val stream = StreamDescription(Codec.HEVC, 2560, 1600, 60.0, 40_000)
    private val welcome = Welcome(1, "b3f1", Welcome.Mac("MacBook Air", "26.6.2", "0.3.0"), display, stream, listOf(Feature.CLOCK_SYNC))
    private val pausingWelcome = welcome.copy(features = listOf(Feature.CLOCK_SYNC, Feature.PAUSE))
    private val format = StreamFormat(Codec.HEVC, 2560, 1600, listOf(byteArrayOf(0x40, 0x01)))

    private fun hello(resume: String?) = Hello(
        versions = VersionRange(1, 1),
        app = Hello.App("test", "0"),
        device = Hello.Device("samsung", "SM-X730", "16", "id"),
        display = Hello.Display(2560, 1600, 274, listOf(60.0, 120.0), 0),
        decoders = emptyList(),
        transport = TransportKind.ADB_TCP,
        resume = resume?.let(Hello::Resume),
    )

    private fun connect(id: Long) {
        transport.current = id
        session.onConnectionState(ConnectionState.Connected(id))
    }

    private fun receive(
        message: Message,
        connectionId: Long = transport.current ?: 1,
        flags: FrameFlags = FrameFlags.NONE,
        receivedAtNanos: Long = nowNanos,
    ) {
        session.onIncoming(Incoming(connectionId, message, flags, StreamId.CONTROL, 100, receivedAtNanos))
    }

    private fun advanceMillis(ms: Long) {
        nowNanos += TimeUnit.MILLISECONDS.toNanos(ms)
        session.onTick()
    }

    /** Streaming on connection [id] with the stream screen open. */
    private fun streaming(id: Long = 1, welcomeMessage: Welcome = welcome) {
        session.onVideoSurfaceChanged(true)
        connect(id)
        receive(welcomeMessage)
        transport.clear()
    }

    private fun frame(id: Long, keyframe: Boolean = false) = VideoFrame(id, 10 * id, 5, isKeyframe = keyframe, data = ByteArray(4))

    /** The Mac answers the latest PING, as it always does within milliseconds. */
    private fun macAnswers() {
        val ping = transport.sentOf<Ping>().lastOrNull() ?: return
        receive(Pong(ping.id, ping.t1, ping.t1 + 100, ping.t1 + 150))
    }

    // Handshake and connection lifecycle

    @Test
    fun sendsHelloOnEveryNewConnection() {
        connect(1)
        assertIs<Hello>(transport.sent.single().second)
        assertEquals(1L, transport.sent.single().first)
        assertEquals(SessionState.Handshaking(1), session.state)

        session.onConnectionState(ConnectionState.Connected(1)) // conflated repeat: no second HELLO
        assertEquals(1, transport.sentOf<Hello>().size)
    }

    @Test
    fun welcomeStartsStreamingClockSyncAndMarksTheConnectionHealthy() {
        connect(1)
        assertTrue(transport.healthy.isEmpty(), "not healthy before WELCOME")
        receive(welcome)
        val state = assertIs<SessionState.Streaming>(session.state)
        assertEquals(welcome, state.welcome)
        assertEquals(listOf(1L), transport.healthy)
        assertEquals(1, transport.sentOf<Ping>().size)
    }

    @Test
    fun messagesFromAnOldConnectionAreIgnored() {
        streaming(id = 1)
        connect(2)
        receive(welcome, connectionId = 1)
        assertIs<SessionState.Handshaking>(session.state)
        receive(welcome, connectionId = 2)
        assertIs<SessionState.Streaming>(session.state)
    }

    @Test
    fun reconnectionStopsTheStreamAndResumesTheSession() {
        streaming(id = 1)
        session.onConnectionState(ConnectionState.WaitingToRetry(1, 250, "closed by peer"))
        assertEquals(SessionState.Idle, session.state)
        assertEquals(1, video.stops)
        connect(2)
        assertEquals(listOf(null, "b3f1"), resumeTokens)
        assertEquals("b3f1", transport.sentOf<Hello>().last().resume?.session)
    }

    @Test
    fun handshakeTimesOutOnce() {
        connect(1)
        advanceMillis(4_900)
        assertTrue(transport.dropped.isEmpty())
        advanceMillis(200)
        advanceMillis(200)
        assertEquals(listOf(1L), transport.dropped)
    }

    @Test
    fun incompatibleVersionEndsTheSession() {
        connect(1)
        receive(welcome.copy(version = 2))
        assertEquals(ErrorCode.INCOMPATIBLE_VERSION, transport.sentOf<ErrorMessage>().single().code)
        assertEquals(GoodbyeReason.ERROR, transport.sentOf<Goodbye>().single().reason)
        assertTrue(transport.closed)
        assertIs<SessionState.Ended>(session.state)
    }

    @Test
    fun aRefusalBeforeWelcomeIsFinal() {
        for (code in listOf(ErrorCode.INTERNAL, ErrorCode.UNSUPPORTED)) {
            val transport = FakeTransport()
            val session = Session(transport, ::hello, FakeVideo(), FakeStats(), { nowNanos }, FakeListener())
            transport.current = 1
            session.onConnectionState(ConnectionState.Connected(1))
            session.onIncoming(Incoming(1, ErrorMessage(code, "cannot create display"), FrameFlags.NONE, StreamId.CONTROL, 50, nowNanos))
            val ended = assertIs<SessionState.Ended>(session.state)
            assertTrue("cannot create display" in ended.reason, ended.reason)
            assertTrue(transport.closed, "no retry storm: the Mac would refuse again")
        }
    }

    @Test
    fun unauthorizedIsRetriedNotFinal() {
        // adb-tcp without the Mac's current loopback token: ERROR unauthorized, then GOODBYE error.
        connect(1)
        receive(ErrorMessage(ErrorCode.UNAUTHORIZED, "missing or wrong loopback token"))
        assertEquals(SessionState.Handshaking(1), session.state)
        assertEquals(ErrorCode.UNAUTHORIZED, listener.errors.single().code)
        receive(Goodbye(GoodbyeReason.ERROR))
        assertEquals(SessionState.Idle, session.state)
        assertEquals(listOf(1L), transport.dropped, "the transport reconnects with backoff")
        assertFalse(transport.closed)
        connect(2)
        assertEquals(2, transport.sentOf<Hello>().size, "a new HELLO, with whatever token is known by then")
    }

    @Test
    fun errorsAfterWelcomeAreOnlyReported() {
        streaming()
        receive(ErrorMessage(ErrorCode.INTERNAL, "encoder hiccup"))
        receive(ErrorMessage(ErrorCode.BAD_FRAME, "oops"))
        assertEquals(listOf(ErrorCode.INTERNAL, ErrorCode.BAD_FRAME), listener.errors.map { it.code })
        assertIs<SessionState.Streaming>(session.state)
        assertFalse(transport.closed)
    }

    @Test
    fun goodbyeReplacedOrUserEndsForGood() {
        streaming()
        receive(Goodbye(GoodbyeReason.REPLACED))
        assertIs<SessionState.Ended>(session.state)
        assertTrue(transport.closed)
        // Ended is terminal.
        session.onConnectionState(ConnectionState.Connected(5))
        assertIs<SessionState.Ended>(session.state)
    }

    @Test
    fun anyOtherGoodbyeDropsTheConnectionAndWaitsForTheMac() {
        streaming()
        receive(Goodbye(GoodbyeReason.SHUTDOWN))
        assertEquals(SessionState.Idle, session.state)
        assertEquals(listOf(1L), transport.dropped)
        assertFalse(transport.closed)
        assertEquals(1, video.stops)

        // The Mac's fail(): ERROR bad-frame + GOODBYE error before WELCOME.
        connect(2)
        receive(ErrorMessage(ErrorCode.BAD_FRAME, "bad hello"))
        receive(Goodbye(GoodbyeReason.ERROR))
        assertEquals(listOf(1L, 2L), transport.dropped)
        assertEquals(listOf(1L), transport.healthy, "connection 2 never becomes healthy, so the backoff grows")
    }

    @Test
    fun transportClosedEndsTheSession() {
        streaming()
        session.onConnectionState(ConnectionState.Closed("closed by peer"))
        assertIs<SessionState.Ended>(session.state)
    }

    @Test
    fun closeSaysGoodbyeAndClosesTheTransport() {
        streaming()
        session.close()
        assertEquals(GoodbyeReason.USER, transport.sentOf<Goodbye>().single().reason)
        assertTrue(transport.closed)
        assertIs<SessionState.Ended>(session.state)
        assertEquals(1, video.stops)
    }

    // Timers and clock sync

    @Test
    fun pingsAndReportsOncePerSecondTogether() {
        streaming()
        assertEquals(TimeUnit.SECONDS.toNanos(1), session.nanosUntilNextTick())
        advanceMillis(999)
        assertTrue(transport.sent.isEmpty(), "nothing before the deadline")
        advanceMillis(1)
        assertEquals(1, transport.sentOf<Ping>().size)
        assertEquals(1, transport.sentOf<ReceiverReport>().size)
        assertEquals(TimeUnit.SECONDS.toNanos(1), session.nanosUntilNextTick(), "one wake-up per second")
        advanceMillis(1_000)
        assertEquals(2, transport.sentOf<Ping>().size)
        assertEquals(2, transport.sentOf<ReceiverReport>().size)
    }

    @Test
    fun schedulesNothingWhileIdleOrAfterAHandshakeTimeout() {
        assertNull(session.nanosUntilNextTick())
        connect(1)
        assertEquals(TimeUnit.SECONDS.toNanos(5), session.nanosUntilNextTick())
        advanceMillis(5_000)
        assertEquals(listOf(1L), transport.dropped)
        assertNull(session.nanosUntilNextTick())
    }

    @Test
    fun pongYieldsTheClockOffsetMacMinusAndroid() {
        session.onVideoSurfaceChanged(true)
        connect(1)
        receive(welcome)
        val ping = transport.sentOf<Ping>().single()
        // Mac clock = Android clock + 5 s; 200 µs each way; 50 µs on the Mac. The transport
        // stamps t1 at write time, so the PONG echoes whatever went out.
        val t2 = ping.t1 + 200 + 5_000_000
        val t3 = t2 + 50
        nowNanos += TimeUnit.MICROSECONDS.toNanos(450)
        receive(Pong(ping.id, ping.t1, t2, t3))
        assertEquals(5_000_000, session.clockOffsetUs)
        assertEquals(listOf(5_000_000L), listener.offsets)

        advanceMillis(1_000)
        assertEquals(5_000_000L to 400L, stats.reports.last())
    }

    @Test
    fun ignoresPongsItDidNotAskFor() {
        streaming()
        receive(Pong(999, 1, 2, 3))
        assertNull(session.clockOffsetUs)
    }

    @Test
    fun answersPingsFromTheMac() {
        streaming()
        val receivedAt = nowNanos
        nowNanos += 30_000 // the session handles the PING 30 µs after the socket read
        receive(Ping(7, 123), receivedAtNanos = receivedAt)
        val pong = transport.sentOf<Pong>().single()
        assertEquals(Pong(7, 123, receivedAt / 1_000, nowNanos / 1_000), pong)
    }

    // Video

    @Test
    fun forwardsFormatAndFramesToTheVideoSink() {
        streaming()
        receive(format)
        val keyframe = frame(1, keyframe = true)
        receive(keyframe, flags = FrameFlags.KEYFRAME)
        assertEquals(listOf(format), video.formats)
        assertEquals(listOf(keyframe), video.frames)
        assertEquals(1, stats.frames)
        assertEquals(format, assertIs<SessionState.Streaming>(session.state).format)
    }

    @Test
    fun rejectsStreamFormatsWithImpossibleSizes() {
        streaming()
        receive(StreamFormat(Codec.HEVC, 0, 1600, emptyList()))
        receive(StreamFormat(Codec.HEVC, 2560, 100_000, emptyList()))
        assertTrue(video.formats.isEmpty())
        assertEquals(listOf(ErrorCode.BAD_FRAME, ErrorCode.BAD_FRAME), transport.sentOf<ErrorMessage>().map { it.code })
    }

    @Test
    fun framesBeforeWelcomeAreIgnoredAndReleased() {
        val pool = ByteArrayPool(minArraySize = 1024)
        val buffer = pool.acquire(1024)
        connect(1)
        session.onIncoming(Incoming(1, frame(1, keyframe = true), FrameFlags.KEYFRAME, StreamId.VIDEO, 100, nowNanos, buffer, pool))
        assertTrue(video.frames.isEmpty())
        assertTrue(pool.acquire(1024) === buffer)
    }

    @Test
    fun theVideoSinkOwnsTheFramesItReceives() {
        val pool = ByteArrayPool(minArraySize = 1024)
        streaming()
        val buffer = pool.acquire(1024)
        session.onIncoming(Incoming(1, frame(1, keyframe = true), FrameFlags.KEYFRAME, StreamId.VIDEO, 100, nowNanos, buffer, pool))
        assertTrue(pool.acquire(1024) !== buffer, "not released until the sink is done")
        video.owners.single().close()
        assertTrue(pool.acquire(1024) === buffer)

        val stale = pool.acquire(1024)
        session.onIncoming(Incoming(99, frame(2), FrameFlags.NONE, StreamId.VIDEO, 100, nowNanos, stale, pool))
        assertTrue(pool.acquire(1024) === stale, "frames from an old connection are released")
    }

    @Test
    fun aGapInFrameIdsRequestsAKeyframe() {
        streaming()
        receive(format)
        receive(frame(1, keyframe = true))
        receive(frame(2))
        assertTrue(transport.sentOf<KeyframeRequest>().isEmpty())
        receive(frame(4)) // frame 3 was lost (e.g. dropped as malformed by the transport)
        assertEquals(KeyframeReason.LOSS, transport.sentOf<KeyframeRequest>().single().reason)

        nowNanos += TimeUnit.SECONDS.toNanos(1)
        receive(frame(9, keyframe = true)) // a keyframe resynchronises: no request
        receive(format) // so does a new format
        receive(frame(20, keyframe = true))
        assertEquals(1, transport.sentOf<KeyframeRequest>().size)
    }

    @Test
    fun keyframeRequestsAreRateLimited() {
        streaming()
        session.requestKeyframe(KeyframeReason.STARTUP)
        session.requestKeyframe(KeyframeReason.DECODER_ERROR)
        nowNanos += TimeUnit.MILLISECONDS.toNanos(600)
        session.requestKeyframe(KeyframeReason.LOSS)
        val requests = transport.sentOf<KeyframeRequest>()
        assertEquals(listOf(KeyframeReason.STARTUP, KeyframeReason.LOSS), requests.map { it.reason })
        assertEquals(41L, requests.first().lastDecodedFrameId)
    }

    // Input and configuration

    @Test
    fun inputFlowsOnlyWhileStreamingAsOneBatchPerEvent() {
        val input = InputMessage(0, 1, InputKind.TOUCH, InputAction.DOWN, emptyList())
        session.onVideoSurfaceChanged(true)
        connect(1)
        assertFalse(session.sendInputs(listOf(input)))
        receive(welcome)
        assertTrue(session.sendInputs(listOf(input, input.copy(sequence = 1))))
        assertEquals(2, transport.batches.single().size, "a MotionEvent's samples go out as one batch")
        assertFalse(session.sendInputs(emptyList()))
        session.onConnectionState(ConnectionState.WaitingToRetry(1, 250, null))
        assertFalse(session.sendInputs(listOf(input)))
    }

    @Test
    fun orientationIsRequestedAfterWelcomeWhenItDiffers() {
        session.desiredOrientation = Orientation.PORTRAIT
        session.preferredRefreshRate = 120.0
        session.onVideoSurfaceChanged(true)
        connect(1)
        receive(welcome)
        val request = transport.sentOf<Configure>().single().request
        assertEquals(Orientation.PORTRAIT, request?.orientation)
        assertEquals(120.0, request?.refreshRate)
    }

    @Test
    fun noRefreshRateIsRequestedByDefault() {
        streaming()
        assertTrue(transport.sentOf<Configure>().isEmpty(), "the Mac decides")
    }

    @Test
    fun rotatingThereAndBackIsSentEveryTime() {
        streaming() // WELCOME: landscape
        session.requestOrientation(Orientation.PORTRAIT)
        // The Mac may or may not announce the change; either way rotating back must be sent.
        session.requestOrientation(Orientation.LANDSCAPE)
        session.requestOrientation(Orientation.LANDSCAPE) // no-op
        receive(Configure(display = display.copy(orientation = Orientation.LANDSCAPE)))
        session.requestOrientation(Orientation.PORTRAIT)
        assertEquals(
            listOf(Orientation.PORTRAIT, Orientation.LANDSCAPE, Orientation.PORTRAIT),
            transport.sentOf<Configure>().map { it.request?.orientation },
        )
        assertEquals(Orientation.LANDSCAPE, assertIs<SessionState.Streaming>(session.state).display.orientation)
    }

    // Direct link key (§6b)

    @Test
    fun theDirectKeyIsHandedOnOnlyWhileStreaming() {
        val keys = mutableListOf<DirectLink>()
        val keeping = Session(transport, ::hello, video, stats, { nowNanos }, object : SessionListener {
            override fun onStateChanged(state: SessionState) = Unit

            override fun onDirectLink(message: DirectLink) {
                keys += message
            }
        })
        transport.current = 1
        keeping.onConnectionState(ConnectionState.Connected(1))
        val key = DirectLink("0102030405060708", "55".repeat(32))
        keeping.onIncoming(Incoming(1, key, FrameFlags.IGNORABLE, StreamId.CONTROL, 100, nowNanos))
        assertTrue(keys.isEmpty(), "not before WELCOME")
        keeping.onIncoming(Incoming(1, welcome, FrameFlags.NONE, StreamId.CONTROL, 100, nowNanos))
        keeping.onIncoming(Incoming(1, key, FrameFlags.IGNORABLE, StreamId.CONTROL, 100, nowNanos))
        assertEquals(listOf(key), keys)
    }

    // Keyboard (§3.3c)

    @Test
    fun keysGoToAMacThatListedKeyboardWhileStreaming() {
        assertFalse(session.sendKey(true, 0x04, 0, 1), "nothing before streaming")
        streaming(welcomeMessage = welcome.copy(features = listOf(Feature.CLOCK_SYNC, Feature.KEYBOARD)))
        assertTrue(session.sendKey(true, 0x04, 0x02, 1_000))
        assertTrue(session.sendKey(false, 0x04, 0x02, 2_000))
        assertEquals(
            listOf(KeyMessage(0, 1_000, KeyAction.DOWN, 0x04, 0x02), KeyMessage(1, 2_000, KeyAction.UP, 0x04, 0x02)),
            transport.sentOf<KeyMessage>(),
        )
    }

    @Test
    fun keysStayOnTheTabletForAMacWithoutKeyboard() {
        streaming() // WELCOME without "keyboard"
        assertFalse(session.sendKey(true, 0x04, 0, 1))
        assertTrue(transport.sentOf<KeyMessage>().isEmpty())
    }

    // Cursor side channel (§3.3b)

    private class FakeCursor : CursorSink {
        val events = mutableListOf<String>()

        override fun onCursorShape(shape: CursorShape) {
            events += "shape ${shape.shapeId}"
        }

        override fun onCursor(position: CursorPosition) {
            events += "at ${position.x},${position.y} shape ${position.shapeId} visible ${position.visible}"
        }

        override fun onCursorReset() {
            events += "reset"
        }
    }

    @Test
    fun theCursorGoesToItsSinkWhileStreamingAndResetsWithTheStream() {
        val cursor = FakeCursor()
        val drawing = Session(transport, ::hello, video, stats, { nowNanos }, listener, cursor = cursor)
        transport.current = 1
        drawing.onConnectionState(ConnectionState.Connected(1))
        val shape = CursorShape(7, 34, 44, 8, 6, byteArrayOf(1))
        val position = CursorPosition(3, 5_000_789, 32768, 32768, visible = true, shapeId = 7)
        drawing.onIncoming(Incoming(1, position, FrameFlags.IGNORABLE, StreamId.CURSOR, 36, nowNanos))
        assertTrue(cursor.events.isEmpty(), "nothing before WELCOME")

        drawing.onIncoming(Incoming(1, welcome, FrameFlags.NONE, StreamId.CONTROL, 100, nowNanos))
        drawing.onIncoming(Incoming(1, shape, FrameFlags.IGNORABLE, StreamId.CURSOR, 27, nowNanos))
        drawing.onIncoming(Incoming(1, position, FrameFlags.IGNORABLE, StreamId.CURSOR, 36, nowNanos))
        drawing.onConnectionState(ConnectionState.WaitingToRetry(1, 250, "reset"))
        assertEquals(listOf("shape 7", "at 32768,32768 shape 7 visible true", "reset"), cursor.events)
    }

    // USB accessory: no handshake timeout

    @Test
    fun withoutAHandshakeTimeoutHelloWaitsForTheMac() {
        val patient = Session(transport, ::hello, video, stats, { nowNanos }, listener, config = SessionConfig(handshakeTimeoutNanos = null))
        transport.current = 1
        patient.onConnectionState(ConnectionState.Connected(1))
        assertEquals(SessionState.Handshaking(1), patient.state)
        assertNull(patient.nanosUntilNextTick(), "nothing scheduled while waiting")
        nowNanos += TimeUnit.MINUTES.toNanos(5)
        patient.onTick()
        assertTrue(transport.dropped.isEmpty())
        patient.onIncoming(Incoming(1, welcome, FrameFlags.NONE, StreamId.CONTROL, 100, nowNanos))
        assertIs<SessionState.Streaming>(patient.state)
    }

    // Wi‑Fi pairing (§6): commit, nonce, reveal, confirm, paired

    private val macFingerprint = Fingerprint.fromBytes(ByteArray(32) { 0x11 })
    private val tabletFingerprint = Fingerprint.fromBytes(ByteArray(32) { 0x22 })
    private val macNonceHex = "33".repeat(32)
    private val pinned = mutableListOf<Pair<Fingerprint, String>>()
    private var noncesDrawn = 0

    /** A session over TLS, connected (connection 1) to the Mac with [macFingerprint]; the tablet's nonce is 32 × 0x44. */
    private fun wifiSession(): Session = Session(
        transport, ::hello, video, stats, { nowNanos }, listener,
        pairing = PairingContext(
            tabletFingerprint = tabletFingerprint,
            isPinned = { mac -> pinned.any { it.first == mac } },
            onPaired = { mac, name -> pinned += mac to name },
            newNonce = {
                noncesDrawn++
                ByteArray(32) { 0x44 }
            },
        ),
    ).also {
        transport.current = 1
        it.onConnectionState(ConnectionState.Connected(1, macFingerprint))
        transport.clear()
    }

    private fun Session.receive(message: Message) = onIncoming(Incoming(1, message, FrameFlags.NONE, StreamId.CONTROL, 60, nowNanos))

    /** Steps 1–4: `required`, the tablet's `commit`, the Mac's `nonce`, the tablet's `reveal`. */
    private fun Session.exchangeNonces(): Session = apply {
        receive(Pairing(PairingState.REQUIRED, "Kelvin's MacBook Air"))
        receive(Pairing(PairingState.NONCE, nonce = macNonceHex))
    }

    private fun assertPairingFailed(session: Session, reason: String) {
        assertEquals(listOf(PairingState.REJECTED), transport.sentOf<Pairing>().map { it.state }.takeLast(1))
        assertEquals(GoodbyeReason.ERROR, transport.sentOf<Goodbye>().single().reason)
        assertEquals(SessionState.Ended("pairing failed: $reason"), session.state)
        assertTrue(transport.closed)
        assertTrue(pinned.isEmpty())
    }

    @Test
    fun pairingCommitsRevealsShowsTheCodeAndPinsTheMac() {
        val wifi = wifiSession()
        wifi.receive(Pairing(PairingState.REQUIRED, "Kelvin's MacBook Air"))
        // Step 2, with the §6 vector: FPs 32 × 0x11 / 0x22, tablet nonce 32 × 0x44.
        assertEquals(
            Pairing(PairingState.COMMIT, commitment = "052c957131b84f9b12e9519024c730dbf4fa95abac4b8d2e5b1118b2cef8ec89"),
            transport.sentOf<Pairing>().single(),
        )
        assertEquals(SessionState.Pairing(1, "Kelvin's MacBook Air", code = null), wifi.state, "no code before the Mac's nonce")
        wifi.confirmPairing()
        assertEquals(1, transport.sentOf<Pairing>().size, "nothing to confirm yet")
        assertEquals(TimeUnit.SECONDS.toNanos(120), wifi.nanosUntilNextTick(), "the pairing timeout replaces the handshake timeout")

        wifi.receive(Pairing(PairingState.NONCE, nonce = macNonceHex))
        assertEquals(Pairing(PairingState.REVEAL, nonce = "44".repeat(32)), transport.sentOf<Pairing>().last())
        assertEquals(SessionState.Pairing(1, "Kelvin's MacBook Air", code = "053656"), wifi.state)

        wifi.confirmPairing()
        wifi.confirmPairing() // a second tap sends nothing
        assertEquals(listOf(PairingState.COMMIT, PairingState.REVEAL, PairingState.CONFIRMED), transport.sentOf<Pairing>().map { it.state })
        assertTrue(assertIs<SessionState.Pairing>(wifi.state).confirmed)
        assertTrue(pinned.isEmpty(), "nothing is pinned before the Mac's user confirms too")

        wifi.receive(Pairing(PairingState.PAIRED, "Kelvin's MacBook Air"))
        assertEquals(listOf(macFingerprint to "Kelvin's MacBook Air"), pinned)
        assertEquals(SessionState.Handshaking(1), wifi.state)
        assertEquals(TimeUnit.SECONDS.toNanos(5), wifi.nanosUntilNextTick(), "WELCOME is due now")
        wifi.receive(welcome)
        assertIs<SessionState.Streaming>(wifi.state)
    }

    @Test
    fun cancellingPairingDeclinesAsTheUser() {
        val wifi = wifiSession().exchangeNonces()
        wifi.rejectPairing()
        assertEquals(PairingState.REJECTED, transport.sentOf<Pairing>().last().state)
        assertEquals(GoodbyeReason.USER, transport.sentOf<Goodbye>().single().reason)
        assertEquals(SessionState.Ended("pairing cancelled"), wifi.state)
        assertTrue(transport.closed, "no reconnection into another pairing prompt")
        assertTrue(pinned.isEmpty())
    }

    @Test
    fun disconnectingWhilePairingDeclinesFirst() {
        val wifi = wifiSession()
        wifi.receive(Pairing(PairingState.REQUIRED, "Mac"))
        wifi.close()
        assertEquals(PairingState.REJECTED, transport.sentOf<Pairing>().last().state)
        assertEquals(GoodbyeReason.USER, transport.sentOf<Goodbye>().single().reason)
    }

    @Test
    fun theMacDecliningEndsTheSession() {
        val wifi = wifiSession().exchangeNonces()
        wifi.confirmPairing()
        wifi.receive(Pairing(PairingState.REJECTED))
        assertEquals(SessionState.Ended("the Mac declined pairing"), wifi.state)
        assertTrue(transport.closed)
        assertTrue(pinned.isEmpty())
    }

    @Test
    fun aNonceBeforeRequiredEndsTheAttempt() {
        val wifi = wifiSession()
        wifi.receive(Pairing(PairingState.NONCE, nonce = macNonceHex))
        assertPairingFailed(wifi, "unexpected nonce")
    }

    @Test
    fun aRepeatedNonceEndsTheAttempt() {
        val wifi = wifiSession().exchangeNonces()
        wifi.receive(Pairing(PairingState.NONCE, nonce = "55".repeat(32)))
        assertPairingFailed(wifi, "unexpected nonce")
    }

    @Test
    fun aMalformedNonceEndsTheAttempt() {
        val wifi = wifiSession()
        wifi.receive(Pairing(PairingState.REQUIRED, "Mac"))
        wifi.receive(Pairing(PairingState.NONCE, nonce = "33".repeat(31)))
        assertPairingFailed(wifi, "malformed nonce")
    }

    @Test
    fun aRepeatedRequiredEndsTheAttempt() {
        val wifi = wifiSession()
        wifi.receive(Pairing(PairingState.REQUIRED, "Mac"))
        wifi.receive(Pairing(PairingState.REQUIRED, "Mac"))
        assertPairingFailed(wifi, "unexpected required")
    }

    @Test
    fun pairedBeforeTheTabletConfirmedEndsTheAttempt() {
        val wifi = wifiSession().exchangeNonces()
        wifi.receive(Pairing(PairingState.PAIRED, "Mac"))
        assertPairingFailed(wifi, "unexpected paired")
    }

    @Test
    fun anAttemptTimesOutAfterTwoMinutes() {
        val wifi = wifiSession().exchangeNonces()
        nowNanos += TimeUnit.SECONDS.toNanos(119)
        wifi.onTick()
        assertIs<SessionState.Pairing>(wifi.state)
        nowNanos += TimeUnit.SECONDS.toNanos(1)
        wifi.onTick()
        assertPairingFailed(wifi, "pairing timed out")
    }

    @Test
    fun unknownPairingStatesAreIgnored() {
        val wifi = wifiSession()
        wifi.receive(Pairing(PairingState.REQUIRED, "Mac"))
        wifi.receive(Pairing(PairingState("handshake-v2")))
        wifi.receive(Pairing(PairingState.COMMIT, commitment = "00".repeat(32))) // tablet → Mac, echoed
        assertEquals(SessionState.Pairing(1, "Mac"), wifi.state)
        assertEquals(1, transport.sentOf<Pairing>().size)
    }

    @Test
    fun eachAttemptCommitsToAFreshNonce() {
        val wifi = wifiSession()
        wifi.receive(Pairing(PairingState.REQUIRED, "Mac"))
        wifi.onConnectionState(ConnectionState.WaitingToRetry(1, 250, "reset"))
        assertEquals(SessionState.Idle, wifi.state)
        transport.current = 2
        wifi.onConnectionState(ConnectionState.Connected(2, macFingerprint))
        wifi.onIncoming(Incoming(2, Pairing(PairingState.REQUIRED, "Mac"), FrameFlags.NONE, StreamId.CONTROL, 60, nowNanos))
        assertEquals(2, noncesDrawn)
        assertEquals(SessionState.Pairing(2, "Mac"), wifi.state)
    }

    @Test
    fun aMacThatSkipsPairingWithoutAPinIsNotTrusted() {
        val wifi = wifiSession()
        wifi.receive(welcome)
        assertEquals(GoodbyeReason.ERROR, transport.sentOf<Goodbye>().single().reason)
        val ended = assertIs<SessionState.Ended>(wifi.state)
        assertTrue("Forget this tablet on the Mac, then connect again" in ended.reason, ended.reason)
        assertTrue(transport.closed)
        assertTrue(transport.healthy.isEmpty())
    }

    /** The HELLO sent on a fresh Wi‑Fi connection to a Mac presenting [presented]. */
    private fun wifiHello(presented: Fingerprint?): Hello {
        val wifi = Session(
            transport, ::hello, video, stats, { nowNanos }, listener,
            pairing = PairingContext(tabletFingerprint, isPinned = { mac -> pinned.any { it.first == mac } }, onPaired = { _, _ -> }),
        )
        transport.current = 7
        wifi.onConnectionState(ConnectionState.Connected(7, presented))
        return transport.sentOf<Hello>().last()
    }

    @Test
    fun wifiHelloRequestsPairingExactlyWhenTheMacIsNotPinned() {
        assertEquals(true, wifiHello(macFingerprint).pairingRequested, "no pin (never paired, forgotten, or Pair again)")
        pinned += Fingerprint.fromBytes(ByteArray(32) { 0x55 }) to "Old identity"
        assertEquals(true, wifiHello(macFingerprint).pairingRequested, "the pin doesn't match this certificate")
        pinned += macFingerprint to "Mac"
        assertNull(wifiHello(macFingerprint).pairingRequested, "pinned: plain HELLO")
    }

    @Test
    fun usbHelloNeverRequestsPairing() {
        connect(1)
        assertNull(transport.sentOf<Hello>().single().pairingRequested)
    }

    @Test
    fun aPinnedMacGoesStraightToWelcome() {
        pinned += macFingerprint to "Mac"
        val wifi = wifiSession()
        wifi.receive(welcome)
        assertIs<SessionState.Streaming>(wifi.state)
    }

    @Test
    fun pairingIsIgnoredOverUsb() {
        connect(1)
        receive(Pairing(PairingState.REQUIRED, "Mac"))
        assertEquals(SessionState.Handshaking(1), session.state)
    }

    // No Surface: pause, or goodbye + suspend

    @Test
    fun theStreamPausesWhenTheSurfaceGoesAwayAndResumesWhenItIsBack() {
        streaming(welcomeMessage = pausingWelcome)
        session.onVideoSurfaceChanged(false)
        advanceMillis(999)
        assertTrue(transport.sentOf<Configure>().isEmpty(), "brief surface changes don't pause")
        advanceMillis(1)
        assertEquals(true, transport.sentOf<Configure>().single().request?.paused)
        assertTrue(assertIs<SessionState.Streaming>(session.state).paused)
        assertFalse(session.sendInputs(listOf(InputMessage(0, 1, InputKind.TOUCH, InputAction.DOWN, emptyList()))))

        // Paused: PING stays at 1 Hz, reports drop to one per 5 s.
        transport.clear()
        repeat(10) {
            advanceMillis(1_000)
            macAnswers()
        }
        assertEquals(10, transport.sentOf<Ping>().size)
        assertEquals(2, transport.sentOf<ReceiverReport>().size)

        transport.clear()
        session.onVideoSurfaceChanged(true)
        assertEquals(false, transport.sentOf<Configure>().single().request?.paused)
        assertFalse(assertIs<SessionState.Streaming>(session.state).paused)
        advanceMillis(1_000)
        assertEquals(1, transport.sentOf<ReceiverReport>().size, "back to 1 Hz")
    }

    @Test
    fun withoutPauseSupportTheSessionSaysGoodbyeAndReconnectsLater() {
        streaming() // WELCOME without "pause"
        session.onVideoSurfaceChanged(false)
        advanceMillis(9_000)
        assertTrue(transport.sentOf<Goodbye>().isEmpty())
        assertEquals(TimeUnit.SECONDS.toNanos(1), session.nanosUntilNextTick())
        advanceMillis(1_000)
        assertEquals(GoodbyeReason.USER, transport.sentOf<Goodbye>().single().reason)
        assertTrue(transport.suspended)
        assertEquals(SessionState.Suspended, session.state)
        assertEquals(1, video.stops)
        assertNull(session.nanosUntilNextTick(), "nothing runs while suspended")

        session.onConnectionState(ConnectionState.Suspended)
        assertEquals(SessionState.Suspended, session.state)
        session.onVideoSurfaceChanged(true)
        assertEquals(1, transport.resumes)
        assertEquals(SessionState.Idle, session.state)
        connect(2)
        assertEquals("b3f1", transport.sentOf<Hello>().last().resume?.session)
    }

    @Test
    fun aMissingSurfaceIsMeasuredFromWelcome() {
        // Connected from the connection screen: the stream screen opens right after WELCOME.
        connect(1)
        nowNanos += TimeUnit.SECONDS.toNanos(30) // a long handshake wait, still no surface
        receive(pausingWelcome)
        advanceMillis(500)
        assertTrue(transport.sentOf<Configure>().isEmpty())
        session.onVideoSurfaceChanged(true)
        advanceMillis(1_000)
        assertTrue(transport.sentOf<Configure>().isEmpty(), "never paused: the surface came in time")
    }

    @Test
    fun unknownMessagesAreSkipped() {
        streaming()
        receive(UnknownMessage(0x7E, FrameFlags.IGNORABLE, StreamId.TELEMETRY, ByteArray(3)))
        assertIs<SessionState.Streaming>(session.state)
        assertTrue(transport.sent.none { it.second.type == MessageType.ERROR })
        assertEquals(200L, stats.bytes, "every received frame counts towards bytesReceived")
    }

    @Test
    fun unknownRequiredMessagesAreAnsweredWithUnsupportedAndTheConnectionStays() {
        streaming()
        receive(UnknownMessage(0x7D, FrameFlags.NONE, StreamId.CONTROL, "{}".encodeToByteArray()))
        val error = transport.sentOf<ErrorMessage>().single()
        assertEquals(ErrorCode.UNSUPPORTED, error.code)
        assertTrue("0x7d" in error.message, error.message)
        assertIs<SessionState.Streaming>(session.state)
        assertTrue(transport.dropped.isEmpty())
        assertFalse(transport.closed)
    }
}
