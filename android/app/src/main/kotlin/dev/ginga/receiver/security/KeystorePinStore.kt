package dev.ginga.receiver.security

import android.content.Context
import dev.ginga.receiver.AppLog
import dev.ginga.transport.InMemoryPinStore
import dev.ginga.transport.PinCodec
import dev.ginga.transport.PinStore
import dev.ginga.transport.PinnedMac

/**
 * The Macs this tablet paired with ({id, name, fingerprint}, see [PinCodec]) in a [SealedFile]. A
 * missing or tampered file reads as "no pins": the Mac then asks to pair again. Reads come from
 * memory after the first load.
 */
class KeystorePinStore(context: Context) : PinStore {
    private val file = SealedFile(context, "wifi-pins", "ginga-pins")
    private val cache: InMemoryPinStore by lazy { InMemoryPinStore(file.read()?.let(PinCodec::decode).orEmpty()) }

    override fun get(id: String): PinnedMac? = cache.get(id)

    override fun all(): List<PinnedMac> = cache.all()

    override fun put(mac: PinnedMac) = synchronized(this) {
        cache.put(mac)
        save()
    }

    override fun remove(id: String) = synchronized(this) {
        cache.remove(id)
        save()
    }

    private fun save() {
        val pins = cache.all()
        file.write(PinCodec.encode(pins))
        AppLog.i("pins.saved", "count" to pins.size)
    }
}
