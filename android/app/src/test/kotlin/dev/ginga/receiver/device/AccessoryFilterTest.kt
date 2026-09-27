package dev.ginga.receiver.device

import dev.ginga.transport.AccessoryIdentity
import dev.ginga.transport.AccessoryInfo
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.w3c.dom.Document
import org.w3c.dom.Element
import org.w3c.dom.NodeList

/**
 * Android opens the app for the Mac only if `res/xml/accessory_filter.xml` matches the strings the
 * Mac sends ([AccessoryIdentity]) and the manifest routes `USB_ACCESSORY_ATTACHED` with it.
 */
class AccessoryFilterTest {
    private val mainDir = File(System.getProperty("ginga.appMainDir") ?: "src/main")

    private fun parse(path: String): Document = DocumentBuilderFactory.newInstance()
        .apply { isNamespaceAware = true }
        .newDocumentBuilder()
        .parse(File(mainDir, path))

    private fun NodeList.elements(): List<Element> = (0 until length).map { item(it) as Element }

    private fun Element.android(name: String): String = getAttributeNS(ANDROID_NS, name)

    @Test
    fun filterMatchesTheAccessoryTheMacAnnounces() {
        val filter = parse("res/xml/accessory_filter.xml").getElementsByTagName("usb-accessory").elements().single()
        val info = AccessoryInfo(filter.getAttribute("manufacturer"), filter.getAttribute("model"))
        assertEquals(AccessoryIdentity.MANUFACTURER, info.manufacturer)
        assertEquals(AccessoryIdentity.MODEL, info.model)
        assertTrue(AccessoryIdentity.matches(info))
        assertEquals("", filter.getAttribute("version"), "no version pin: a newer Mac still opens the app")
    }

    @Test
    fun manifestRoutesTheAttachIntentThroughTheFilter() {
        val manifest = parse("AndroidManifest.xml")
        val activity = manifest.getElementsByTagName("activity").elements().single { it.android("name") == ".ui.AccessoryActivity" }
        assertEquals("true", activity.android("exported"), "the system starts it")
        assertEquals(
            listOf(ATTACHED),
            activity.getElementsByTagName("action").elements().map { it.android("name") },
        )
        val meta = activity.getElementsByTagName("meta-data").elements().single()
        assertEquals(ATTACHED, meta.android("name"))
        assertEquals("@xml/accessory_filter", meta.android("resource"))

        val feature = manifest.getElementsByTagName("uses-feature").elements().single { it.android("name") == "android.hardware.usb.accessory" }
        assertEquals("false", feature.android("required"), "without accessory support the app still works over ADB")
    }

    @Test
    fun onlyTheAdbShellCanDeliverTheLoopbackToken() {
        val receiver = parse("AndroidManifest.xml").getElementsByTagName("receiver").elements()
            .single { it.android("name") == ".adb.LoopbackTokenReceiver" }
        assertEquals("true", receiver.android("exported"))
        assertEquals("android.permission.DUMP", receiver.android("permission"), "held only by the adb shell")
        assertEquals(
            listOf("dev.ginga.action.LOOPBACK_TOKEN"),
            receiver.getElementsByTagName("action").elements().map { it.android("name") },
        )
    }

    private companion object {
        const val ANDROID_NS = "http://schemas.android.com/apk/res/android"
        const val ATTACHED = "android.hardware.usb.action.USB_ACCESSORY_ATTACHED"
    }
}
