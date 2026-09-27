package dev.ginga.receiver.ui

import dev.ginga.protocol.ErrorCode
import dev.ginga.protocol.PairingCode
import dev.ginga.protocol.TransportKind
import dev.ginga.receiver.R
import dev.ginga.receiver.ReceiverState
import dev.ginga.receiver.direct.DirectState
import dev.ginga.receiver.session.SessionState
import dev.ginga.transport.ConnectionState
import java.util.Locale

/** Headline and detail line for the connection screen. Pure, so it's unit-tested. */
data class StatusText(val headline: String, val detail: String) {
    companion object {
        /** Headline and detail, plus the Mac's last ERROR when there is one. */
        fun of(state: ReceiverState): StatusText {
            val unauthorized = state.lastRemoteError?.code == ErrorCode.UNAUTHORIZED
            if (unauthorized && state.active && state.session !is SessionState.Streaming) {
                // Retried with backoff, and at once when the Mac hands over its adb token.
                return StatusText(
                    "Waiting for the Mac to authorize this USB connection",
                    "Is Ginga running on the Mac? It authorizes this tablet through adb when it starts.",
                )
            }
            val text = describe(state)
            val error = state.lastRemoteError?.takeUnless { unauthorized } ?: return text
            val line = "Mac reported ${error.code}: ${error.message}"
            return text.copy(detail = if (text.detail.isEmpty()) line else "${text.detail}\n$line")
        }

        private fun describe(state: ReceiverState): StatusText {
            val session = state.session
            if (!state.active) return idle(state)
            if (session is SessionState.Streaming) {
                val stream = session.stream
                val fps = if (stream.fps % 1.0 == 0.0) stream.fps.toInt().toString() else String.format(Locale.US, "%.1f", stream.fps)
                val via = when (state.transport) {
                    TransportKind.AOA -> " · direct USB"
                    TransportKind.ADB_TCP -> " · ADB"
                    TransportKind.WIFI_TLS -> " · Wi‑Fi"
                    else -> ""
                }
                val detail = "${stream.width}×${stream.height} ${stream.codec} @ $fps fps · ${session.display.name} (${session.display.orientation})$via"
                return if (session.paused) {
                    StatusText("Paused: ${session.welcome.mac.name}", "Nothing on screen shows the display, so the Mac stopped sending it. $detail")
                } else {
                    StatusText("Streaming from ${session.welcome.mac.name}", detail)
                }
            }
            if (session is SessionState.Pairing) {
                val code = session.code?.let(PairingCode::display)
                    ?: return StatusText("Pairing with ${session.macName}…", "Exchanging codes")
                return if (session.confirmed) {
                    StatusText("Pairing with ${session.macName}", "Code $code confirmed here. Confirm it on the Mac too.")
                } else {
                    StatusText("Pair with ${session.macName}?", "Code $code. Check that the Mac shows the same code.")
                }
            }
            if (session is SessionState.Suspended) {
                return StatusText("Paused", "Disconnected while the display isn't shown; reconnects when it opens.")
            }
            if (session is SessionState.Handshaking) {
                return if (state.transport == TransportKind.AOA) {
                    StatusText("Connected, waiting for the Mac…", "HELLO sent over USB. The Mac answers as soon as Ginga runs there.")
                } else {
                    StatusText("Connected, waiting for the Mac…", "HELLO sent")
                }
            }
            return when (val connection = state.connection) {
                ConnectionState.Idle -> StatusText("Starting…", "")
                is ConnectionState.Connecting -> StatusText("Connecting…", "${route(state)} (attempt ${connection.attempt})")
                is ConnectionState.Connected -> StatusText("Connected", "Waiting for the Mac")
                is ConnectionState.WaitingToRetry -> StatusText(
                    "Waiting for the Mac…",
                    "Retrying in ${String.format(Locale.US, "%.2f", connection.delayMs / 1000.0)} s" +
                        (connection.lastError?.let { " · $it" } ?: "") + retryHint(state),
                )
                is ConnectionState.Closed -> StatusText("Disconnected", connection.reason ?: "")
                ConnectionState.Suspended -> StatusText("Paused", "Reconnects when the display opens.")
            }
        }

        private fun idle(state: ReceiverState): StatusText {
            val last = state.endReason?.let { "Last session: $it" }
            val hint = if (state.accessoryAttached) "Your Mac is connected by USB. Tap Connect to use this tablet as its display." else null
            val detail = listOfNotNull(last, hint).joinToString("\n").ifEmpty { "Tap Connect to use this tablet as a display." }
            return StatusText("Not connected", detail)
        }

        private fun route(state: ReceiverState): String = when (state.transport) {
            TransportKind.AOA -> "Direct USB"
            TransportKind.WIFI_TLS -> "Wi‑Fi: ${state.wifiMacName ?: "Mac"}"
            else -> "127.0.0.1:47800 via adb reverse"
        }

        private fun retryHint(state: ReceiverState): String = when (state.transport) {
            TransportKind.AOA -> ""
            TransportKind.WIFI_TLS -> "\nIs Ginga running on the Mac, on the same network?"
            else -> "\nIs Ginga running on the Mac, with adb reverse tcp:47800 tcp:47800?"
        }

        /** One word for the overlay. */
        fun short(state: ReceiverState): String = when {
            !state.active -> "disconnected"
            (state.session as? SessionState.Streaming)?.paused == true -> "paused"
            state.session is SessionState.Streaming -> "streaming"
            state.session is SessionState.Suspended -> "suspended"
            state.session is SessionState.Pairing -> "pairing"
            state.session is SessionState.Handshaking -> "handshaking"
            state.connection is ConnectionState.WaitingToRetry -> "reconnecting"
            else -> "connecting"
        }
    }
}

/** The direct link's button and status line (§6b). Pure, so it's unit-tested. */
data class DirectText(val inProgress: Boolean, val status: UiText) {
    companion object {
        fun of(state: DirectState, keyMac: String?): DirectText = when (state) {
            DirectState.Idle -> DirectText(false, idle(keyMac))
            is DirectState.CreatingNetwork -> DirectText(true, UiText(R.string.direct_creating, state.network))
            is DirectState.WaitingForMac -> DirectText(true, UiText(R.string.direct_waiting, state.ssid))
            is DirectState.Connecting -> DirectText(true, UiText(R.string.direct_connecting))
            DirectState.Connected -> DirectText(true, UiText(R.string.direct_connected))
            is DirectState.Ended -> DirectText(false, UiText(R.string.direct_ended, state.reason, idle(keyMac)))
        }

        private fun idle(keyMac: String?): UiText =
            if (keyMac != null) UiText(R.string.direct_available, keyMac) else UiText(R.string.direct_unavailable)
    }
}
