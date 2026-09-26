package dev.tab2mac.transport

/**
 * The strings the Mac sends with AOA SEND_STRING before START (indices 0–5). Android matches the
 * app's `res/xml/accessory_filter.xml` against [MANUFACTURER] and [MODEL]; a unit test keeps the
 * two in step. [DESCRIPTION] is the name Android shows in its prompts.
 */
object AccessoryIdentity {
    const val MANUFACTURER: String = "Tab2Mac"
    const val MODEL: String = "Tab2Mac Receiver"
    const val DESCRIPTION: String = "Second display for your Mac"
    const val VERSION: String = "1"

    /** Empty: Android offers no download link when the app is missing. */
    const val URI: String = ""
    const val SERIAL: String = "1"

    /** Whether [accessory] is the Mac, by the fields the accessory filter matches (exactly, like Android). */
    fun matches(accessory: AccessoryInfo): Boolean =
        accessory.manufacturer == MANUFACTURER && accessory.model == MODEL
}

/**
 * The identifying strings of an attached USB accessory, as plain data. The serial is left out on
 * purpose: `UsbAccessory.getSerial()` throws until the user has granted access.
 */
data class AccessoryInfo(val manufacturer: String?, val model: String?, val version: String? = null)

/** Which transport a new connection uses. */
sealed interface TransportChoice<out A> {
    /** TCP to 127.0.0.1:47800, tunnelled to the Mac by `adb reverse` (needs USB debugging). */
    data object AdbTcp : TransportChoice<Nothing>

    /** The Mac is attached as a USB accessory and the app may open it. */
    data class Accessory<A>(val accessory: A) : TransportChoice<A>

    /** The Mac is attached as a USB accessory, but the user must allow access first. */
    data class AccessoryNeedsPermission<A>(val accessory: A) : TransportChoice<A>
}

/** Picks the transport: direct USB (AOA) whenever the Mac's accessory is attached, ADB otherwise. */
object TransportSelector {
    /**
     * [attached] is `UsbManager.getAccessoryList()` (at most one entry in practice); [info] and
     * [hasPermission] read an entry. Other accessories (a dock, a car) are ignored.
     */
    fun <A> choose(attached: List<A>, info: (A) -> AccessoryInfo, hasPermission: (A) -> Boolean): TransportChoice<A> {
        val mac = attached.firstOrNull { AccessoryIdentity.matches(info(it)) } ?: return TransportChoice.AdbTcp
        return if (hasPermission(mac)) TransportChoice.Accessory(mac) else TransportChoice.AccessoryNeedsPermission(mac)
    }
}
