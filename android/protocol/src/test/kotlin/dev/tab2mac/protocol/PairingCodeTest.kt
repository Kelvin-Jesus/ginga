package dev.tab2mac.protocol

import java.security.MessageDigest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull

class PairingCodeTest {
    private val mac = Fingerprint.fromBytes(ByteArray(32) { 0x11 })
    private val tablet = Fingerprint.fromBytes(ByteArray(32) { 0x22 })
    private val macNonce = ByteArray(32) { 0x33 }
    private val tabletNonce = ByteArray(32) { 0x44 }

    @Test
    fun matchesTheProtocolVector() {
        // PROTOCOL.md §6; the Swift suite asserts the same values.
        assertEquals(
            "052c957131b84f9b12e9519024c730dbf4fa95abac4b8d2e5b1118b2cef8ec89",
            PairingCode.hex(PairingCode.commitment(tablet, mac, tabletNonce)),
        )
        assertEquals("053656", PairingCode.code(mac, tablet, macNonce, tabletNonce))
        assertEquals("053 656", PairingCode.display("053656"))
    }

    @Test
    fun theOrderOfEveryInputMatters() {
        val code = PairingCode.code(mac, tablet, macNonce, tabletNonce)
        assertNotEquals(code, PairingCode.code(tablet, mac, macNonce, tabletNonce))
        assertNotEquals(code, PairingCode.code(mac, tablet, tabletNonce, macNonce))
        assertFalse(PairingCode.commitment(tablet, mac, tabletNonce).contentEquals(PairingCode.commitment(mac, tablet, tabletNonce)))
    }

    @Test
    fun eachAttemptGetsAFreshNonce() {
        val first = PairingCode.newNonce()
        assertEquals(32, first.size)
        assertFalse(first.contentEquals(PairingCode.newNonce()))
    }

    @Test
    fun codesAreZeroPaddedToSixDigits() {
        val padded = (0 until 2_000).asSequence()
            .map { seed -> PairingCode.code(mac, tablet, ByteArray(32) { (it * 7 + seed).toByte() }, tabletNonce) }
            .first { it.startsWith("0") }
        assertEquals(6, padded.length)
    }

    @Test
    fun nonceFieldsAreExactly64LowercaseHexDigits() {
        assertContentEquals(macNonce, PairingCode.parseHex("33".repeat(32)))
        assertNull(PairingCode.parseHex(null))
        assertNull(PairingCode.parseHex("33".repeat(31)))
        assertNull(PairingCode.parseHex("AB".repeat(32)), "uppercase is malformed")
        assertNull(PairingCode.parseHex("zz".repeat(32)))
        assertFailsWith<IllegalArgumentException> { PairingCode.code(mac, tablet, ByteArray(31), tabletNonce) }
    }

    @Test
    fun aFingerprintIsTheSha256OfTheCertificateDer() {
        val der = ByteArray(300) { (it * 13).toByte() }
        val fingerprint = Fingerprint.of(der)
        assertEquals(MessageDigest.getInstance("SHA-256").digest(der).toHex(), fingerprint.hex)
        assertEquals(fingerprint, Fingerprint.fromHex(fingerprint.hex))
        assertEquals(fingerprint.hashCode(), Fingerprint.fromBytes(fingerprint.toByteArray()).hashCode())
        assertNull(Fingerprint.fromHex("abc"))
        assertNull(Fingerprint.fromHex("zz".repeat(32)))
        assertFailsWith<IllegalArgumentException> { Fingerprint.fromBytes(ByteArray(31)) }
    }
}
