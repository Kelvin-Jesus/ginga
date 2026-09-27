package dev.ginga.receiver.ui

import dev.ginga.discovery.DiscoveredMac
import dev.ginga.discovery.TxtRecord
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
import dev.ginga.receiver.WifiMac
import dev.ginga.receiver.direct.DirectState
import dev.ginga.receiver.session.SessionState
import dev.ginga.transport.ConnectionState

/**
 * Debug builds only (`MainActivity.handleAutomation`, `--es preview <name>`): made-up states that
 * draw each home panel without a Mac, for screenshots on an emulator (phone and tablet sizes).
 * Nothing here is connected to the real controller; `--es preview off` returns to it.
 */
data class HomePreview(val state: ReceiverState, val macs: List<WifiMac> = emptyList(), val method: ConnectMethod? = null) {
    companion object {
        /**
         * searching, found, usb, usb-plug, direct, direct-screen, exchanging, pairing,
         * pairing-confirmed, connecting, waiting, connected, paused, error; null for anything else.
         */
        fun of(name: String): HomePreview? {
            val macName = "MacBook Pro do Kelvin"
            val display = DisplayDescription(17, "Galaxy", PixelDimensions(1280, 800), true, 60.0, Orientation.LANDSCAPE)
            val stream = StreamDescription(Codec.HEVC, 2560, 1600, 60.0, 40_000)
            val welcome = Welcome(1, "s", Welcome.Mac(macName, "26.6.2", "0.3.0"), display, stream)
            val streaming = SessionState.Streaming(3, welcome, display, stream, null)
            val wifi = ReceiverState(active = true, transport = TransportKind.WIFI_TLS, wifiMacName = macName)
            return when (name) {
                "searching" -> HomePreview(ReceiverState(), method = ConnectMethod.WIFI)
                "found" -> HomePreview(
                    ReceiverState(),
                    listOf(mac("a", macName, paired = true), mac("b", "Mac mini do estúdio"), mac("c", "iMac da sala", paired = true, changed = true)),
                    ConnectMethod.WIFI,
                )
                "usb" -> HomePreview(ReceiverState(accessoryAttached = true))
                "usb-plug" -> HomePreview(ReceiverState(), method = ConnectMethod.USB)
                "direct" -> HomePreview(ReceiverState(directKeyMac = macName), method = ConnectMethod.DIRECT)
                "direct-screen" -> HomePreview(ReceiverState(direct = DirectState.WaitingForMac("DIRECT-Gn-4F2A", "Wi‑Fi Direct"), directKeyMac = macName))
                "exchanging" -> HomePreview(wifi.copy(session = SessionState.Pairing(1, macName)))
                "pairing" -> HomePreview(wifi.copy(session = SessionState.Pairing(1, macName, "482913")))
                "pairing-confirmed" -> HomePreview(wifi.copy(session = SessionState.Pairing(1, macName, "482913", confirmed = true)))
                "connecting" -> HomePreview(wifi.copy(connection = ConnectionState.Connecting(1)))
                "waiting" -> HomePreview(wifi.copy(connection = ConnectionState.WaitingToRetry(2, 4_000, null)))
                "connected" -> HomePreview(wifi.copy(session = streaming))
                "paused" -> HomePreview(wifi.copy(session = streaming.copy(paused = true)))
                "error" -> HomePreview(ReceiverState(lastRemoteError = ErrorMessage(ErrorCode.INTERNAL, "The virtual display could not be created.")), method = ConnectMethod.WIFI)
                else -> null
            }
        }

        private fun mac(id: String, name: String, paired: Boolean = false, changed: Boolean = false) =
            WifiMac(DiscoveredMac("svc-$id", emptyList(), 47801, TxtRecord(1, id, name)), paired, changed)
    }
}
