package dev.ginga.receiver.device

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** HELLO `device.name` is a label: cleaned the same way the Mac shows it (PROTOCOL.md §3.1). */
class DeviceNameTest {
    @Test
    fun keepsTheOwnersNameReadable() {
        assertEquals("Galaxy S25 Ultra", cleanDeviceName("Galaxy S25 Ultra"))
        assertEquals("Tablet da Ana", cleanDeviceName("  Tablet\u0007 da\n Ana  "))
    }

    @Test
    fun capsTheLengthAndDropsEmptyNames() {
        assertEquals(64, cleanDeviceName("g".repeat(100))?.length)
        assertNull(cleanDeviceName(" \t "))
    }
}
