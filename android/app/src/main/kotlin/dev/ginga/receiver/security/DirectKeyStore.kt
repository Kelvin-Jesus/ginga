package dev.ginga.receiver.security

import android.content.Context
import dev.ginga.protocol.DirectLink
import dev.ginga.protocol.hexToBytes
import dev.ginga.receiver.AppLog
import dev.ginga.receiver.direct.DirectKey
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * The no-router keys Macs handed over (§6b DIRECT_LINK), one per Mac (by keyId), in a
 * [SealedFile]. The most recent one is used for a direct connection. Keys are never logged.
 */
class DirectKeyStore(context: Context) {
    private val file = SealedFile(context, "direct-keys", "ginga-direct-keys")
    private val keys: MutableList<DirectKey> by lazy { DirectKeyCodec.decode(file.read()).toMutableList() }

    /** The key received most recently, or null before any Mac sent one. */
    fun latest(): DirectKey? = synchronized(this) { keys.lastOrNull() }

    /** Keeps [message] for [macName]; false if malformed. */
    fun put(message: DirectLink, macName: String): Boolean {
        val key = DirectKeyCodec.parse(message, macName) ?: return false
        synchronized(this) {
            keys.removeAll { it.keyIdHex == key.keyIdHex }
            keys += key
            file.write(DirectKeyCodec.encode(keys))
        }
        AppLog.i("direct.key-stored", "keyId" to key.keyIdHex, "mac" to macName)
        return true
    }
}

/** DIRECT_LINK validation and the store's JSON. Pure. */
object DirectKeyCodec {
    private val HEX = Regex("[0-9a-f]+")

    /** Null unless keyId is 16 and key 64 lowercase hex digits. */
    fun parse(message: DirectLink, macName: String): DirectKey? {
        if (message.keyId.length != 16 || message.key.length != 64) return null
        if (!HEX.matches(message.keyId) || !HEX.matches(message.key)) return null
        return DirectKey(message.keyId.hexToBytes(), message.key.hexToBytes(), macName)
    }

    fun encode(keys: List<DirectKey>): String = buildJsonArray {
        for (key in keys) {
            add(
                buildJsonObject {
                    put("keyId", key.keyIdHex)
                    put("key", key.key.joinToString("") { "%02x".format(it) })
                    put("mac", key.macName)
                },
            )
        }
    }.toString()

    fun decode(text: String?): List<DirectKey> {
        val array = try {
            text?.let { Json.parseToJsonElement(it) as? JsonArray }
        } catch (_: IllegalArgumentException) {
            null
        } ?: return emptyList()
        return array.mapNotNull { element ->
            val entry = element as? JsonObject ?: return@mapNotNull null
            fun text(name: String) = (entry[name] as? JsonPrimitive)?.takeIf { it.isString }?.content
            parse(DirectLink(text("keyId") ?: return@mapNotNull null, text("key") ?: return@mapNotNull null), text("mac") ?: "Mac")
        }
    }
}
