package dev.tab2mac.receiver.direct

import dev.tab2mac.protocol.DirectAddress
import dev.tab2mac.protocol.DirectCredentials
import dev.tab2mac.protocol.DirectLinkCrypto
import dev.tab2mac.protocol.ProtocolJson
import dev.tab2mac.protocol.hexToBytes
import java.util.concurrent.TimeUnit
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

class DirectLinkFlowTest {
    private val key = DirectKey("0102030405060708".hexToBytes(), ByteArray(32) { 0x55 }, "MacBook Air")
    private var nowMs = 1_790_000_000_000L
    private val random = Random(7)
    private val states = mutableListOf<DirectState>()
    private val connections = mutableListOf<Pair<String, Int>>()

    private class FakeNetwork(override val kind: String) : DirectNetwork {
        var started: Triple<String, String, Any>? = null
        var stops = 0
        lateinit var up: (String, String) -> Unit
        lateinit var failed: (String) -> Unit
        lateinit var lost: (String) -> Unit

        override fun start(name: String, passphrase: String, onUp: (String, String) -> Unit, onFailed: (String) -> Unit, onLost: (String) -> Unit) {
            started = Triple(name, passphrase, Unit)
            up = onUp
            failed = onFailed
            lost = onLost
        }

        override fun stop() {
            stops++
        }

        fun comeUp() = up(started!!.first, started!!.second)
    }

    private class FakeServer : CredentialServer {
        var running = false
        var stops = 0
        lateinit var read: () -> ByteArray
        lateinit var write: (ByteArray) -> Boolean
        lateinit var fail: (String) -> Unit

        override fun start(credentials: () -> ByteArray, onAddress: (ByteArray) -> Boolean, onFailed: (String) -> Unit) {
            running = true
            read = credentials
            write = onAddress
            fail = onFailed
        }

        override fun stop() {
            running = false
            stops++
        }
    }

    private val direct = FakeNetwork("Wi‑Fi Direct")
    private val hotspot = FakeNetwork("hotspot")
    private val server = FakeServer()

    private fun flow() = DirectLinkFlow(
        key, listOf(direct, hotspot), server,
        connect = { host, port -> connections += host to port },
        onState = { states += it },
        now = { nowMs },
        random = { size -> random.nextBytes(size) },
    )

    /** What the Mac does: read and decrypt the credentials. */
    private fun macReads(): DirectCredentials {
        val plaintext = DirectLinkCrypto.open(DirectLinkCrypto.subkey(key.key, DirectLinkCrypto.Purpose.CREDENTIALS), key.keyId, server.read())!!
        return ProtocolJson.decodeFromString(DirectCredentials.serializer(), plaintext.decodeToString())
    }

    /** What the Mac writes back. */
    private fun address(session: String, host: String = "192.168.49.23", port: Int = 55471) = DirectLinkCrypto.seal(
        DirectLinkCrypto.subkey(key.key, DirectLinkCrypto.Purpose.ADDRESS), key.keyId, random.nextBytes(12), DirectAddress(host, port, session).encode(),
    )

    private fun assertTornDown() {
        assertIs<DirectState.Ended>(states.last())
        assertFalse(server.running)
        assertTrue(direct.stops + hotspot.stops >= 1, "the network is stopped")
    }

    @Test
    fun theWholeWayFromNetworkToSessionAndBack() {
        val flow = flow()
        flow.start()
        assertEquals(DirectState.CreatingNetwork("Wi‑Fi Direct"), flow.state)
        val (name, passphrase, _) = direct.started!!
        assertEquals("DIRECT-T2-0102", name)
        assertTrue(passphrase.length >= 16, passphrase)

        direct.comeUp()
        assertEquals(DirectState.WaitingForMac("DIRECT-T2-0102", "Wi‑Fi Direct"), flow.state)
        assertTrue(server.running)
        val credentials = macReads()
        assertEquals("DIRECT-T2-0102", credentials.ssid)
        assertEquals(passphrase, credentials.psk)
        assertEquals(TimeUnit.MILLISECONDS.toSeconds(nowMs) + 300, credentials.expires, "valid for 5 minutes")
        assertEquals(32, credentials.session.length)

        assertTrue(server.write(address(credentials.session)))
        assertEquals(DirectState.Connecting("192.168.49.23", 55471), flow.state)
        assertEquals(listOf("192.168.49.23" to 55471), connections)

        flow.onConnected()
        assertEquals(DirectState.Connected, flow.state)
        assertFalse(server.running, "no Bluetooth LE once connected")
        assertEquals(0, direct.stops, "the network stays for the session")

        flow.onSessionEnded("closed: user")
        assertEquals(DirectState.Ended("closed: user"), flow.state)
        assertEquals(1, direct.stops)
        assertEquals(0, hotspot.stops)
    }

    @Test
    fun eachReadIsAFreshBlob() {
        val flow = flow()
        flow.start()
        direct.comeUp()
        assertFalse(server.read().contentEquals(server.read()), "fresh nonce")
    }

    @Test
    fun fallsBackToTheHotspotWhenWifiDirectFails() {
        val flow = flow()
        flow.start()
        direct.failed("busy")
        assertEquals(DirectState.CreatingNetwork("hotspot"), flow.state)
        hotspot.up("AndroidShare_1234", "system-chosen-psk")
        assertEquals(DirectState.WaitingForMac("AndroidShare_1234", "hotspot"), flow.state)
        assertEquals("system-chosen-psk", macReads().psk)
    }

    @Test
    fun noNetworkAtAllEndsAndTearsDown() {
        val flow = flow()
        flow.start()
        direct.failed("busy")
        hotspot.failed("tethering off")
        assertEquals(DirectState.Ended("no network could be created: hotspot: tethering off"), flow.state)
        assertFalse(server.running)
        assertTrue(connections.isEmpty())
    }

    @Test
    fun aBluetoothFailureTearsTheNetworkDown() {
        val flow = flow()
        flow.start()
        direct.comeUp()
        server.fail("advertising failed: 3")
        assertEquals(DirectState.Ended("Bluetooth LE: advertising failed: 3"), flow.state)
        assertTornDown()
    }

    @Test
    fun losingTheNetworkEndsEverything() {
        val flow = flow()
        flow.start()
        direct.comeUp()
        direct.lost("group removed")
        assertTornDown()
    }

    @Test
    fun cancelTearsDownInEveryState() {
        for (step in 0..3) {
            val server = FakeServer()
            val network = FakeNetwork("Wi‑Fi Direct")
            val flow = DirectLinkFlow(key, listOf(network), server, { _, _ -> }, {}, { nowMs }, { random.nextBytes(it) })
            flow.start()
            if (step >= 1) network.comeUp()
            val session = if (step >= 1) {
                val plaintext = DirectLinkCrypto.open(DirectLinkCrypto.subkey(key.key, DirectLinkCrypto.Purpose.CREDENTIALS), key.keyId, server.read())!!
                ProtocolJson.decodeFromString(DirectCredentials.serializer(), plaintext.decodeToString()).session
            } else {
                ""
            }
            if (step >= 2) server.write(address(session))
            if (step >= 3) flow.onConnected()
            flow.cancel()
            assertEquals(DirectState.Ended("cancelled"), flow.state, "step $step")
            assertFalse(server.running)
            assertEquals(1, network.stops)
            flow.cancel() // idempotent
            assertEquals(1, network.stops)
        }
    }

    @Test
    fun refusesReplaysForeignSessionsAndTampering() {
        val flow = flow()
        flow.start()
        direct.comeUp()
        val session = macReads().session
        assertFalse(server.write(address("ffeeddccbbaa99887766554433221100")), "an earlier link's address")
        assertFalse(server.write(address(session).also { it[25] = (it[25] + 1).toByte() }), "tampered")
        val otherKey = DirectLinkCrypto.subkey(ByteArray(32) { 0x66 }, DirectLinkCrypto.Purpose.ADDRESS)
        assertFalse(server.write(DirectLinkCrypto.seal(otherKey, key.keyId, ByteArray(12), DirectAddress("10.0.0.1", 1, session).encode())), "another key")
        assertTrue(connections.isEmpty())
        assertTrue(server.write(address(session)))
        assertFalse(server.write(address(session, host = "10.9.9.9")), "only one address per link")
        assertEquals(listOf("192.168.49.23" to 55471), connections)
    }

    @Test
    fun refusesAnAddressAfterTheCredentialsExpired() {
        val flow = flow()
        flow.start()
        direct.comeUp()
        assertFalse(server.write(address("00".repeat(16))), "nothing offered yet")
        val session = macReads().session
        nowMs += TimeUnit.MINUTES.toMillis(5) + 1
        assertFalse(server.write(address(session)), "expired")
        macReads() // a fresh read renews the offer
        assertTrue(server.write(address(session)))
    }
}
