package dev.ginga.transport

import dev.ginga.protocol.Fingerprint
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put

/**
 * A Mac this tablet paired with over Wi‑Fi (PROTOCOL.md §6): its Bonjour `id`, its name, and the
 * fingerprint of the certificate it presented while pairing.
 */
data class PinnedMac(val id: String, val name: String, val fingerprint: Fingerprint)

/** Where pinned Macs are kept, by Mac `id`. Implementations are thread-safe. */
interface PinStore {
    fun get(id: String): PinnedMac?

    fun all(): List<PinnedMac>

    /** Adds or replaces the pin for [PinnedMac.id]. */
    fun put(mac: PinnedMac)

    fun remove(id: String)
}

/** A [PinStore] in memory (tests, and the cache in front of a file). */
open class InMemoryPinStore(initial: Collection<PinnedMac> = emptyList()) : PinStore {
    private val pins = LinkedHashMap<String, PinnedMac>().apply { initial.forEach { put(it.id, it) } }

    override fun get(id: String): PinnedMac? = synchronized(pins) { pins[id] }

    override fun all(): List<PinnedMac> = synchronized(pins) { pins.values.toList() }

    override fun put(mac: PinnedMac) {
        synchronized(pins) { pins[mac.id] = mac }
    }

    override fun remove(id: String) {
        synchronized(pins) { pins.remove(id) }
    }
}

/** Pins as JSON: `[{"id":"…","name":"…","fingerprint":"<64 hex digits>"}]`. */
object PinCodec {
    fun encode(pins: Collection<PinnedMac>): String = buildJsonArray {
        for (pin in pins) {
            add(
                buildJsonObject {
                    put("id", pin.id)
                    put("name", pin.name)
                    put("fingerprint", pin.fingerprint.hex)
                },
            )
        }
    }.toString()

    /** Reads [encode]'s output; malformed entries are skipped, malformed text yields nothing. */
    fun decode(text: String): List<PinnedMac> {
        val array = try {
            Json.parseToJsonElement(text) as? JsonArray
        } catch (_: IllegalArgumentException) {
            null
        } ?: return emptyList()
        return array.mapNotNull { element ->
            val entry = element as? JsonObject ?: return@mapNotNull null
            fun text(key: String): String? = (entry[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
            val id = text("id") ?: return@mapNotNull null
            val fingerprint = text("fingerprint")?.let(Fingerprint::fromHex) ?: return@mapNotNull null
            PinnedMac(id, text("name") ?: id, fingerprint)
        }
    }
}

/** The verdict on the Mac at the other end of a TLS handshake, before anything is sent. */
fun interface MacVerifier {
    /** Null accepts [mac] (its certificate fingerprint); a reason refuses it and closes the link. */
    fun refusal(mac: Fingerprint): String?
}

/**
 * §6 pinning: a Mac pinned under [macId] must present exactly the pinned certificate — anything
 * else is refused with [IDENTITY_CHANGED], before HELLO. A Mac without a pin is accepted; the
 * session then pairs with it (PAIRING) and pins it on `paired`.
 */
class PinnedMacVerifier(private val pins: PinStore, private val macId: String) : MacVerifier {
    override fun refusal(mac: Fingerprint): String? {
        val pinned = pins.get(macId) ?: return null
        return if (pinned.fingerprint == mac) null else IDENTITY_CHANGED
    }

    companion object {
        /** The [ConnectionState.Closed] reason when a pinned Mac presents another certificate. */
        const val IDENTITY_CHANGED: String = "this Mac's identity changed; pair again"
    }
}
