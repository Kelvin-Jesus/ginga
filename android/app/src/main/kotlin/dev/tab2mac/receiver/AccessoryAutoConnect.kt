package dev.tab2mac.receiver

import dev.tab2mac.protocol.TransportKind

/**
 * Whether to open the Mac's USB accessory without being asked, when the app starts or comes back
 * to the foreground. Android sends `USB_ACCESSORY_ATTACHED` only on a real attach, so a tablet
 * that stayed in accessory mode while the Mac app restarted (or this app was reinstalled) would
 * otherwise never open the fresh link the Mac offers. Pure, so it's unit-tested.
 */
object AccessoryAutoConnect {
    enum class Decision {
        /** Leave things as they are. */
        NONE,

        /** Start a direct USB session. */
        CONNECT,

        /** End the ADB session that isn't streaming, then start a direct USB session: USB accessory wins. */
        REPLACE,
    }

    /**
     * @param accessoryReady the Mac's accessory is attached and access is granted
     * @param autoReconnect the "Reconnect automatically" setting
     * @param blocked the user disconnected, or the Mac ended the last session for good (GOODBYE
     *   `user`/`replaced`), since the last explicit Connect or attach
     * @param current the transport of the running session, null when there is none
     * @param streaming the running session shows video
     */
    fun decide(accessoryReady: Boolean, autoReconnect: Boolean, blocked: Boolean, current: TransportKind?, streaming: Boolean): Decision = when {
        !accessoryReady || !autoReconnect || blocked -> Decision.NONE
        current == null -> Decision.CONNECT
        current == TransportKind.ADB_TCP && !streaming -> Decision.REPLACE
        else -> Decision.NONE
    }
}
