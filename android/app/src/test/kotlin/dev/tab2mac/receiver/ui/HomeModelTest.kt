package dev.tab2mac.receiver.ui

import dev.tab2mac.discovery.DiscoveredMac
import dev.tab2mac.discovery.TxtRecord
import dev.tab2mac.protocol.Codec
import dev.tab2mac.protocol.DisplayDescription
import dev.tab2mac.protocol.ErrorCode
import dev.tab2mac.protocol.ErrorMessage
import dev.tab2mac.protocol.Orientation
import dev.tab2mac.protocol.PixelDimensions
import dev.tab2mac.protocol.StreamDescription
import dev.tab2mac.protocol.TransportKind
import dev.tab2mac.protocol.Welcome
import dev.tab2mac.receiver.R
import dev.tab2mac.receiver.ReceiverState
import dev.tab2mac.receiver.WifiMac
import dev.tab2mac.receiver.direct.DirectState
import dev.tab2mac.receiver.session.SessionState
import dev.tab2mac.transport.ConnectionState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HomeModelTest {
    private val display = DisplayDescription(17, "Galaxy Tab S11", PixelDimensions(1280, 800), true, 60.0, Orientation.LANDSCAPE)
    private val stream = StreamDescription(Codec.HEVC, 2560, 1600, 60.0, 40_000)
    private val welcome = Welcome(1, "s", Welcome.Mac("MacBook Pro do Kelvin", "26.6.2", "0.3.0"), display, stream)
    private val streaming = SessionState.Streaming(3, welcome, display, stream, null)

    private fun mac(id: String, paired: Boolean = false, changed: Boolean = false) =
        WifiMac(DiscoveredMac("svc-$id", emptyList(), 47801, TxtRecord(1, id, "Mac $id")), paired, changed)

    @Test
    fun searchesOverWifiUntilAMacShowsUp() {
        val model = HomeModel.of(ReceiverState(), emptyList(), null)
        assertEquals(HomePanel.Searching, model.panel)
        assertEquals(StatusPill(Orbit.SEARCHING, UiText(R.string.status_searching)), model.pill)
        assertEquals(ConnectMethod.WIFI, model.method)
        assertNull(model.notice)
    }

    @Test
    fun listsMacsWithTheRightAction() {
        val macs = listOf(mac("a"), mac("b", paired = true), mac("c", paired = true, changed = true))
        val model = HomeModel.of(ReceiverState(), macs, null)
        val found = assertIs<HomePanel.Found>(model.panel)
        assertEquals(listOf(R.string.mac_connect, R.string.mac_reconnect, R.string.mac_pair_again), found.macs.map { it.action.id })
        assertEquals(listOf(R.string.mac_meta_new, R.string.mac_meta_paired, R.string.mac_meta_changed), found.macs.map { it.meta.id })
        assertEquals(Orbit.OFF, model.pill.orbit)
    }

    @Test
    fun chipsPickTheMethodAndTheCableSuggestsUsb() {
        assertEquals(HomePanel.Usb(attached = false), HomeModel.of(ReceiverState(), listOf(mac("a")), ConnectMethod.USB).panel)
        val attached = HomeModel.of(ReceiverState(accessoryAttached = true), emptyList(), null)
        assertEquals(ConnectMethod.USB, attached.method)
        assertEquals(HomePanel.Usb(attached = true), attached.panel)
        assertEquals(UiText(R.string.status_cable), attached.pill.text)
        // The user's choice wins over the cable.
        assertEquals(HomePanel.Searching, HomeModel.of(ReceiverState(accessoryAttached = true), emptyList(), ConnectMethod.WIFI).panel)
    }

    @Test
    fun directLinkNeedsAKeyAndHidesTheChipsWhileRunning() {
        val unavailable = HomeModel.of(ReceiverState(), emptyList(), ConnectMethod.DIRECT).panel
        assertEquals(HomePanel.Direct(false, false, UiText(R.string.direct_unavailable)), unavailable)
        val available = HomeModel.of(ReceiverState(directKeyMac = "MacBook"), emptyList(), ConnectMethod.DIRECT).panel
        assertEquals(HomePanel.Direct(false, true, UiText(R.string.direct_available, "MacBook")), available)

        val running = HomeModel.of(ReceiverState(direct = DirectState.WaitingForMac("DIRECT-T2", "Wi‑Fi Direct")), emptyList(), ConnectMethod.WIFI)
        assertEquals(
            HomePanel.Direct(true, true, UiText(R.string.direct_waiting, "DIRECT-T2"), "DIRECT-T2", UiText(R.string.direct_orbit)),
            running.panel,
        )
        // While the network is being created there is no name yet, and the line says so.
        val creating = HomeModel.of(ReceiverState(direct = DirectState.CreatingNetwork("Wi‑Fi Direct")), emptyList(), null).panel
        assertEquals(
            HomePanel.Direct(true, true, UiText(R.string.direct_creating, "Wi‑Fi Direct"), null, UiText(R.string.direct_creating, "Wi‑Fi Direct")),
            creating,
        )
        assertNull(running.method)
        assertEquals(Orbit.SEARCHING, running.pill.orbit)
    }

    @Test
    fun pairingShowsTheCodeThenWaitsForTheMac() {
        val wifi = ReceiverState(active = true, transport = TransportKind.WIFI_TLS, wifiMacName = "MacBook")
        val exchanging = HomeModel.of(wifi.copy(session = SessionState.Pairing(1, "MacBook")), emptyList(), null)
        assertEquals(HomePanel.Pairing("MacBook", null, false), exchanging.panel)
        assertEquals(StatusPill(Orbit.PAIRING, UiText(R.string.status_exchanging)), exchanging.pill)
        assertNull(exchanging.method, "no chips while a connection is under way")

        val asking = HomeModel.of(wifi.copy(session = SessionState.Pairing(1, "MacBook", "482913")), emptyList(), null)
        assertEquals(HomePanel.Pairing("MacBook", "482913", false), asking.panel)
        assertEquals(UiText(R.string.status_waiting_code), asking.pill.text)

        val confirmed = HomeModel.of(wifi.copy(session = SessionState.Pairing(1, "MacBook", "482913", true)), emptyList(), null)
        assertEquals(UiText(R.string.status_waiting_mac), confirmed.pill.text)
    }

    @Test
    fun connectingSaysHowAndWhatToCheck() {
        val usb = HomeModel.of(ReceiverState(active = true, transport = TransportKind.AOA, connection = ConnectionState.Connecting(1)), emptyList(), null)
        assertEquals(HomePanel.Connecting(UiText(R.string.connecting_usb), null), usb.panel)
        assertEquals(StatusPill(Orbit.SEARCHING, UiText(R.string.status_connecting)), usb.pill)

        val wifi = HomeModel.of(
            ReceiverState(active = true, transport = TransportKind.WIFI_TLS, wifiMacName = "MacBook", connection = ConnectionState.WaitingToRetry(2, 500, "refused")),
            emptyList(),
            null,
        )
        assertEquals(HomePanel.Connecting(UiText(R.string.waiting_mac_title), UiText(R.string.waiting_hint_wifi)), wifi.panel)
        assertEquals(UiText(R.string.status_waiting_mac), wifi.pill.text)

        val handshake = HomeModel.of(ReceiverState(active = true, transport = TransportKind.ADB_TCP, session = SessionState.Handshaking(1)), emptyList(), null)
        assertEquals(HomePanel.Connecting(UiText(R.string.handshake_title), null), handshake.panel)

        val unauthorized = HomeModel.of(
            ReceiverState(active = true, transport = TransportKind.ADB_TCP, lastRemoteError = ErrorMessage(ErrorCode.UNAUTHORIZED, "token")),
            emptyList(),
            null,
        )
        assertEquals(HomePanel.Connecting(UiText(R.string.authorize_title), UiText(R.string.authorize_sub)), unauthorized.panel)
        assertNull(unauthorized.notice, "an adb refusal is explained, not reported as an error")
    }

    @Test
    fun connectedAndPausedShowTheSpecs() {
        val live = HomeModel.of(ReceiverState(active = true, transport = TransportKind.WIFI_TLS, session = streaming), emptyList(), null)
        val specs = UiText(R.string.specs, "2560×1600", "60", UiText(R.string.via_wifi))
        assertEquals(HomePanel.Connected(false, UiText(R.string.connected_sub, "MacBook Pro do Kelvin"), specs, true), live.panel)
        assertEquals(StatusPill(Orbit.CONNECTED, UiText(R.string.status_connected, "60", UiText(R.string.via_wifi))), live.pill)

        val paused = HomeModel.of(ReceiverState(active = true, transport = TransportKind.AOA, session = streaming.copy(paused = true)), emptyList(), null)
        val panel = assertIs<HomePanel.Connected>(paused.panel)
        assertTrue(panel.paused)
        assertEquals(UiText(R.string.paused_sub), panel.explanation)
        assertEquals(UiText(R.string.via_usb), panel.specs!!.args[2])
        assertEquals(Orbit.PAUSED, paused.pill.orbit)

        val suspended = HomeModel.of(ReceiverState(active = true, connection = ConnectionState.Suspended, session = SessionState.Suspended), emptyList(), null)
        assertEquals(HomePanel.Connected(true, UiText(R.string.suspended_sub), null, true), suspended.panel)
    }

    @Test
    fun theDirectLinkIsNamedInTheSpecs() {
        val state = ReceiverState(active = true, transport = TransportKind.WIFI_TLS, direct = DirectState.Connected, session = streaming)
        assertEquals(UiText(R.string.via_direct), HomeModel.via(state))
        assertEquals(UiText(R.string.status_connected, "60", UiText(R.string.via_direct)), HomeModel.connectedText(streaming, state))
    }

    @Test
    fun macErrorsAreReportedInWords() {
        val model = HomeModel.of(ReceiverState(lastRemoteError = ErrorMessage(ErrorCode.INTERNAL, "cannot create display")), emptyList(), null)
        assertEquals(UiText(R.string.notice_mac_error, "cannot create display"), model.notice)
        assertEquals(StatusPill(Orbit.ERROR, UiText(R.string.status_error)), model.pill)
    }

    @Test
    fun formatsTheRefreshRate() {
        assertEquals("60", HomeModel.fps(60.0))
        assertEquals("120", HomeModel.fps(120.0))
        assertEquals("59.9", HomeModel.fps(59.94))
    }

    @Test
    fun streamWaitingLineNamesTheMac() {
        assertEquals(UiText(R.string.stream_from, "MacBook Pro do Kelvin"), StreamWaitingText.of(ReceiverState(active = true, session = streaming)))
        assertEquals(UiText(R.string.status_paused), StreamWaitingText.of(ReceiverState(active = true, session = streaming.copy(paused = true))))
        assertEquals(UiText(R.string.connecting_title), StreamWaitingText.of(ReceiverState(active = true)))
    }

    @Test
    fun refreshChoicesMapToHertz() {
        assertEquals(RefreshChoice.MAC, RefreshChoice.of(null))
        assertEquals(RefreshChoice.HZ_60, RefreshChoice.of(60))
        assertEquals(RefreshChoice.HZ_120, RefreshChoice.of(120))
        assertEquals(RefreshChoice.MAC, RefreshChoice.of(90))
        assertEquals(listOf(null, 60, 120), RefreshChoice.entries.map { it.hz })
    }

    @Test
    fun motionRules() {
        assertTrue(Motion.isReduced(0f))
        assertEquals(false, Motion.isReduced(1f))
        assertEquals(false, Motion.isReduced(0.5f))
        assertEquals(listOf(0L, 120L, 240L), (0..2).map { Motion.staggerDelay(it, Motion.RISE_STAGGER) })
        assertEquals(300L, Motion.staggerDelay(5, Motion.DIGIT_STAGGER))
        assertEquals(0L, Motion.staggerDelay(-1, Motion.DIGIT_STAGGER))
    }
}
