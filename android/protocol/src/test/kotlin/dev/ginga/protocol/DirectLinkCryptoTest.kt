package dev.ginga.protocol

import dev.ginga.protocol.DirectLinkCrypto.Purpose
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
        "01020304050607080909090909090909090909099f2fa452568ca28a265f8f20a285763f7681dcb148c12a085ae117d046ae61bcb27831e6ebea98d66170f2e14d9ced2dbf867fa7668ca1cbb75dc180323f700b276345f79d8e5fcfbe22eacba5221bf34d743879225aeb1e6022a12b24f2753566f99f9413d38173182cc6c39505376f99ae5c66985a096006fdff5857755fb50029c8a9e706f8f0c9da5beb"
    private val addressBlob =
        "0102030405060708090909090909090909090909923619aa87d7eb78090f3d480e07fb8aa350dbc7ac692467bc86d1d5f174cc5a8bc58d94045ddc34b17c4a1f956830bb6bfcddbbb3051fe54a47db3099df512b1dc54407012e375f7edd330268bac91be8335a2c4959b014548f3eebeb781cd44faf"
    private val credentials = DirectCredentials(1790000000, "gn-Example-Passphrase", "00112233445566778899aabbccddeeff", "DIRECT-Ginga-0102")
    private val address = DirectAddress("192.168.49.23", 55471, "00112233445566778899aabbccddeeff")

    @Test
    fun subkeysMatchTheVector() {
        assertEquals("75bc03cb45573842d8a842de4be2e8af48b937dd59f5d8fa3a8f4894b0a94aee", DirectLinkCrypto.subkey(directKey, Purpose.CREDENTIALS).toHex())
        assertEquals("ab1e4ff1ce626425d6a274df7b484e86ee138a2e44b5085952d184dabc27948b", DirectLinkCrypto.subkey(directKey, Purpose.ADDRESS).toHex())
    }

    @Test
    fun credentialsSealToTheVectorAndOpenBack() {
        val subkey = DirectLinkCrypto.subkey(directKey, Purpose.CREDENTIALS)
        assertEquals(
            """{"expires":1790000000,"psk":"gn-Example-Passphrase","session":"00112233445566778899aabbccddeeff","ssid":"DIRECT-Ginga-0102"}""",
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
