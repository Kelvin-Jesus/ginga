package dev.ginga.receiver.adb

import dev.ginga.protocol.Hello
import dev.ginga.protocol.TransportKind
import dev.ginga.protocol.VersionRange
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LoopbackTokenTest {
    private val token = "0123456789abcdef".repeat(4)

    private class MemoryPersistence(var stored: String? = null) : TokenPersistence {
        var writes = 0

        override fun read(): String? = stored

        override fun write(token: String) {
            stored = token
            writes++
        }
    }

    private fun hello(transport: TransportKind) = Hello(
        versions = VersionRange(1, 1),
        app = Hello.App("Ginga for Android", "0.1.0"),
        device = Hello.Device("samsung", "SM-X730", "16", "id"),
        display = Hello.Display(2560, 1600, 274, listOf(60.0, 120.0), 0),
        decoders = emptyList(),
        transport = transport,
    )

    @Test
    fun onlyExactly64LowercaseHexDigitsAreAToken() {
        assertEquals(token, LoopbackToken.parse(token))
        assertNull(LoopbackToken.parse(null))
        assertNull(LoopbackToken.parse(""))
        assertNull(LoopbackToken.parse(token.dropLast(1)))
        assertNull(LoopbackToken.parse(token + "0"))
        assertNull(LoopbackToken.parse(token.uppercase()))
        assertNull(LoopbackToken.parse(token.replaceFirst('0', 'g')))
        assertNull(LoopbackToken.parse(" " + token.drop(1)))
    }

    @Test
    fun theStoreKeepsOnlyWellFormedTokensAndSurvivesARestart() {
        val persistence = MemoryPersistence()
        val store = LoopbackTokenStore(persistence)
        assertNull(store.token)
        assertFalse(store.offer("not a token"))
        assertNull(store.token)
        assertTrue(store.offer(token))
        assertEquals(token, store.token)
        assertFalse(store.offer("ff".repeat(31)), "a bad token doesn't replace a good one")
        assertEquals(token, store.token)
        assertEquals(1, persistence.writes)

        assertEquals(token, LoopbackTokenStore(persistence).token, "after an app restart")
        assertNull(LoopbackTokenStore(MemoryPersistence("tampered")).token, "a malformed stored value is ignored")
    }

    @Test
    fun helloCarriesTheTokenOverAdbOnly() {
        assertEquals(token, LoopbackToken.applyTo(hello(TransportKind.ADB_TCP), token).loopbackToken)
        assertNull(LoopbackToken.applyTo(hello(TransportKind.ADB_TCP), null).loopbackToken, "no token yet: connect anyway")
        assertNull(LoopbackToken.applyTo(hello(TransportKind.AOA), token).loopbackToken)
        assertNull(LoopbackToken.applyTo(hello(TransportKind.WIFI_TLS), token).loopbackToken)
        assertNull(LoopbackToken.applyTo(hello(TransportKind.ADB_TCP).copy(transport = null), token).loopbackToken)
    }
}
