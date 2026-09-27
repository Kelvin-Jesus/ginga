package dev.ginga.discovery

import java.net.InetAddress
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TxtRecordTest {
    @Test
    fun parsesTheSpecifiedKeys() {
        val txt = TxtRecord.parse(
            mapOf("pv" to "1".encodeToByteArray(), "id" to "a1b2".encodeToByteArray(), "name" to "MacBook Air".encodeToByteArray()),
        )
        assertEquals(TxtRecord(1, "a1b2", "MacBook Air"), txt)
    }

    @Test
    fun toleratesMissingMalformedAndOddlyCasedKeys() {
        val txt = TxtRecord.parse(mapOf("PV" to "x".encodeToByteArray(), "Name" to " Studio ".encodeToByteArray(), "id" to null))
        assertEquals(TxtRecord(null, null, "Studio"), txt)
        assertEquals(TxtRecord(null, null, null), TxtRecord.parse(emptyMap()))
    }

    @Test
    fun parsesWhatTheMacAdvertises() {
        // WiFiService: pv, the first 12 hex digits of the Mac's certificate fingerprint, its name.
        val attributes = mapOf(
            "pv" to "1".encodeToByteArray(),
            "id" to "3f2a91c07d11".encodeToByteArray(),
            "name" to "Kelvin’s MacBook Air".encodeToByteArray(),
        )
        val mac = DiscoveredMac("Kelvin’s MacBook Air", listOf(InetAddress.getByName("192.168.1.20")), 47801, TxtRecord.parse(attributes))
        assertEquals(TxtRecord(1, "3f2a91c07d11", "Kelvin’s MacBook Air"), mac.txt)
        assertEquals("3f2a91c07d11", mac.id)
        assertEquals("Kelvin’s MacBook Air", mac.displayName)
        assertTrue(mac.isCompatible)
    }

    @Test
    fun aMacWithoutIdIsKeyedByItsServiceName() {
        val mac = DiscoveredMac("Studio", emptyList(), 47801, TxtRecord.parse(mapOf("pv" to "1".encodeToByteArray())))
        assertEquals("Studio", mac.id)
        assertNull(mac.preferredAddress)
        assertFalse(DiscoveredMac("Old", emptyList(), 1, TxtRecord(0, null, null)).isCompatible)
    }

    @Test
    fun prefersIpv4Addresses() {
        val v6 = InetAddress.getByName("fe80::1")
        val v4 = InetAddress.getByName("10.0.0.7")
        assertEquals(v4, DiscoveredMac("Mac", listOf(v6, v4), 47801, TxtRecord(1, "id", null)).preferredAddress)
        assertEquals(v6, DiscoveredMac("Mac", listOf(v6), 47801, TxtRecord(1, "id", null)).preferredAddress)
    }

    @Test
    fun displayNameFallsBackToTheServiceName() {
        val loopback = InetAddress.getLoopbackAddress()
        assertEquals("Mac", DiscoveredMac("Mac", listOf(loopback), 47801, TxtRecord(1, "id", null)).displayName)
        assertEquals("Studio", DiscoveredMac("Mac", listOf(loopback), 47801, TxtRecord(1, "id", "Studio")).displayName)
    }
}
