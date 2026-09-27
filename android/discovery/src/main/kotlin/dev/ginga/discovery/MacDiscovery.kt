package dev.ginga.discovery

import java.net.Inet4Address
import java.net.InetAddress
import kotlinx.coroutines.flow.StateFlow

/** Bonjour service type the Mac advertises (PROTOCOL.md §6). */
const val SERVICE_TYPE: String = "_ginga._tcp"

/**
 * The TXT record of a Ginga service (§6): no secrets, only what's needed to pick a Mac.
 *
 * @property protocolVersion `pv`, the Mac's maximum protocol version.
 * @property instanceId `id`, the Mac instance ID (stable per Mac identity; pins are kept by it).
 * @property name `name`, the Mac's display name.
 */
data class TxtRecord(val protocolVersion: Int?, val instanceId: String?, val name: String?) {
    companion object {
        /** Parses `NsdServiceInfo.getAttributes()`; missing or malformed keys become null. */
        fun parse(attributes: Map<String, ByteArray?>): TxtRecord {
            fun text(key: String): String? =
                attributes.entries.firstOrNull { it.key.equals(key, ignoreCase = true) }?.value
                    ?.toString(Charsets.UTF_8)?.trim()?.takeIf { it.isNotEmpty() }
            return TxtRecord(
                protocolVersion = text("pv")?.toIntOrNull(),
                instanceId = text("id"),
                name = text("name"),
            )
        }
    }
}

/** A Mac found on the local network. */
data class DiscoveredMac(
    val serviceName: String,
    val addresses: List<InetAddress>,
    val port: Int,
    val txt: TxtRecord,
) {
    /** What to show in a picker. */
    val displayName: String get() = txt.name ?: serviceName

    /** The key pins are stored under: the TXT `id`, or the service name for a Mac without one. */
    val id: String get() = txt.instanceId ?: serviceName

    /** Whether this implementation can talk to it (`pv` ≥ 1; a Mac without `pv` is assumed to). */
    val isCompatible: Boolean get() = (txt.protocolVersion ?: 1) >= 1

    /** The address to connect to: IPv4 first (link-local IPv6 needs a scope), else the first one. */
    val preferredAddress: InetAddress? get() = addresses.firstOrNull { it is Inet4Address } ?: addresses.firstOrNull()
}

/**
 * Finds Macs advertising [SERVICE_TYPE]. The Mac advertises and the tablet only browses, because
 * advertising will need the `ACCESS_LOCAL_NETWORK` runtime permission on Android 17 (research §5.3).
 * Browsing costs radio time: run it only while a Mac picker is on screen.
 */
interface MacDiscovery {
    /** Macs currently visible, resolved to addresses and ports. */
    val macs: StateFlow<List<DiscoveredMac>>

    /** Starts browsing (idempotent). */
    fun start()

    /** Stops browsing and forgets every Mac. */
    fun stop()
}
