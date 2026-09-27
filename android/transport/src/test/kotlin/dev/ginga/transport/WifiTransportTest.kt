package dev.ginga.transport

import dev.ginga.protocol.Fingerprint
import dev.ginga.protocol.FrameCodec
import dev.ginga.protocol.FrameDecoder
import dev.ginga.protocol.Hello
import dev.ginga.protocol.Message
import dev.ginga.protocol.MessageCodec
import dev.ginga.protocol.Pairing
import dev.ginga.protocol.PairingState
import dev.ginga.protocol.Ping
import dev.ginga.protocol.TransportKind
import dev.ginga.protocol.VersionRange
import java.io.EOFException
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Test

/**
 * [WifiTransport] against a real TLS 1.3 server on loopback standing in for the Mac: mutual
 * authentication with self-signed P-256 certificates, pinning by fingerprint, framing on top.
 */
class WifiTransportTest {
    private val macIdentity = TestIdentity.create("Ginga on Test Mac")
    private val tabletIdentity = TestIdentity.create("Ginga tablet")
    private val servers = mutableListOf<SSLServerSocket>()
    private val server = listen()
    private val transports = mutableListOf<WifiTransport>()

    /** A TLS 1.3 listener like the Mac's: its identity, a client certificate required. */
    private fun listen(): SSLServerSocket = (
        SSLContext.getInstance("TLSv1.3").apply { init(arrayOf(macIdentity.keyManager()), arrayOf(TrustAnyCertificate), null) }
            .serverSocketFactory.createServerSocket(0, 4, InetAddress.getLoopbackAddress()) as SSLServerSocket
        ).apply {
        needClientAuth = true
        enabledProtocols = arrayOf("TLSv1.3")
        servers += this
    }

    @After
    fun tearDown() {
        transports.forEach { it.close() }
        servers.forEach { it.close() }
    }

    private fun transport(
        pins: PinStore = InMemoryPinStore(),
        locator: MacLocator = MacLocator { InetSocketAddress(InetAddress.getLoopbackAddress(), server.localPort) },
        policy: ReconnectPolicy = ReconnectPolicy(initialDelayMs = 10, maxDelayMs = 40),
    ) = WifiTransport(
        WifiTransportConfig(name = "Test Mac", reconnectPolicy = policy),
        locator,
        tabletIdentity.keyManager(),
        PinnedMacVerifier(pins, MAC_ID),
    ).also { transports += it }

    private fun SSLServerSocket.acceptMac(): SSLSocket = (accept() as SSLSocket).apply {
        soTimeout = 5_000
        startHandshake()
    }

    private fun acceptMac(): SSLSocket = (server.accept() as SSLSocket).apply {
        soTimeout = 5_000
        startHandshake()
    }

    private fun WifiTransport.awaitConnected(after: Long = 0): ConnectionState.Connected = runBlocking {
        withTimeout(5_000) { state.first { it is ConnectionState.Connected && it.connectionId > after } as ConnectionState.Connected }
    }

    private fun SSLSocket.readMessage(decoder: FrameDecoder = FrameDecoder()): Message {
        val buffer = ByteArray(4_096)
        while (true) {
            val count = inputStream.read(buffer)
            if (count < 0) throw EOFException()
            val frames = decoder.feed(buffer, 0, count)
            if (frames.isNotEmpty()) return MessageCodec.decode(frames.first())
        }
    }

    private fun SSLSocket.write(message: Message) {
        outputStream.apply {
            write(FrameCodec.encode(MessageCodec.encode(message)))
            flush()
        }
    }

    private val hello = Hello(
        versions = VersionRange(1, 1),
        app = Hello.App("Ginga for Android", "0.1.0"),
        device = Hello.Device("samsung", "SM-X730", "16", "id"),
        display = Hello.Display(2560, 1600, 274, listOf(60.0, 120.0), 0),
        decoders = emptyList(),
        transport = TransportKind.WIFI_TLS,
    )

    @Test(timeout = 30_000)
    fun speaksTheProtocolOverMutualTls13() {
        val transport = transport()
        transport.connect()
        val mac = acceptMac()
        val connected = transport.awaitConnected()

        assertEquals(macIdentity.fingerprint, connected.peer, "the Mac's certificate fingerprint is known before HELLO")
        assertEquals("TLSv1.3", mac.session.protocol)
        val presented = mac.session.peerCertificates.single().encoded
        assertEquals(tabletIdentity.fingerprint, Fingerprint.of(presented), "the tablet presents its own certificate")

        assertTrue(transport.send(hello, connected.connectionId))
        assertEquals(TransportKind.WIFI_TLS, assertIs<Hello>(mac.readMessage()).transport)
        mac.write(Pairing(PairingState.REQUIRED, "Test Mac"))
        val received = runBlocking { withTimeout(5_000) { transport.incoming.first() } }
        assertEquals(Pairing(PairingState.REQUIRED, "Test Mac"), received.message)
        received.release()
    }

    @Test(timeout = 30_000)
    fun aPinnedMacWithItsCertificateIsAccepted() {
        val pins = InMemoryPinStore(listOf(PinnedMac(MAC_ID, "Test Mac", macIdentity.fingerprint)))
        val transport = transport(pins)
        transport.connect()
        val mac = acceptMac()
        val connected = transport.awaitConnected()
        assertTrue(transport.send(Ping(1, 0), connected.connectionId))
        assertEquals(1, assertIs<Ping>(mac.readMessage()).id)
    }

    @Test(timeout = 30_000)
    fun aPinnedMacWithAnotherCertificateIsRefusedBeforeHello() {
        val impostor = TestIdentity.create("Someone else")
        val pins = InMemoryPinStore(listOf(PinnedMac(MAC_ID, "Test Mac", impostor.fingerprint)))
        val transport = transport(pins)
        transport.connect()
        val mac = server.accept() as SSLSocket
        mac.soTimeout = 5_000
        val firstByte = CompletableFuture.supplyAsync {
            try {
                mac.startHandshake()
                mac.inputStream.read()
            } catch (_: IOException) {
                -1 // reset by the tablet's close: fine too
            }
        }

        val closed = runBlocking { withTimeout(5_000) { transport.state.first { it is ConnectionState.Closed } } }
        assertEquals(ConnectionState.Closed(PinnedMacVerifier.IDENTITY_CHANGED), closed)
        assertEquals(-1, firstByte.get(5, TimeUnit.SECONDS), "not a single byte of the protocol reaches an unexpected Mac")
    }

    @Test(timeout = 30_000)
    fun reconnectsAndVerifiesEachNewLink() {
        val pins = InMemoryPinStore(listOf(PinnedMac(MAC_ID, "Test Mac", macIdentity.fingerprint)))
        val transport = transport(pins)
        transport.connect()
        acceptMac().close() // the Mac drops the first connection
        val mac = acceptMac()
        val second = transport.awaitConnected(after = 1)
        assertEquals(macIdentity.fingerprint, second.peer)
        assertTrue(transport.send(Ping(2, 0), second.connectionId))
        assertEquals(2, assertIs<Ping>(mac.readMessage()).id)
    }

    @Test(timeout = 30_000)
    fun findsTheMacAgainBeforeEveryConnection() {
        // Ginga restarted on the Mac: its listener moved to another port.
        val restarted = listen()
        val ports = ArrayDeque(listOf(server.localPort, restarted.localPort))
        val lookups = AtomicInteger()
        val locator = MacLocator {
            lookups.incrementAndGet()
            synchronized(ports) { (if (ports.size > 1) ports.removeFirst() else ports.first()) }
                .let { InetSocketAddress(InetAddress.getLoopbackAddress(), it) }
        }
        val transport = transport(locator = locator)
        transport.connect()
        server.acceptMac().close() // the old instance goes away
        val mac = restarted.acceptMac()
        val connected = transport.awaitConnected(after = 1)
        assertTrue(transport.send(Ping(3, 0), connected.connectionId))
        assertEquals(3, assertIs<Ping>(mac.readMessage()).id)
        assertEquals(2, lookups.get())
    }

    @Test(timeout = 30_000)
    fun aMacThatIsNotOnTheNetworkIsRetried() {
        val found = AtomicInteger()
        val transport = transport(
            locator = MacLocator {
                if (found.incrementAndGet() < 3) null else InetSocketAddress(InetAddress.getLoopbackAddress(), server.localPort)
            },
            policy = ReconnectPolicy(initialDelayMs = 200, maxDelayMs = 400), // long enough to observe
        )
        transport.connect()
        val retry = runBlocking { withTimeout(5_000) { transport.state.first { it is ConnectionState.WaitingToRetry } } }
        assertEquals("Test Mac isn't on the network", (retry as ConnectionState.WaitingToRetry).lastError)
        acceptMac()
        transport.awaitConnected()
        assertEquals(3, found.get())
    }

    private companion object {
        const val MAC_ID = "3f2a91c07d11"
    }
}
