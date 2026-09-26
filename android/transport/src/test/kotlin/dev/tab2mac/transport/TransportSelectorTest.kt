package dev.tab2mac.transport

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TransportSelectorTest {
    private val mac = AccessoryInfo(AccessoryIdentity.MANUFACTURER, AccessoryIdentity.MODEL, AccessoryIdentity.VERSION)
    private val dock = AccessoryInfo("Acme", "USB-C Dock", "2")

    private fun choose(attached: List<AccessoryInfo>, granted: Set<AccessoryInfo> = emptySet()) =
        TransportSelector.choose(attached, { it }, { it in granted })

    @Test
    fun usesAdbWhenNoAccessoryIsAttached() {
        assertEquals(TransportChoice.AdbTcp, choose(emptyList()))
    }

    @Test
    fun usesTheAccessoryWhenTheMacIsAttachedAndAccessAllowed() {
        assertEquals(TransportChoice.Accessory(mac), choose(listOf(mac), granted = setOf(mac)))
    }

    @Test
    fun asksForAccessFirstWhenNotAllowedYet() {
        assertEquals(TransportChoice.AccessoryNeedsPermission(mac), choose(listOf(mac)))
    }

    @Test
    fun ignoresOtherAccessories() {
        assertEquals(TransportChoice.AdbTcp, choose(listOf(dock), granted = setOf(dock)))
        assertEquals(TransportChoice.Accessory(mac), choose(listOf(dock, mac), granted = setOf(dock, mac)))
    }

    @Test
    fun matchesManufacturerAndModelExactlyLikeAndroid() {
        assertTrue(AccessoryIdentity.matches(mac))
        assertTrue(AccessoryIdentity.matches(mac.copy(version = "2")), "the filter doesn't pin a version")
        assertFalse(AccessoryIdentity.matches(mac.copy(model = "Tab2Mac Display")), "the pre-M6 model string")
        assertFalse(AccessoryIdentity.matches(mac.copy(manufacturer = "tab2mac")))
        assertFalse(AccessoryIdentity.matches(AccessoryInfo(null, null)))
    }

    @Test
    fun identityIsWhatTheMacSends() {
        assertEquals(
            listOf("Tab2Mac", "Tab2Mac Receiver", "Second display for your Mac", "1", "", "1"),
            with(AccessoryIdentity) { listOf(MANUFACTURER, MODEL, DESCRIPTION, VERSION, URI, SERIAL) },
        )
    }
}
