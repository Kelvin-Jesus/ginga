package dev.tab2mac.transport

import dev.tab2mac.protocol.Fingerprint
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PinsTest {
    private val macFingerprint = Fingerprint.fromBytes(ByteArray(32) { 0x11 })
    private val otherFingerprint = Fingerprint.fromBytes(ByteArray(32) { 0x33 })

    @Test
    fun pinsSurviveEncoding() {
        val pins = listOf(
            PinnedMac("3f2a91c07d11", "Kelvin's MacBook Air", macFingerprint),
            PinnedMac("b7", "Studio \"Mac\"", otherFingerprint),
        )
        assertEquals(pins, PinCodec.decode(PinCodec.encode(pins)))
    }

    @Test
    fun malformedPinsAreSkipped() {
        assertEquals(emptyList(), PinCodec.decode("not json"))
        assertEquals(emptyList(), PinCodec.decode("""{"id":"x"}"""))
        val text = """[{"id":"a","fingerprint":"${macFingerprint.hex}"},{"id":"b","fingerprint":"zz"},{"name":"no id"},7]"""
        assertEquals(listOf(PinnedMac("a", "a", macFingerprint)), PinCodec.decode(text))
    }

    @Test
    fun anUnknownMacIsAcceptedAndThenPairs() {
        assertNull(PinnedMacVerifier(InMemoryPinStore(), "mac").refusal(macFingerprint))
    }

    @Test
    fun aPinnedMacMustPresentThePinnedCertificate() {
        val pins = InMemoryPinStore(listOf(PinnedMac("mac", "Mac", macFingerprint)))
        assertNull(PinnedMacVerifier(pins, "mac").refusal(macFingerprint))
        assertEquals(PinnedMacVerifier.IDENTITY_CHANGED, PinnedMacVerifier(pins, "mac").refusal(otherFingerprint))
        assertNull(PinnedMacVerifier(pins, "another-mac").refusal(otherFingerprint), "pins are per Mac id")
        pins.remove("mac")
        assertNull(PinnedMacVerifier(pins, "mac").refusal(otherFingerprint), "forgotten: pair again")
    }
}
