package dev.tab2mac.receiver.direct

import dev.tab2mac.protocol.DirectLink
import dev.tab2mac.receiver.security.DirectKeyCodec
import dev.tab2mac.receiver.ui.DirectText
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DirectKeyCodecTest {
    private val message = DirectLink("0102030405060708", "55".repeat(32))

    @Test
    fun keysAreValidatedStrictly() {
        val key = DirectKeyCodec.parse(message, "MacBook Air")!!
        assertEquals("0102030405060708", key.keyIdHex)
        assertEquals(32, key.key.size)
        assertNull(DirectKeyCodec.parse(message.copy(keyId = "01020304"), "Mac"))
        assertNull(DirectKeyCodec.parse(message.copy(key = "55".repeat(31)), "Mac"))
        assertNull(DirectKeyCodec.parse(message.copy(key = "5G".repeat(32)), "Mac"))
        assertNull(DirectKeyCodec.parse(message.copy(keyId = "0102030405060708".uppercase().replace('0', 'A')), "Mac"))
    }

    @Test
    fun theStoreRoundTripsAndSkipsGarbage() {
        val keys = listOf(DirectKeyCodec.parse(message, "MacBook Air")!!, DirectKeyCodec.parse(DirectLink("1111111111111111", "66".repeat(32)), "Studio")!!)
        val decoded = DirectKeyCodec.decode(DirectKeyCodec.encode(keys))
        assertEquals(listOf("0102030405060708", "1111111111111111"), decoded.map { it.keyIdHex })
        assertTrue(decoded[1].key.contentEquals(ByteArray(32) { 0x66 }))
        assertEquals("Studio", decoded[1].macName)
        assertEquals(emptyList(), DirectKeyCodec.decode(null))
        assertEquals(emptyList(), DirectKeyCodec.decode("not json"))
        assertEquals(1, DirectKeyCodec.decode("""[{"keyId":"0102030405060708","key":"${"55".repeat(32)}"},{"keyId":"x","key":"y"}]""").size)
    }

    @Test
    fun theKeyNeverShowsInStrings() {
        val key = DirectKeyCodec.parse(message, "Mac")!!
        assertFalse("5555" in key.toString())
        assertFalse("5555" in message.toString())
    }

    @Test
    fun directTextFollowsTheState() {
        assertFalse(DirectText.of(DirectState.Idle, null).inProgress)
        assertTrue("one connection" in DirectText.of(DirectState.Idle, null).status)
        assertTrue(DirectText.of(DirectState.CreatingNetwork("Wi‑Fi Direct"), "Mac").inProgress)
        assertEquals(
            "Waiting for the Mac: network DIRECT-T2-0102 is up. On the Mac, choose Direct connection.",
            DirectText.of(DirectState.WaitingForMac("DIRECT-T2-0102", "Wi‑Fi Direct"), "Mac").status,
        )
        assertTrue(DirectText.of(DirectState.Connected, "Mac").inProgress)
        val ended = DirectText.of(DirectState.Ended("cancelled"), "MacBook Air")
        assertFalse(ended.inProgress)
        assertTrue(ended.status.startsWith("Direct connection ended: cancelled."), ended.status)
    }
}
