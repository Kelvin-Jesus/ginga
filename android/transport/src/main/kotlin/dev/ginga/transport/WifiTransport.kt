package dev.ginga.transport

import dev.ginga.protocol.Fingerprint
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.security.GeneralSecurityException
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509ExtendedTrustManager
import javax.net.ssl.X509KeyManager

/**
 * Where the Mac is right now. Asked before every connection attempt, reconnections included: the
 * Mac's Wi‑Fi port is chosen by the system each time Ginga starts, so an address found earlier
 * goes stale (PROTOCOL.md §6). May block briefly (a Bonjour resolve).
 */
fun interface MacLocator {
    /** The Mac's current address, or null when it isn't on the network. */
    fun locate(): InetSocketAddress?
}

/** How a [WifiTransport] connects. */
data class WifiTransportConfig(
    /** The Mac's name for logs and the endpoint (its Bonjour service name). */
    val name: String,
    val autoReconnect: Boolean = true,
    val reconnectPolicy: ReconnectPolicy = ReconnectPolicy(),
    val connectTimeoutMs: Int = 3_000,
    /** How long the TLS handshake may take (it includes the Mac's key exchange). */
    val handshakeTimeoutMs: Int = 5_000,
    val incomingCapacity: Int = 8,
    val readChunkBytes: Int = 256 * 1024,
    val closeDrainTimeoutMs: Long = 300,
    /** Nothing received for this long while streaming, or a write blocked this long: reconnect ([LinkOptions.silenceTimeoutMs]). */
    val silenceTimeoutMs: Long? = 5_000,
) {
    internal fun linkOptions() = LinkOptions(
        autoReconnect, reconnectPolicy, incomingCapacity, readChunkBytes, closeDrainTimeoutMs, silenceTimeoutMs = silenceTimeoutMs,
    )
}

/**
 * [Transport] over Wi‑Fi (M7, PROTOCOL.md §5–6): TLS 1.3 over TCP with `TCP_NODELAY`, then the
 * same framing, reader and [SendQueue] writer as every other link ([LinkTransport]).
 *
 * Trust is pinning, not a certificate chain: the handshake accepts any server certificate, and
 * [verifier] judges the Mac by its certificate fingerprint before anything is sent — a refusal
 * (for example a pinned Mac presenting another certificate) ends the transport without HELLO.
 * The tablet presents [identity] as its client certificate, which the Mac requires.
 * Connection drops are retried with the usual backoff; before each attempt [locator] finds the
 * Mac again, and each new link is verified again.
 */
class WifiTransport(
    config: WifiTransportConfig,
    locator: MacLocator,
    identity: X509KeyManager,
    verifier: MacVerifier,
    nanoClock: () -> Long = System::nanoTime,
) : LinkTransport(
    endpoint = "tls://${config.name}",
    opener = TlsOpener(config, locator, identity, verifier),
    options = config.linkOptions(),
    nanoClock = nanoClock,
    threadPrefix = "ginga-tls",
)

/** Opens TLS 1.3 links to the Mac and fingerprints its certificate. */
internal class TlsOpener(
    private val config: WifiTransportConfig,
    private val locator: MacLocator,
    identity: X509KeyManager,
    private val verifier: MacVerifier,
) : LinkOpener {
    private val context: SSLContext = SSLContext.getInstance(TLS_13).apply {
        init(arrayOf(identity), arrayOf(AcceptAnyCertificate), null)
    }

    override fun open(): LinkAttempt {
        val address = locator.locate() ?: return LinkAttempt.Failed("${config.name} isn't on the network")
        val socket = Socket()
        val tls = try {
            socket.tcpNoDelay = true
            socket.connect(address, config.connectTimeoutMs)
            val tls = context.socketFactory.createSocket(socket, address.hostString, address.port, true) as SSLSocket
            tls.useClientMode = true
            tls.enabledProtocols = arrayOf(TLS_13)
            tls.soTimeout = config.handshakeTimeoutMs
            tls.startHandshake()
            tls.soTimeout = 0 // from now on reads block until data arrives: no polling
            tls
        } catch (e: IOException) {
            socket.closeQuietly()
            return LinkAttempt.Failed(e.message ?: e.javaClass.simpleName)
        }
        val fingerprint = try {
            (tls.session.peerCertificates.firstOrNull() as? X509Certificate)?.let { Fingerprint.of(it.encoded) }
        } catch (_: IOException) {
            null // SSLPeerUnverifiedException
        } catch (_: GeneralSecurityException) {
            null // CertificateEncodingException
        }
        if (fingerprint == null) {
            tls.closeQuietly()
            return LinkAttempt.Failed("the Mac presented no usable certificate")
        }
        val refusal = verifier.refusal(fingerprint)
        if (refusal != null) {
            TransportLog.w("tls.refused", "mac" to fingerprint.hex, "reason" to refusal)
            tls.closeQuietly()
            return LinkAttempt.Gone(refusal)
        }
        TransportLog.i(
            "tls.connected", "address" to address, "protocol" to tls.session.protocol,
            "cipher" to tls.session.cipherSuite, "mac" to fingerprint.hex,
        )
        return LinkAttempt.Opened(TlsLink(tls, fingerprint))
    }

    private companion object {
        const val TLS_13 = "TLSv1.3"
    }
}

/** One TLS connection. Closing it (from any thread) wakes a blocked read. */
private class TlsLink(private val socket: SSLSocket, override val peerFingerprint: Fingerprint) : ByteLink {
    override val input: InputStream = socket.inputStream
    override val output: OutputStream = socket.outputStream

    // No half-close: not every TLS socket supports it. The Mac closes after our GOODBYE, and
    // close() sends close_notify.

    override fun close() {
        socket.close()
    }
}

/**
 * Accepts any server certificate during the handshake: the Mac's certificate is self-signed, and
 * it is pinned by fingerprint right after ([MacVerifier]), before a single byte is sent.
 */
private object AcceptAnyCertificate : X509ExtendedTrustManager() {
    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit

    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) = Unit

    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) = Unit

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) = Unit

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) = Unit

    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
}

private fun Socket.closeQuietly() {
    try {
        close()
    } catch (_: IOException) {
    }
}
