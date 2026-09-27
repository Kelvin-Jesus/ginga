package dev.ginga.protocol

import java.security.GeneralSecurityException
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException

/**
 * §6b: what travels over Bluetooth LE while the tablet hosts a direct link. Each blob is
 * `keyId (8) ‖ nonce (12) ‖ AES-256-GCM ciphertext ‖ tag (16)`, with the keyId as AAD, under a
 * subkey `HKDF-SHA256(ikm = direct key, salt = "ginga-direct-v1", info = purpose)`. Pure JVM.
 * Nothing here is ever logged.
 */
object DirectLinkCrypto {
    const val KEY_SIZE: Int = 32
    const val KEY_ID_SIZE: Int = 8
    const val NONCE_SIZE: Int = 12
    private const val TAG_BITS = 128
    private val SALT = "ginga-direct-v1".encodeToByteArray()

    enum class Purpose(val info: String) {
        /** Tablet → Mac: the network's credentials (GATT read). */
        CREDENTIALS("credentials"),

        /** Mac → tablet: where to connect (GATT write). */
        ADDRESS("address"),
    }

    /** HKDF-SHA256 (RFC 5869), 32 bytes. */
    fun subkey(directKey: ByteArray, purpose: Purpose): ByteArray {
        require(directKey.size == KEY_SIZE) { "a direct key is $KEY_SIZE bytes" }
        val prk = hmac(SALT, directKey)
        return hmac(prk, purpose.info.encodeToByteArray() + byteArrayOf(1))
    }

    /** Encrypts [plaintext] into the §6b blob. */
    fun seal(subkey: ByteArray, keyId: ByteArray, nonce: ByteArray, plaintext: ByteArray): ByteArray {
        require(keyId.size == KEY_ID_SIZE && nonce.size == NONCE_SIZE) { "keyId is 8 bytes, nonce 12" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(subkey, "AES"), GCMParameterSpec(TAG_BITS, nonce))
        cipher.updateAAD(keyId)
        return keyId + nonce + cipher.doFinal(plaintext)
    }

    /** Decrypts a §6b blob sealed for [keyId]; null if it's for another key, malformed or tampered with. */
    fun open(subkey: ByteArray, keyId: ByteArray, sealed: ByteArray): ByteArray? {
        if (sealed.size < KEY_ID_SIZE + NONCE_SIZE + TAG_BITS / 8) return null
        if (!sealed.copyOfRange(0, KEY_ID_SIZE).contentEquals(keyId)) return null
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(subkey, "AES"), GCMParameterSpec(TAG_BITS, sealed, KEY_ID_SIZE, NONCE_SIZE))
            cipher.updateAAD(keyId)
            cipher.doFinal(sealed, KEY_ID_SIZE + NONCE_SIZE, sealed.size - KEY_ID_SIZE - NONCE_SIZE)
        } catch (_: GeneralSecurityException) {
            null
        }
    }

    private fun hmac(key: ByteArray, data: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(key, "HmacSHA256"))
            doFinal(data)
        }
}

/** §6b credentials plaintext (tablet → Mac). Fields in the order they are encoded. */
@Serializable
data class DirectCredentials(val expires: Long, val psk: String, val session: String, val ssid: String) {
    fun encode(): ByteArray = ProtocolJson.encodeToString(serializer(), this).encodeToByteArray()

    override fun toString(): String = "DirectCredentials(ssid=$ssid, expires=$expires, …)"
}

/** §6b address plaintext (Mac → tablet). */
@Serializable
data class DirectAddress(val host: String, val port: Int, val session: String) {
    fun encode(): ByteArray = ProtocolJson.encodeToString(serializer(), this).encodeToByteArray()

    companion object {
        /** Null if [plaintext] isn't a well-formed address. */
        fun decode(plaintext: ByteArray): DirectAddress? = try {
            ProtocolJson.decodeFromString(serializer(), plaintext.decodeToString()).takeIf { it.port in 1..65535 && it.host.isNotEmpty() }
        } catch (_: SerializationException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }
}
