package dev.tab2mac.receiver.ui

import android.content.Context
import dev.tab2mac.protocol.ErrorCode
import dev.tab2mac.protocol.TransportKind
import dev.tab2mac.receiver.R
import dev.tab2mac.receiver.ReceiverState
import dev.tab2mac.receiver.WifiMac
import dev.tab2mac.receiver.direct.DirectState
import dev.tab2mac.receiver.session.SessionState
import dev.tab2mac.transport.ConnectionState
import java.util.Locale

/**
 * A string resource and its format arguments, resolved against the current locale only when
 * shown. Arguments may be [UiText]s themselves. Pure, so the mapping below is unit-tested.
 */
data class UiText(val id: Int, val args: List<Any> = emptyList()) {
    constructor(id: Int, vararg args: Any) : this(id, args.toList())

    fun resolve(context: Context): String =
        context.getString(id, *args.map { if (it is UiText) it.resolve(context) else it }.toTypedArray())
}

/** How the user wants to reach the Mac while nothing is connected: the chips of the home screen. */
enum class ConnectMethod { WIFI, USB, DIRECT }

/** The StatusOrbit's planet: its colour and its animation (orbit, pulse or still). */
enum class Orbit { OFF, SEARCHING, PAIRING, CONNECTED, PAUSED, ERROR }

/** The single StatusOrbit pill at the top of a screen. */
data class StatusPill(val orbit: Orbit, val text: UiText)

/** A Mac found on the network, as a DeviceRow. */
data class MacRow(val mac: WifiMac, val meta: UiText, val action: UiText)

/** What the home screen shows below the header: one decision at a time (flows.md, "Tablet"). */
sealed interface HomePanel {
    /** Wi‑Fi, nothing found yet: the radar. */
    data object Searching : HomePanel

    /** Wi‑Fi, Macs on the network. */
    data class Found(val macs: List<MacRow>) : HomePanel

    /** The USB cable: plug it in (or connect, when the Mac's accessory is attached). */
    data class Usb(val attached: Boolean) : HomePanel

    /**
     * No router (§6b): this tablet's own network. While it is [inProgress], its own screen shows
     * the galaxy, the network's [ssid] (as the direct-link flow made it; null until it is up) and
     * [screenLine].
     */
    data class Direct(
        val inProgress: Boolean,
        val canStart: Boolean,
        val status: UiText,
        val ssid: String? = null,
        val screenLine: UiText? = null,
    ) : HomePanel

    /** Wi‑Fi pairing (§6): the same six digits on both screens. [code] is null while exchanging. */
    data class Pairing(val macName: String, val code: String?, val confirmed: Boolean) : HomePanel

    /** A connection is being made. */
    data class Connecting(val title: UiText, val detail: UiText?) : HomePanel

    /** Connected (streaming), or paused. */
    data class Connected(
        val paused: Boolean,
        val explanation: UiText,
        val specs: UiText?,
        val canShowDisplay: Boolean,
    ) : HomePanel
}

/**
 * The home screen for a [ReceiverState]. [method] is the chip in effect when nothing is
 * connected, or null when the chips are hidden. [notice] is a problem worth a line of its own.
 */
data class HomeModel(
    val pill: StatusPill,
    val panel: HomePanel,
    val method: ConnectMethod?,
    val notice: UiText?,
) {
    companion object {
        /**
         * [chosen] is the chip the user picked, if any: otherwise USB when the Mac's accessory is
         * attached, Wi‑Fi (the recommended path) when not.
         */
        fun of(state: ReceiverState, macs: List<WifiMac>, chosen: ConnectMethod?): HomeModel {
            val notice = state.lastRemoteError
                ?.takeUnless { it.code == ErrorCode.UNAUTHORIZED }
                ?.let { UiText(R.string.notice_mac_error, it.message) }
            if (state.active) return active(state, notice)
            val direct = DirectText.of(state.direct, state.directKeyMac)
            if (direct.inProgress) {
                val pill = StatusPill(Orbit.SEARCHING, UiText(R.string.status_direct))
                val ssid = (state.direct as? DirectState.WaitingForMac)?.ssid
                // Creating the network says so; once it is up, the Mac is entering its orbit.
                val line = if (state.direct is DirectState.CreatingNetwork) direct.status else UiText(R.string.direct_orbit)
                return HomeModel(pill, HomePanel.Direct(true, true, direct.status, ssid, line), null, notice)
            }
            val method = chosen ?: if (state.accessoryAttached) ConnectMethod.USB else ConnectMethod.WIFI
            val (pill, panel) = when (method) {
                ConnectMethod.WIFI -> if (macs.isEmpty()) {
                    StatusPill(Orbit.SEARCHING, UiText(R.string.status_searching)) to HomePanel.Searching
                } else {
                    StatusPill(Orbit.OFF, UiText(R.string.status_found)) to HomePanel.Found(macs.map(::row))
                }
                ConnectMethod.USB -> StatusPill(
                    Orbit.OFF,
                    UiText(if (state.accessoryAttached) R.string.status_cable else R.string.status_off),
                ) to HomePanel.Usb(state.accessoryAttached)
                ConnectMethod.DIRECT -> StatusPill(Orbit.OFF, UiText(R.string.status_off)) to
                    HomePanel.Direct(false, state.directKeyMac != null, direct.status)
            }
            val errorPill = if (notice != null) StatusPill(Orbit.ERROR, UiText(R.string.status_error)) else pill
            return HomeModel(errorPill, panel, method, notice)
        }

        private fun row(mac: WifiMac): MacRow = MacRow(
            mac = mac,
            meta = UiText(
                when {
                    mac.identityChanged -> R.string.mac_meta_changed
                    mac.paired -> R.string.mac_meta_paired
                    else -> R.string.mac_meta_new
                },
            ),
            action = UiText(
                when {
                    mac.identityChanged -> R.string.mac_pair_again
                    mac.paired -> R.string.mac_reconnect
                    else -> R.string.mac_connect
                },
            ),
        )

        private fun active(state: ReceiverState, notice: UiText?): HomeModel {
            val session = state.session
            if (session is SessionState.Streaming) {
                val specs = UiText(
                    R.string.specs,
                    "${session.stream.width}×${session.stream.height}",
                    fps(session.stream.fps),
                    via(state),
                )
                return if (session.paused) {
                    HomeModel(
                        StatusPill(Orbit.PAUSED, UiText(R.string.status_paused)),
                        HomePanel.Connected(true, UiText(R.string.paused_sub), specs, canShowDisplay = true),
                        null,
                        notice,
                    )
                } else {
                    HomeModel(
                        StatusPill(Orbit.CONNECTED, connectedText(session, state)),
                        HomePanel.Connected(false, UiText(R.string.connected_sub, session.welcome.mac.name), specs, canShowDisplay = true),
                        null,
                        notice,
                    )
                }
            }
            if (session is SessionState.Suspended || state.connection == ConnectionState.Suspended) {
                return HomeModel(
                    StatusPill(Orbit.PAUSED, UiText(R.string.status_paused)),
                    HomePanel.Connected(true, UiText(R.string.suspended_sub), null, canShowDisplay = true),
                    null,
                    notice,
                )
            }
            if (session is SessionState.Pairing) {
                val pill = when {
                    session.code == null -> UiText(R.string.status_exchanging)
                    session.confirmed -> UiText(R.string.status_waiting_mac)
                    else -> UiText(R.string.status_waiting_code)
                }
                return HomeModel(StatusPill(Orbit.PAIRING, pill), HomePanel.Pairing(session.macName, session.code, session.confirmed), null, notice)
            }
            if (state.lastRemoteError?.code == ErrorCode.UNAUTHORIZED) {
                // adb: retried with backoff, and at once when the Mac hands over its token.
                return HomeModel(
                    StatusPill(Orbit.PAIRING, UiText(R.string.status_authorizing)),
                    HomePanel.Connecting(UiText(R.string.authorize_title), UiText(R.string.authorize_sub)),
                    null,
                    null,
                )
            }
            val connecting = when {
                session is SessionState.Handshaking -> HomePanel.Connecting(UiText(R.string.handshake_title), null)
                state.connection is ConnectionState.WaitingToRetry -> HomePanel.Connecting(UiText(R.string.waiting_mac_title), waitingHint(state))
                else -> HomePanel.Connecting(connectingTitle(state), null)
            }
            val pill = if (state.connection is ConnectionState.WaitingToRetry) UiText(R.string.status_waiting_mac) else UiText(R.string.status_connecting)
            return HomeModel(StatusPill(Orbit.SEARCHING, pill), connecting, null, notice)
        }

        private fun connectingTitle(state: ReceiverState): UiText = when (state.transport) {
            TransportKind.AOA -> UiText(R.string.connecting_usb)
            TransportKind.WIFI_TLS -> state.wifiMacName?.let { UiText(R.string.connecting_wifi, it) } ?: UiText(R.string.connecting_title)
            TransportKind.ADB_TCP -> UiText(R.string.connecting_adb)
            else -> UiText(R.string.connecting_title)
        }

        private fun waitingHint(state: ReceiverState): UiText = when (state.transport) {
            TransportKind.AOA -> UiText(R.string.waiting_hint_usb)
            TransportKind.WIFI_TLS -> UiText(R.string.waiting_hint_wifi)
            else -> UiText(R.string.waiting_hint_adb)
        }

        /** "Conectado · 60 Hz · Wi‑Fi": the pill on the home screen and the stream's first-frame toast. */
        fun connectedText(session: SessionState.Streaming, state: ReceiverState): UiText =
            UiText(R.string.status_connected, fps(session.stream.fps), via(state))

        /** How the stream reaches this tablet, in words. */
        fun via(state: ReceiverState): UiText = when (state.transport) {
            TransportKind.AOA, TransportKind.ADB_TCP -> UiText(R.string.via_usb)
            TransportKind.WIFI_TLS -> UiText(if (state.direct == DirectState.Connected) R.string.via_direct else R.string.via_wifi)
            else -> UiText(R.string.via_wifi)
        }

        /** 60.0 → "60"; 59.94 → "59.9". */
        fun fps(value: Double): String =
            if (value % 1.0 == 0.0) value.toInt().toString() else String.format(Locale.US, "%.1f", value)
    }
}

/** The stream screen's line before the first frame: "Transmitindo de <Mac>". */
object StreamWaitingText {
    fun of(state: ReceiverState): UiText {
        val session = state.session
        return when {
            session is SessionState.Streaming && session.paused -> UiText(R.string.status_paused)
            session is SessionState.Streaming -> UiText(R.string.stream_from, session.welcome.mac.name)
            session is SessionState.Suspended -> UiText(R.string.status_paused)
            else -> UiText(R.string.connecting_title)
        }
    }
}
