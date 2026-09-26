package dev.tab2mac.transport

import dev.tab2mac.protocol.Fingerprint
import java.io.ByteArrayOutputStream
import java.math.BigInteger
import java.net.Socket
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLEngine
import javax.net.ssl.X509ExtendedTrustManager
import javax.net.ssl.X509KeyManager

/**
 * A P-256 key with a self-signed X.509 v3 certificate (ECDSA-SHA256, no extensions) — the kind of
 * identity both the Mac and the tablet use (PROTOCOL.md §6) — for JVM tests.
 */
internal class TestIdentity private constructor(private val keyPair: KeyPair, val certificate: X509Certificate) {
    val fingerprint: Fingerprint get() = Fingerprint.of(certificate.encoded)

    /** A JSSE key manager presenting this identity. */
    fun keyManager(): X509KeyManager {
        val password = "test".toCharArray()
        val store = KeyStore.getInstance("PKCS12").apply {
            load(null, null)
            setKeyEntry("identity", keyPair.private, password, arrayOf(certificate))
        }
        val factory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm()).apply { init(store, password) }
        return factory.keyManagers.filterIsInstance<X509KeyManager>().first()
    }

    companion object {
        fun create(commonName: String): TestIdentity {
            val keyPair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
            val der = SelfSignedCertificate.der(keyPair, commonName)
            val certificate = CertificateFactory.getInstance("X.509").generateCertificate(der.inputStream()) as X509Certificate
            return TestIdentity(keyPair, certificate)
        }
    }
}

/** Minimal DER for a self-signed certificate, like the Mac's `SelfSignedCertificate`. */
internal object SelfSignedCertificate {
    private const val DAY_MS = 86_400_000L

    fun der(keyPair: KeyPair, commonName: String): ByteArray {
        val ecdsaWithSha256 = sequence(objectId(1, 2, 840, 10045, 4, 3, 2))
        val name = sequence(set(sequence(objectId(2, 5, 4, 3), tlv(0x0C, commonName.encodeToByteArray()))))
        val now = System.currentTimeMillis()
        val tbs = sequence(
            tlv(0xA0, integer(BigInteger.valueOf(2))), // [0] EXPLICIT version: v3
            integer(BigInteger.valueOf(now)),
            ecdsaWithSha256,
            name,
            sequence(utcTime(now - DAY_MS), utcTime(now + 365 * DAY_MS)),
            name,
            keyPair.public.encoded, // SubjectPublicKeyInfo
        )
        val signature = Signature.getInstance("SHA256withECDSA").run {
            initSign(keyPair.private)
            update(tbs)
            sign()
        }
        return sequence(tbs, ecdsaWithSha256, tlv(0x03, byteArrayOf(0) + signature))
    }

    private fun sequence(vararg parts: ByteArray) = tlv(0x30, parts.reduce(ByteArray::plus))

    private fun set(vararg parts: ByteArray) = tlv(0x31, parts.reduce(ByteArray::plus))

    private fun integer(value: BigInteger) = tlv(0x02, value.toByteArray())

    private fun utcTime(millis: Long): ByteArray {
        val format = SimpleDateFormat("yyMMddHHmmss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
        return tlv(0x17, format.format(Date(millis)).encodeToByteArray())
    }

    private fun objectId(vararg arcs: Int): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(arcs[0] * 40 + arcs[1])
        for (arc in arcs.drop(2)) {
            val groups = generateSequence(arc) { it ushr 7 }.takeWhile { it > 0 }.map { it and 0x7F }.toList().ifEmpty { listOf(0) }.reversed()
            groups.forEachIndexed { i, group -> out.write(if (i < groups.size - 1) group or 0x80 else group) }
        }
        return tlv(0x06, out.toByteArray())
    }

    private fun tlv(tag: Int, content: ByteArray): ByteArray {
        val length = content.size
        val header = when {
            length < 0x80 -> byteArrayOf(tag.toByte(), length.toByte())
            length < 0x100 -> byteArrayOf(tag.toByte(), 0x81.toByte(), length.toByte())
            else -> byteArrayOf(tag.toByte(), 0x82.toByte(), (length ushr 8).toByte(), length.toByte())
        }
        return header + content
    }
}

/** A test Mac's trust: any tablet certificate passes the handshake (the session pins it). */
internal object TrustAnyCertificate : X509ExtendedTrustManager() {
    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit

    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) = Unit

    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) = Unit

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) = Unit

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) = Unit

    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
}
