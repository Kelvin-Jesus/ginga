package dev.ginga.receiver.ui

import dev.ginga.protocol.Codec
import dev.ginga.protocol.DisplayDescription
import dev.ginga.protocol.ErrorCode
import dev.ginga.protocol.ErrorMessage
import dev.ginga.protocol.Orientation
import dev.ginga.protocol.PixelDimensions
import dev.ginga.protocol.StreamDescription
import dev.ginga.protocol.TransportKind
import dev.ginga.protocol.Welcome
import dev.ginga.receiver.ReceiverState
import dev.ginga.receiver.session.SessionState
import dev.ginga.receiver.video.VideoPipeline
import dev.ginga.transport.ConnectionState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class StatusTextTest {
    private val display = DisplayDescription(17, "Galaxy Tab S11", PixelDimensions(1280, 800), true, 60.0, Orientation.LANDSCAPE)
    private val stream = StreamDescription(Codec.HEVC, 2560, 1600, 60.0, 40_000)
    private val welcome = Welcome(1, "s", Welcome.Mac("MacBook Air", "26.6.2", "0.3.0"), display, stream)

    @Test
    fun describesEachPhase() {
        assertEquals("Not connected", StatusText.of(ReceiverState()).headline)
        assertEquals("Last session: Mac: replaced", StatusText.of(ReceiverState(endReason = "Mac: replaced")).detail)

        val waiting = StatusText.of(ReceiverState(active = true, connection = ConnectionState.WaitingToRetry(3, 1_000, "Connection refused")))
        assertEquals("Waiting for the Mac…", waiting.headline)
        assertTrue(waiting.detail.startsWith("Retrying in 1.00 s · Connection refused"), waiting.detail)

        val streaming = StatusText.of(
            ReceiverState(active = true, connection = ConnectionState.Connected(4), session = SessionState.Streaming(4, welcome, display, stream, null)),
        )
        assertEquals("Streaming from MacBook Air", streaming.headline)
        assertEquals("2560×1600 hevc @ 60 fps · Galaxy Tab S11 (landscape)", streaming.detail)

        assertEquals("reconnecting", StatusText.short(ReceiverState(active = true, connection = ConnectionState.WaitingToRetry(1, 250, null))))
    }

    @Test
    fun showsTheMacsLastError() {
        val state = ReceiverState(endReason = "Mac refused the connection", lastRemoteError = ErrorMessage(ErrorCode.INTERNAL, "cannot create display"))
        assertTrue(StatusText.of(state).detail.endsWith("Mac reported internal: cannot create display"), StatusText.of(state).detail)
    }

    @Test
    fun describesPausedAndSuspendedStreams() {
        val paused = ReceiverState(active = true, session = SessionState.Streaming(4, welcome, display, stream, null, paused = true))
        assertEquals("Paused: MacBook Air", StatusText.of(paused).headline)
        assertEquals("paused", StatusText.short(paused))
        val suspended = ReceiverState(active = true, connection = ConnectionState.Suspended, session = SessionState.Suspended)
        assertEquals("Paused", StatusText.of(suspended).headline)
        assertEquals("suspended", StatusText.short(suspended))
    }

    @Test
    fun describesDirectUsbSessions() {
        val connecting = StatusText.of(ReceiverState(active = true, transport = TransportKind.AOA, connection = ConnectionState.Connecting(1)))
        assertEquals("Direct USB (attempt 1)", connecting.detail)

        val handshaking = StatusText.of(ReceiverState(active = true, transport = TransportKind.AOA, session = SessionState.Handshaking(1)))
        assertEquals("HELLO sent over USB. The Mac answers as soon as Ginga runs there.", handshaking.detail)

        val streaming = StatusText.of(
            ReceiverState(
                active = true, transport = TransportKind.AOA, connection = ConnectionState.Connected(2),
                session = SessionState.Streaming(2, welcome, display, stream, null),
            ),
        )
        assertEquals("2560×1600 hevc @ 60 fps · Galaxy Tab S11 (landscape) · direct USB", streaming.detail)

        // Unplugged: nothing to suggest. Still plugged in (after Disconnect): Connect reopens it.
        val unplugged = StatusText.of(ReceiverState(transport = TransportKind.AOA, endReason = "disconnected: accessory detached"))
        assertEquals("Not connected", unplugged.headline)
        assertEquals("Last session: disconnected: accessory detached", unplugged.detail)
        val pluggedIn = StatusText.of(ReceiverState(transport = TransportKind.AOA, accessoryAttached = true, endReason = "closed: user"))
        assertEquals("Last session: closed: user\nYour Mac is connected by USB. Tap Connect to use this tablet as its display.", pluggedIn.detail)
        assertEquals(
            "Your Mac is connected by USB. Tap Connect to use this tablet as its display.",
            StatusText.of(ReceiverState(accessoryAttached = true)).detail,
        )

        val retrying = StatusText.of(ReceiverState(active = true, transport = TransportKind.AOA, connection = ConnectionState.WaitingToRetry(1, 250, "busy")))
        assertFalse("adb" in retrying.detail, retrying.detail)
        val adb = StatusText.of(ReceiverState(active = true, transport = TransportKind.ADB_TCP, connection = ConnectionState.WaitingToRetry(1, 250, null)))
        assertTrue("adb reverse tcp:47800" in adb.detail, adb.detail)
    }

    @Test
    fun describesWifiAndPairing() {
        val wifi = ReceiverState(active = true, transport = TransportKind.WIFI_TLS, wifiMacName = "Kelvin's MacBook Air")
        assertEquals("Wi‑Fi: Kelvin's MacBook Air (attempt 2)", StatusText.of(wifi.copy(connection = ConnectionState.Connecting(2))).detail)
        assertTrue("same network" in StatusText.of(wifi.copy(connection = ConnectionState.WaitingToRetry(1, 250, "refused"))).detail)

        val exchanging = StatusText.of(wifi.copy(session = SessionState.Pairing(1, "Kelvin's MacBook Air")))
        assertEquals(StatusText("Pairing with Kelvin's MacBook Air…", "Exchanging codes"), exchanging)
        val asking = StatusText.of(wifi.copy(session = SessionState.Pairing(1, "Kelvin's MacBook Air", "053656")))
        assertEquals(StatusText("Pair with Kelvin's MacBook Air?", "Code 053 656. Check that the Mac shows the same code."), asking)
        val confirmed = StatusText.of(wifi.copy(session = SessionState.Pairing(1, "Kelvin's MacBook Air", "053656", confirmed = true)))
        assertEquals(StatusText("Pairing with Kelvin's MacBook Air", "Code 053 656 confirmed here. Confirm it on the Mac too."), confirmed)
        assertEquals("pairing", StatusText.short(wifi.copy(session = SessionState.Pairing(1, "Mac", "000001"))))

        val streaming = StatusText.of(wifi.copy(session = SessionState.Streaming(2, welcome, display, stream, null)))
        assertTrue(streaming.detail.endsWith(" · Wi‑Fi"), streaming.detail)
    }

    @Test
    fun explainsAnUnauthorizedAdbConnection() {
        val refused = ErrorMessage(ErrorCode.UNAUTHORIZED, "missing or wrong loopback token")
        val waiting = StatusText.of(
            ReceiverState(active = true, transport = TransportKind.ADB_TCP, connection = ConnectionState.WaitingToRetry(2, 500, "closed by peer"), lastRemoteError = refused),
        )
        assertEquals("Waiting for the Mac to authorize this USB connection", waiting.headline)
        assertTrue("Is Ginga running on the Mac?" in waiting.detail, waiting.detail)

        val streaming = StatusText.of(
            ReceiverState(active = true, transport = TransportKind.ADB_TCP, session = SessionState.Streaming(3, welcome, display, stream, null), lastRemoteError = refused),
        )
        assertEquals("Streaming from MacBook Air", streaming.headline)
        assertFalse("unauthorized" in streaming.detail, "a refusal from before the token arrived isn't shown")
    }

    @Test
    fun mapsCodecNamesToMimeTypes() {
        assertEquals("video/hevc", VideoPipeline.mimeType(Codec.HEVC))
        assertEquals("video/avc", VideoPipeline.mimeType(Codec("h264")))
        assertEquals("video/avc", VideoPipeline.mimeType(Codec("AVC")))
        assertNull(VideoPipeline.mimeType(Codec("av1")))
    }
}
