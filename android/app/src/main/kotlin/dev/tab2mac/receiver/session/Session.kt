package dev.tab2mac.receiver.session

import dev.tab2mac.protocol.ClockSyncEstimator
import dev.tab2mac.protocol.Configure
import dev.tab2mac.protocol.DirectLink
import dev.tab2mac.protocol.CursorPosition
import dev.tab2mac.protocol.CursorShape
import dev.tab2mac.protocol.DisplayDescription
import dev.tab2mac.protocol.ErrorCode
import dev.tab2mac.protocol.ErrorMessage
import dev.tab2mac.protocol.Feature
import dev.tab2mac.protocol.Fingerprint
import dev.tab2mac.protocol.Goodbye
import dev.tab2mac.protocol.GoodbyeReason
import dev.tab2mac.protocol.Hello
import dev.tab2mac.protocol.InputMessage
import dev.tab2mac.protocol.KeyAction
import dev.tab2mac.protocol.KeyMessage
import dev.tab2mac.protocol.KeyframeReason
import dev.tab2mac.protocol.KeyframeRequest
import dev.tab2mac.protocol.Message
import dev.tab2mac.protocol.Orientation
import dev.tab2mac.protocol.Pairing as PairingMessage
import dev.tab2mac.protocol.PairingCode
import dev.tab2mac.protocol.PairingState
import dev.tab2mac.protocol.Ping
import dev.tab2mac.protocol.Pong
import dev.tab2mac.protocol.StreamFormat
import dev.tab2mac.protocol.UnknownMessage
import dev.tab2mac.protocol.VersionNegotiation
import dev.tab2mac.protocol.VideoFrame
import dev.tab2mac.protocol.Welcome
import dev.tab2mac.transport.ConnectionState
import dev.tab2mac.transport.Incoming
import dev.tab2mac.transport.Transport
import java.util.concurrent.TimeUnit
import kotlin.math.abs

/**
 * The receiver side of one user-initiated connection (PROTOCOL.md §3.1, §5): per transport
 * connection it sends HELLO, waits for WELCOME, feeds STREAM_FORMAT and VIDEO_FRAME to the
 * [VideoSink], answers PINGs, keeps clock sync with a PING every second, sends a RECEIVER_REPORT
 * every [SessionConfig.reportIntervalNanos] (1 s over USB), and asks for keyframes on the
 * decoder's behalf.
 *
 * Power: when no video Surface exists (app in the background, screen off) the stream is paused
 * with CONFIGURE `request.paused` if the Mac supports `pause`; otherwise the session says
 * GOODBYE after [SessionConfig.goodbyeWithoutSurfaceNanos] and reconnects when a Surface is back.
 *
 * Wi‑Fi pairing (§6, with a [PairingContext]), strictly in order: `required` → the tablet
 * commits to a fresh nonce (`commit`) → the Mac's `nonce` → the tablet reveals its own
 * (`reveal`) and shows the code ([SessionState.Pairing]) → [confirmPairing] (`confirmed`) → the
 * Mac's `paired` pins the Mac and the handshake resumes. Anything missing, repeated, out of order
 * or malformed ends the attempt with `rejected` and GOODBYE `error`; [rejectPairing] declines
 * with GOODBYE `user`. The handshake timeout is replaced by the 2-minute pairing timeout. A Mac
 * that answers with WELCOME without being pinned isn't trusted on first use.
 *
 * Liveness: the Mac answers every PING (1 Hz while streaming); the transport's watchdog, on a
 * thread that never does I/O, tears the link down when nothing arrives for a few seconds or a
 * write stays blocked ([dev.tab2mac.transport.LinkOptions.silenceTimeoutMs]).
 *
 * Confinement: everything runs on one thread (the session thread) except [sendInputs] and
 * [clockOffsetUs], which are safe from any thread. Time only advances through [onTick]; the
 * driver sleeps until [nanosUntilNextTick] (no fixed-rate polling), so tests drive the session
 * with a fake clock and a fake [Transport].
 */
class Session(
    private val transport: Transport,
    private val hello: (resumeSession: String?) -> Hello,
    private val video: VideoSink,
    private val stats: SessionStats,
    private val clock: MonotonicClock,
    private val listener: SessionListener,
    private val log: SessionLog = SessionLog { _, _ -> },
    private val config: SessionConfig = SessionConfig(),
    private val pairing: PairingContext? = null,
    private val cursor: CursorSink = CursorSink.NONE,
) {
    /** Current state. */
    var state: SessionState = SessionState.Idle
        private set

    /** θ = Mac clock − Android clock (µs) of the best recent PING/PONG, or null before the first. */
    @Volatile
    var clockOffsetUs: Long? = null
        private set

    /** Orientation to request from the Mac (after WELCOME and on rotation). */
    var desiredOrientation: Orientation? = null

    /** Refresh rate to ask the Mac for after WELCOME; null lets the Mac decide (the default). */
    var preferredRefreshRate: Double? = null

    private val clockSync = ClockSyncEstimator()

    @Volatile
    private var inputConnectionId = NO_CONNECTION

    @Volatile
    private var keyConnectionId = NO_CONNECTION
    private val keySequence = java.util.concurrent.atomic.AtomicLong()

    // Per connection.
    private var connectionId = NO_CONNECTION
    /** The Mac's certificate fingerprint on a TLS connection. */
    private var macFingerprint: Fingerprint? = null
    /** This attempt's nonce, once committed to (§6). */
    private var tabletNonce: ByteArray? = null
    private var pairingDeadline: Long? = null
    /** When to give up waiting for WELCOME; null = wait as long as the link lasts. */
    private var handshakeDeadline: Long? = null
    private var handshakeTimedOut = false
    private val outstandingPings = LinkedHashSet<Long>()
    private var nextPingAt = 0L
    private var nextReportAt = 0L
    private var pauseSupported = false
    /** WELCOME listed `keyboard` (§3.3c). */
    private var keyboardSupported = false
    private var requestedOrientation: Orientation? = null
    private var expectedFrameId = NO_FRAME

    // Across connections.
    private var nextPingId = 1L
    private var lastKeyframeRequestAt: Long? = null
    private var resumeToken: String? = null
    private var surfaceAvailable = false
    private var surfaceMissingSince = clock.nanoTime()

    /** Follows the transport: a new connection id starts a handshake; losing it stops the stream. */
    fun onConnectionState(connection: ConnectionState) {
        if (state is SessionState.Ended) return
        when (connection) {
            is ConnectionState.Connected -> if (connection.connectionId != connectionId) startHandshake(connection.connectionId, connection.peer)
            is ConnectionState.Closed -> end("disconnected: ${connection.reason ?: "closed"}")
            ConnectionState.Suspended -> if (state !is SessionState.Suspended) {
                stopStream()
                setState(SessionState.Suspended)
            }
            else -> if (state is SessionState.Handshaking || state is SessionState.Streaming || state is SessionState.Pairing) {
                stopStream()
                setState(SessionState.Idle)
            }
        }
    }

    /**
     * Handles one received message. Messages from an earlier connection are ignored. The session
     * releases [incoming] unless it hands a video frame to the [VideoSink], which then does.
     */
    fun onIncoming(incoming: Incoming) {
        var handedOff = false
        try {
            if (state is SessionState.Ended || incoming.connectionId != connectionId) return
            stats.onMessageReceived(incoming.wireSize)
            when (val message = incoming.message) {
                is Welcome -> onWelcome(message)
                is StreamFormat -> onStreamFormat(message)
                is VideoFrame -> handedOff = onVideoFrame(message, incoming)
                // §3.3b: the pointer as a side channel, when WELCOME listed `cursor`.
                is CursorPosition -> if (state is SessionState.Streaming) cursor.onCursor(message)
                is CursorShape -> if (state is SessionState.Streaming) cursor.onCursorShape(message)
                is Configure -> onConfigure(message)
                // t3 is stamped by the transport as the PONG is written (§3.4).
                is Ping -> send(Pong(message.id, message.t1, incoming.receivedAtNanos / 1_000, clock.nanoTime() / 1_000))
                is Pong -> onPong(message, incoming.receivedAtNanos)
                is ErrorMessage -> onRemoteError(message)
                is Goodbye -> onGoodbye(message)
                is PairingMessage -> onPairing(message)
                // §6b: sent after WELCOME, only over an authenticated session. Never logged.
                is DirectLink -> if (state is SessionState.Streaming) listener.onDirectLink(message) else log("direct-link.unexpected")
                is UnknownMessage -> onUnknown(message)
                else -> log("message.unexpected", "type" to message.type)
            }
        } finally {
            if (!handedOff) incoming.release()
        }
    }

    /** The video Surface appeared or went away (UI thread events, delivered on the session thread). */
    fun onVideoSurfaceChanged(available: Boolean) {
        if (available == surfaceAvailable) return
        surfaceAvailable = available
        log("surface.changed", "available" to available)
        if (!available) {
            surfaceMissingSince = clock.nanoTime()
            return
        }
        val current = state
        if (current is SessionState.Streaming && current.paused) setPaused(current, paused = false)
        if (current is SessionState.Suspended) {
            setState(SessionState.Idle)
            transport.resume()
        }
    }

    /**
     * How long until [onTick] has work — the next PING/RECEIVER_REPORT, the pause or goodbye
     * deadline while streaming without a Surface, the handshake or pairing deadline —
     * or null when nothing is scheduled.
     */
    fun nanosUntilNextTick(): Long? {
        val now = clock.nanoTime()
        return when (val current = state) {
            is SessionState.Handshaking -> if (handshakeTimedOut) null else handshakeDeadline?.let { (it - now).coerceAtLeast(0) }
            is SessionState.Pairing -> pairingDeadline?.let { (it - now).coerceAtLeast(0) }
            is SessionState.Streaming -> {
                var wait = minOf(nextPingAt - now, nextReportAt - now)
                surfaceDeadline(current)?.let { wait = minOf(wait, it - now) }
                wait.coerceAtLeast(0)
            }
            else -> null
        }
    }

    /** Periodic work. Call when [nanosUntilNextTick] elapses (or earlier: extra calls are harmless). */
    fun onTick() {
        val now = clock.nanoTime()
        when (val current = state) {
            is SessionState.Handshaking -> if (!handshakeTimedOut && handshakeDeadline?.let { now - it >= 0 } == true) {
                handshakeTimedOut = true
                log("handshake.timeout", "connection" to current.connectionId)
                transport.dropConnection(current.connectionId, "no WELCOME within 5 s")
            }
            is SessionState.Pairing -> if (pairingDeadline?.let { now - it >= 0 } == true) failPairing("pairing timed out")
            is SessionState.Streaming -> {
                val deadline = surfaceDeadline(current)
                if (deadline != null && now - deadline >= 0) {
                    if (pauseSupported) {
                        setPaused(current, paused = true)
                    } else {
                        suspendForSurface()
                        return
                    }
                }
                if (now - nextPingAt >= 0) {
                    sendPing(now)
                    nextPingAt = now + config.pingIntervalNanos
                }
                if (now - nextReportAt >= 0) {
                    send(stats.intervalReport(clockSync.best?.offsetUs, clockSync.latest?.roundTripUs))
                    nextReportAt = now + reportInterval()
                }
            }
            else -> Unit
        }
    }

    /** Asks the Mac for a keyframe (rate-limited). */
    fun requestKeyframe(reason: KeyframeReason) {
        val streaming = state as? SessionState.Streaming ?: return
        if (streaming.paused) return
        val now = clock.nanoTime()
        val last = lastKeyframeRequestAt
        if (last != null && now - last < config.keyframeRequestIntervalNanos) return
        lastKeyframeRequestAt = now
        send(KeyframeRequest(reason, stats.lastDecodedFrameId))
        log("keyframe.requested", "reason" to reason)
    }

    /**
     * The tablet rotated: ask the Mac to follow (CONFIGURE request). Compared with the last
     * orientation requested on this connection (the Mac ignores no-ops), so rotating back is
     * always sent.
     */
    fun requestOrientation(orientation: Orientation) {
        desiredOrientation = orientation
        if (state !is SessionState.Streaming || orientation == requestedOrientation) return
        requestedOrientation = orientation
        send(Configure(request = Configure.Request(orientation = orientation)))
        log("configure.requested", "orientation" to orientation)
    }

    /**
     * Sends one key of a hardware keyboard (KEY, §3.3c) while streaming to a Mac that listed
     * `keyboard`; false otherwise, so the key stays with Android. Thread-safe.
     */
    fun sendKey(down: Boolean, usage: Int, modifiers: Int, eventTimeUs: Long): Boolean {
        val id = keyConnectionId
        if (id == NO_CONNECTION) return false
        val sequence = keySequence.getAndIncrement() and U32_MAX
        return transport.send(KeyMessage(sequence, eventTimeUs, if (down) KeyAction.DOWN else KeyAction.UP, usage, modifiers), id)
    }

    /** Sends one `MotionEvent`'s INPUT messages in one write while streaming. Thread-safe. */
    fun sendInputs(messages: List<InputMessage>): Boolean {
        val id = inputConnectionId
        return id != NO_CONNECTION && messages.isNotEmpty() && transport.sendBatch(messages, id)
    }

    /**
     * The user checked that the Mac shows the same code: PAIRING `confirmed`. Only once the code is
     * on screen, which is after the reveal (the Mac rejects an earlier `confirmed`).
     */
    fun confirmPairing() {
        val current = state as? SessionState.Pairing ?: return
        if (current.code == null || current.confirmed) return
        send(PairingMessage(PairingState.CONFIRMED))
        setState(current.copy(confirmed = true))
        log("pairing.confirmed")
    }

    /** The user declined (the codes differ, or they changed their mind): `rejected`, GOODBYE `user`, close. */
    fun rejectPairing() {
        if (state !is SessionState.Pairing) return
        send(PairingMessage(PairingState.REJECTED))
        send(Goodbye(GoodbyeReason.USER))
        log("pairing.declined-here")
        end("pairing cancelled")
        transport.close()
    }

    /** Says GOODBYE and closes the transport for good (declining first while pairing). */
    fun close(reason: GoodbyeReason = GoodbyeReason.USER) {
        if (state is SessionState.Pairing) send(PairingMessage(PairingState.REJECTED))
        if (state is SessionState.Handshaking || state is SessionState.Streaming || state is SessionState.Pairing) send(Goodbye(reason))
        end("closed: $reason")
        transport.close()
    }

    private fun startHandshake(id: Long, peer: Fingerprint?) {
        stopStream()
        connectionId = id
        macFingerprint = peer
        tabletNonce = null
        pairingDeadline = null
        clockSync.reset()
        clockOffsetUs = null
        outstandingPings.clear()
        pauseSupported = false
        keyboardSupported = false
        requestedOrientation = null
        expectedFrameId = NO_FRAME
        handshakeTimedOut = false
        handshakeDeadline = config.handshakeTimeoutNanos?.let { clock.nanoTime() + it }
        setState(SessionState.Handshaking(id))
        val sent = send(helloFor(peer))
        log("hello.sent", "connection" to id, "resume" to resumeToken, "queued" to sent)
    }

    /**
     * HELLO for this connection. Over Wi‑Fi, `pairingRequested` when the tablet has no pin
     * matching the certificate the Mac just presented — never pinned, forgotten, or "Pair again"
     * after an identity change — so a Mac that still pins the tablet pairs anyway (§6).
     */
    private fun helloFor(mac: Fingerprint?): Hello {
        val base = hello(resumeToken)
        val context = pairing ?: return base
        val pinned = mac != null && context.isPinned(mac)
        return base.copy(pairingRequested = if (pinned) null else true)
    }

    private fun onWelcome(welcome: Welcome) {
        if (state !is SessionState.Handshaking) {
            log("welcome.unexpected", "state" to state)
            return
        }
        if (welcome.version !in VersionNegotiation.SUPPORTED) {
            log("welcome.incompatible-version", "version" to welcome.version)
            send(ErrorMessage(ErrorCode.INCOMPATIBLE_VERSION, "receiver supports ${VersionNegotiation.SUPPORTED}, Mac chose ${welcome.version}"))
            send(Goodbye(GoodbyeReason.ERROR))
            end("incompatible protocol version ${welcome.version}")
            transport.close()
            return
        }
        val context = pairing
        val mac = macFingerprint
        if (context != null && (mac == null || !context.isPinned(mac))) {
            // §6: the Mac still knows this tablet, but the tablet doesn't know the Mac.
            log("welcome.unpinned-mac", "fingerprint" to mac?.hex)
            send(Goodbye(GoodbyeReason.ERROR))
            end(UNPINNED_MAC)
            transport.close()
            return
        }
        // Only a completed handshake resets the transport's reconnection backoff.
        transport.markHealthy(connectionId)
        resumeToken = welcome.session
        pauseSupported = welcome.features?.contains(Feature.PAUSE) == true
        keyboardSupported = welcome.features?.contains(Feature.KEYBOARD) == true
        requestedOrientation = welcome.display.orientation
        val now = clock.nanoTime()
        // A missing Surface is measured from WELCOME, so the stream screen has time to open.
        if (!surfaceAvailable && now - surfaceMissingSince > 0) surfaceMissingSince = now
        setState(SessionState.Streaming(connectionId, welcome, welcome.display, welcome.stream, format = null))
        log(
            "welcome.received", "session" to welcome.session, "mac" to welcome.mac.name, "codec" to welcome.stream.codec,
            "width" to welcome.stream.width, "height" to welcome.stream.height, "fps" to welcome.stream.fps,
            "pause" to pauseSupported,
        )
        sendPing(now)
        nextPingAt = now + config.pingIntervalNanos
        nextReportAt = now + reportInterval()
        requestInitialConfiguration(welcome.display)
    }

    private fun requestInitialConfiguration(display: DisplayDescription) {
        val orientation = desiredOrientation?.takeIf { it != display.orientation }
        val refreshRate = preferredRefreshRate?.takeIf { abs(it - display.refreshRate) >= 1.0 }
        if (orientation == null && refreshRate == null) return
        if (orientation != null) requestedOrientation = orientation
        send(Configure(request = Configure.Request(orientation = orientation, refreshRate = refreshRate)))
        log("configure.requested", "orientation" to orientation, "refreshRate" to refreshRate)
    }

    private fun onStreamFormat(format: StreamFormat) {
        val streaming = state as? SessionState.Streaming ?: return log("stream-format.unexpected", "state" to state)
        if (format.width !in 1..MAX_DIMENSION || format.height !in 1..MAX_DIMENSION) {
            log("stream-format.invalid", "width" to format.width, "height" to format.height)
            send(ErrorMessage(ErrorCode.BAD_FRAME, "invalid STREAM_FORMAT size ${format.width}x${format.height}"))
            return
        }
        expectedFrameId = NO_FRAME
        setState(streaming.copy(format = format))
        log("stream-format.received", "codec" to format.codec, "width" to format.width, "height" to format.height, "parameterSets" to format.parameterSets.size)
        video.onStreamFormat(format, streaming.stream)
    }

    /** Returns whether the frame (and the duty to release it) went to the video sink. */
    private fun onVideoFrame(frame: VideoFrame, incoming: Incoming): Boolean {
        if (state !is SessionState.Streaming) return false
        stats.onVideoFrameReceived(frame.frameId)
        // The Mac never drops an encoded frame, so a gap in frameIds is real loss (for example
        // a VIDEO_FRAME the transport couldn't decode): the next delta frames can't be decoded.
        val expected = expectedFrameId
        expectedFrameId = (frame.frameId + 1) and U32_MAX
        if (expected != NO_FRAME && frame.frameId != expected && !frame.isKeyframe) {
            log("video.gap", "expected" to expected, "got" to frame.frameId)
            requestKeyframe(KeyframeReason.LOSS)
        }
        video.onVideoFrame(frame, incoming.receivedAtNanos, incoming)
        return true
    }

    private fun onConfigure(configure: Configure) {
        val streaming = state as? SessionState.Streaming ?: return
        if (configure.display == null && configure.stream == null) {
            log("configure.ignored", "request" to configure.request)
            return
        }
        setState(streaming.copy(display = configure.display ?: streaming.display, stream = configure.stream ?: streaming.stream))
        log("configure.announced", "orientation" to configure.display?.orientation, "width" to configure.stream?.width, "height" to configure.stream?.height)
    }

    private fun onPong(pong: Pong, receivedAtNanos: Long) {
        // Matched by id: t1 was stamped by the transport when the PING was written.
        if (!outstandingPings.remove(pong.id)) return log("pong.unmatched", "id" to pong.id)
        val sample = clockSync.add(pong.t1, pong.t2, pong.t3, receivedAtNanos / 1_000)
        val best = clockSync.best ?: return log("clock.sample-rejected", "rttUs" to sample.roundTripUs)
        clockOffsetUs = best.offsetUs
        listener.onClockSync(best.offsetUs, sample.roundTripUs)
    }

    private fun onRemoteError(error: ErrorMessage) {
        log("error.received", "code" to error.code, "message" to error.message)
        listener.onRemoteError(error)
        val refusedBeforeWelcome = state is SessionState.Handshaking &&
            (error.code == ErrorCode.UNSUPPORTED || error.code == ErrorCode.INTERNAL)
        if (refusedBeforeWelcome || error.code == ErrorCode.INCOMPATIBLE_VERSION) {
            // The Mac can't serve this tablet: retrying would only repeat the refusal.
            end("Mac refused the connection: ${error.code}: ${error.message}")
            transport.close()
        }
    }

    private fun onGoodbye(goodbye: Goodbye) {
        log("goodbye.received", "reason" to goodbye.reason)
        when (goodbye.reason) {
            // The user on the Mac disconnected, or another tablet took over: don't come back.
            GoodbyeReason.USER, GoodbyeReason.REPLACED -> {
                end(endedByMac(goodbye.reason))
                transport.close()
            }
            // Shutdown or error: close this connection ourselves; the transport retries with backoff.
            else -> {
                stopStream()
                setState(SessionState.Idle)
                transport.dropConnection(connectionId, "goodbye ${goodbye.reason}")
            }
        }
    }

    /** When the missing Surface should pause (or, without `pause`, end) the stream; null if not due. */
    private fun surfaceDeadline(streaming: SessionState.Streaming): Long? = when {
        surfaceAvailable -> null
        pauseSupported -> if (streaming.paused) null else surfaceMissingSince + config.pauseAfterNanos
        else -> surfaceMissingSince + config.goodbyeWithoutSurfaceNanos
    }

    private fun setPaused(streaming: SessionState.Streaming, paused: Boolean) {
        send(Configure(request = Configure.Request(paused = paused)))
        setState(streaming.copy(paused = paused))
        nextReportAt = clock.nanoTime() + reportInterval()
        log(if (paused) "stream.paused" else "stream.resumed")
    }

    /** §6. Only over TLS ([pairing] and the Mac's fingerprint known); ignored elsewhere. */
    private fun onPairing(message: PairingMessage) {
        val context = pairing
        val mac = macFingerprint
        if (context == null || mac == null) return log("pairing.ignored", "state" to message.state)
        val current = state
        when (message.state) {
            PairingState.REQUIRED -> {
                if (current !is SessionState.Handshaking) return failPairing("unexpected required")
                val nonce = context.newNonce()
                tabletNonce = nonce
                // Commit before seeing the Mac's nonce. No code yet.
                send(PairingMessage(PairingState.COMMIT, commitment = PairingCode.hex(PairingCode.commitment(context.tabletFingerprint, mac, nonce))))
                handshakeDeadline = null
                pairingDeadline = clock.nanoTime() + config.pairingTimeoutNanos
                setState(SessionState.Pairing(connectionId, message.name ?: "your Mac"))
                log("pairing.committed", "mac" to message.name)
            }
            PairingState.NONCE -> {
                val nonce = tabletNonce
                if (current !is SessionState.Pairing || current.code != null || nonce == null) return failPairing("unexpected nonce")
                val macNonce = PairingCode.parseHex(message.nonce) ?: return failPairing("malformed nonce")
                send(PairingMessage(PairingState.REVEAL, nonce = PairingCode.hex(nonce)))
                val code = PairingCode.code(mac, context.tabletFingerprint, macNonce, nonce)
                setState(current.copy(code = code))
                log("pairing.revealed")
            }
            PairingState.PAIRED -> {
                if (current !is SessionState.Pairing || !current.confirmed) return failPairing("unexpected paired")
                val name = message.name ?: current.macName
                context.onPaired(mac, name)
                log("pairing.paired", "mac" to name, "fingerprint" to mac.hex)
                tabletNonce = null
                pairingDeadline = null
                // WELCOME follows.
                handshakeDeadline = config.handshakeTimeoutNanos?.let { clock.nanoTime() + it }
                setState(SessionState.Handshaking(connectionId))
            }
            PairingState.REJECTED -> {
                if (current !is SessionState.Pairing && current !is SessionState.Handshaking) return
                log("pairing.rejected-by-mac")
                end("the Mac declined pairing")
                transport.close()
            }
            // Tablet → Mac steps coming back, and states this receiver doesn't know: ignored.
            else -> log("pairing.skipped", "state" to message.state)
        }
    }

    /** The exchange broke the rules (§6): `rejected`, GOODBYE `error`, close. */
    private fun failPairing(reason: String) {
        log("pairing.failed", "reason" to reason)
        send(PairingMessage(PairingState.REJECTED))
        send(Goodbye(GoodbyeReason.ERROR))
        end("pairing failed: $reason")
        transport.close()
    }

    /** §1: skip an unknown IGNORABLE type silently; answer any other with ERROR `unsupported`. */
    private fun onUnknown(message: UnknownMessage) {
        if (message.flags.isIgnorable) {
            log("message.skipped", "type" to message.type, "bytes" to message.payload.size)
            return
        }
        log("message.unsupported", "type" to message.type)
        send(ErrorMessage(ErrorCode.UNSUPPORTED, "unsupported message type 0x%02x".format(message.rawType)))
    }

    /** Without `pause`: say GOODBYE, disconnect and wait for a Surface ([onVideoSurfaceChanged]). */
    private fun suspendForSurface() {
        log("stream.suspended", "reason" to "no video surface")
        send(Goodbye(GoodbyeReason.USER))
        stopStream()
        setState(SessionState.Suspended)
        transport.suspend()
    }

    private fun reportInterval(): Long =
        if ((state as? SessionState.Streaming)?.paused == true) config.pausedReportIntervalNanos else config.reportIntervalNanos

    private fun sendPing(now: Long) {
        val id = nextPingId
        nextPingId = (nextPingId % U32_MAX) + 1
        outstandingPings += id
        while (outstandingPings.size > config.maxOutstandingPings) outstandingPings.remove(outstandingPings.first())
        send(Ping(id, now / 1_000))
    }

    private fun send(message: Message): Boolean = transport.send(message, connectionId)

    private fun stopStream() {
        if (state !is SessionState.Streaming) return
        video.onStreamStopped()
        cursor.onCursorReset()
    }

    private fun end(reason: String) {
        if (state is SessionState.Ended) return
        stopStream()
        setState(SessionState.Ended(reason))
    }

    private fun setState(newState: SessionState) {
        if (newState == state) return
        state = newState
        inputConnectionId = (newState as? SessionState.Streaming)?.takeIf { !it.paused }?.connectionId ?: NO_CONNECTION
        keyConnectionId = if (keyboardSupported) inputConnectionId else NO_CONNECTION
        log("session.state", "state" to newState.javaClass.simpleName)
        listener.onStateChanged(newState)
    }

    private fun log(event: String, vararg fields: Pair<String, Any?>) {
        log.event(event, fields.toList())
    }

    private companion object {
        const val NO_CONNECTION = -1L
        const val NO_FRAME = -1L
        const val U32_MAX = 0xFFFF_FFFFL

        /** Largest plausible stream side; anything else in STREAM_FORMAT is a bad frame. */
        const val MAX_DIMENSION = 16_384


        /** Why a Wi‑Fi session ends when a Mac that isn't pinned skips pairing. */
        const val UNPINNED_MAC =
            "this Mac didn't pair, and this tablet has no pairing for it (the Mac may be too old to pair again on request). " +
                "Forget this tablet on the Mac, then connect again"
    }
}
