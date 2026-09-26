package dev.tab2mac.receiver

import dev.tab2mac.protocol.TransportKind
import dev.tab2mac.receiver.AccessoryAutoConnect.Decision
import kotlin.test.Test
import kotlin.test.assertEquals

class AccessoryAutoConnectTest {
    private fun decide(
        accessoryReady: Boolean = true,
        autoReconnect: Boolean = true,
        blocked: Boolean = false,
        current: TransportKind? = null,
        streaming: Boolean = false,
    ) = AccessoryAutoConnect.decide(accessoryReady, autoReconnect, blocked, current, streaming)

    @Test
    fun opensTheAccessoryWhenNothingRuns() {
        // The Mac app restarted, or this app was reinstalled, while the tablet stayed in accessory mode.
        assertEquals(Decision.CONNECT, decide())
    }

    @Test
    fun onlyWithAnAttachedPermittedAccessoryAndReconnectOn() {
        assertEquals(Decision.NONE, decide(accessoryReady = false))
        assertEquals(Decision.NONE, decide(autoReconnect = false))
    }

    @Test
    fun notAfterTheUserOrTheMacEndedItOnPurpose() {
        assertEquals(Decision.NONE, decide(blocked = true))
    }

    @Test
    fun theAccessoryWinsOverAnAdbSessionThatIsNotStreaming() {
        assertEquals(Decision.REPLACE, decide(current = TransportKind.ADB_TCP))
        assertEquals(Decision.NONE, decide(current = TransportKind.ADB_TCP, streaming = true), "a live picture isn't interrupted")
    }

    @Test
    fun leavesOtherSessionsAlone() {
        assertEquals(Decision.NONE, decide(current = TransportKind.AOA))
        assertEquals(Decision.NONE, decide(current = TransportKind.WIFI_TLS))
    }
}
