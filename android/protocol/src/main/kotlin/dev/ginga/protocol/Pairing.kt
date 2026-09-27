package dev.ginga.protocol

import java.security.MessageDigest
import java.security.SecureRandom

/**
 * A certificate fingerprint (§6): SHA-256 of the certificate's DER encoding. Over Wi‑Fi each side
 * pins the other's fingerprint; neither validates a certificate chain.
 */
class Fingerprint private constructor(private val bytes: ByteArray) {
    init {
        require(bytes.size == SIZE) { "a fingerprint is $SIZE bytes, got ${bytes.size}" }
    }

    /** Lowercase hex, 64 characters. */
    val hex: String get() = bytes.toHex()

    fun toByteArray(): ByteArray = bytes.copyOf()

    override fun equals(other: Any?): Boolean = other is Fingerprint && bytes.contentEquals(other.bytes)

    override fun hashCode(): Int = bytes.contentHashCode()

    override fun toString(): String = hex

    internal fun digestInto(digest: MessageDigest) = digest.update(bytes)

    companion object {
        const val SIZE: Int = 32

        /** The fingerprint of a DER-encoded certificate. */
        fun of(certificateDer: ByteArray): Fingerprint = Fingerprint(sha256().digest(certificateDer))

        /** A fingerprint given as its 32 bytes. */
        fun fromBytes(bytes: ByteArray): Fingerprint = Fingerprint(bytes.copyOf())

        /** Parses 64 hex digits, as [hex] prints them; null if malformed. */
        fun fromHex(hex: String): Fingerprint? {
            if (hex.length != SIZE * 2) return null
            return try {
                Fingerprint(hex.hexToBytes())
            } catch (_: IllegalArgumentException) {
                null
            }
        }

        internal fun sha256(): MessageDigest = MessageDigest.getInstance("SHA-256")
    }
}

/**
 * §6 numeric comparison with a commitment (as in Bluetooth LE Secure Connections). The tablet
 * commits to a fresh nonce before it sees the Mac's and reveals it afterwards, so a man in the
 * middle gets one guess at the 6-digit code per attempt instead of searching offline for
 * certificates whose codes collide. Fingerprints are the raw 32-byte digests.
 */
object PairingCode {
    /** Nonces and commitments are 32 bytes; on the wire, 64 lowercase hex digits. */
    const val NONCE_SIZE: Int = 32

    private val random = SecureRandom()

    /** A fresh nonce for one pairing attempt. */
    fun newNonce(): ByteArray = ByteArray(NONCE_SIZE).also(random::nextBytes)

    /** `SHA-256(tabletFingerprint ‖ macFingerprint ‖ tabletNonce)`. */
    fun commitment(tablet: Fingerprint, mac: Fingerprint, tabletNonce: ByteArray): ByteArray {
        require(tabletNonce.size == NONCE_SIZE) { "a nonce is $NONCE_SIZE bytes" }
        return Fingerprint.sha256().run {
            tablet.digestInto(this)
            mac.digestInto(this)
            update(tabletNonce)
            digest()
        }
    }

    /**
     * The code both screens show: the first 4 bytes of
     * `SHA-256(macFingerprint ‖ tabletFingerprint ‖ macNonce ‖ tabletNonce)` as a big-endian
     * unsigned integer, mod 1 000 000, zero-padded to 6 digits.
     */
    fun code(mac: Fingerprint, tablet: Fingerprint, macNonce: ByteArray, tabletNonce: ByteArray): String {
        require(macNonce.size == NONCE_SIZE && tabletNonce.size == NONCE_SIZE) { "a nonce is $NONCE_SIZE bytes" }
        val digest = Fingerprint.sha256().run {
            mac.digestInto(this)
            tablet.digestInto(this)
            update(macNonce)
            update(tabletNonce)
            digest()
        }
        var value = 0L
        for (i in 0 until 4) value = (value shl 8) or (digest[i].toLong() and 0xFF)
        return (value % 1_000_000).toString().padStart(6, '0')
    }

    /** `053656` → `053 656`, the way the code is shown. */
    fun display(code: String): String = if (code.length == 6) code.substring(0, 3) + " " + code.substring(3) else code

    /** A nonce or commitment as it travels: 64 lowercase hex digits. */
    fun hex(bytes: ByteArray): String = bytes.toHex()

    /** Parses a nonce or commitment field: exactly 64 lowercase hex digits, else null. */
    fun parseHex(text: String?): ByteArray? {
        if (text == null || text.length != NONCE_SIZE * 2) return null
        if (text.any { it !in '0'..'9' && it !in 'a'..'f' }) return null
        return text.hexToBytes()
    }
}
