package dev.tab2mac.protocol

import dev.tab2mac.protocol.DirectLinkCrypto.Purpose
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** PROTOCOL.md §6b vectors: direct key 32 × 0x55, keyId 0102030405060708, nonce 12 × 0x09. */
class DirectLinkCryptoTest {
    private val directKey = ByteArray(32) { 0x55 }
    private val keyId = "0102030405060708".hexToBytes()
    private val nonce = ByteArray(12) { 0x09 }

    private val credentialsBlob =
        "010203040506070809090909090909090909090984d6384c8360ca1c97f2b5354c30f35ccb1961920cd7301c93438ab8d442fa0ef146f13e25ccd8bb856c6f82620c7f286fc3091bbce7a7acf12dadd9b9aada33b652186f7eb733bba102d7161c0f799f9083cb5c446b17383218ddbb49ee77ab900f1192ab614461dd05153f5f693c471f6d512018aabdbd2d09c40454866d37617c9f4aadff1b9c98"
    private val addressBlob =
        "01020304050607080909090909090909090909099af08686334cc0577ef60d441003bab5e2b19fe31652a648ef1bff4c5b8903f0f81fdd6ccc40137e63717bd46e755357f041602a37e66320c9d3bc4000c127ddcc61ce22e75751ba0893ad83a578ce642e6057f5a36678f6eb2cc0955fdcfa66be02"
    private val credentials = DirectCredentials(1790000000, "t2-Example-Passphrase", "00112233445566778899aabbccddeeff", "DIRECT-T2-0102")
    private val address = DirectAddress("192.168.49.23", 55471, "00112233445566778899aabbccddeeff")

    @Test
    fun subkeysMatchTheVector() {
        assertEquals("1709054f28835a41ad5e66c72770770ac6975a9cd592406dfc9cda75d25c6aee", DirectLinkCrypto.subkey(directKey, Purpose.CREDENTIALS).toHex())
        assertEquals("e3d677f129ce82d2b42e4b51f5d936518d28db4520077c583d06567bb2866019", DirectLinkCrypto.subkey(directKey, Purpose.ADDRESS).toHex())
    }

    @Test
    fun credentialsSealToTheVectorAndOpenBack() {
        val subkey = DirectLinkCrypto.subkey(directKey, Purpose.CREDENTIALS)
        assertEquals(
            """{"expires":1790000000,"psk":"t2-Example-Passphrase","session":"00112233445566778899aabbccddeeff","ssid":"DIRECT-T2-0102"}""",
            credentials.encode().decodeToString(),
        )
        assertEquals(credentialsBlob, DirectLinkCrypto.seal(subkey, keyId, nonce, credentials.encode()).toHex())
        assertContentEquals(credentials.encode(), DirectLinkCrypto.open(subkey, keyId, credentialsBlob.hexToBytes()))
    }

    @Test
    fun theMacsAddressOpensAndSealsBackToTheVector() {
        val subkey = DirectLinkCrypto.subkey(directKey, Purpose.ADDRESS)
        val plaintext = DirectLinkCrypto.open(subkey, keyId, addressBlob.hexToBytes())!!
        assertEquals(address, DirectAddress.decode(plaintext))
        assertEquals(addressBlob, DirectLinkCrypto.seal(subkey, keyId, nonce, address.encode()).toHex())
    }

    @Test
    fun tamperedForeignOrShortBlobsDontOpen() {
        val subkey = DirectLinkCrypto.subkey(directKey, Purpose.ADDRESS)
        val tampered = addressBlob.hexToBytes().also { it[30] = (it[30] + 1).toByte() }
        assertNull(DirectLinkCrypto.open(subkey, keyId, tampered))
        assertNull(DirectLinkCrypto.open(subkey, "0102030405060709".hexToBytes(), addressBlob.hexToBytes()), "another key's blob")
        assertNull(DirectLinkCrypto.open(DirectLinkCrypto.subkey(directKey, Purpose.CREDENTIALS), keyId, addressBlob.hexToBytes()), "wrong subkey")
        assertNull(DirectLinkCrypto.open(subkey, keyId, ByteArray(20)))
        assertNull(DirectAddress.decode("not json".encodeToByteArray()))
        assertNull(DirectAddress.decode("""{"host":"","port":1,"session":"x"}""".encodeToByteArray()))
    }
}
