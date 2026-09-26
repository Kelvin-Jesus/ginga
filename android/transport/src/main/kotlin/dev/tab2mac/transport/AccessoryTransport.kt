package dev.tab2mac.transport

/**
 * [Transport] over Android Open Accessory (M6, PROTOCOL.md §5): the Mac switched the tablet into
 * accessory mode, and the protocol runs over the accessory's two bulk endpoints, framed exactly as
 * over TCP. No developer mode, adb or network is involved.
 *
 * The link is `UsbManager.openAccessory()`'s file descriptor, read and written by the
 * [LinkTransport] threads: blocking reads with one always pending (the kernel's `f_accessory`
 * completes at most 16 KiB per read and has a single OUT request, so the host waits whenever no
 * read is queued), writes through the [SendQueue] writer.
 *
 * Lifecycle. While the cable stays in, the Mac offers a fresh link about a second after each
 * session ends (PROTOCOL.md §5), and every new link starts with a new HELLO (a new connection id).
 * - [RECONNECTING_OPTIONS] ("Reconnect automatically"): when a link ends (the Mac restarted,
 *   GOODBYE `shutdown`, a Mac gone silent — [LinkOptions.silenceTimeoutMs] tears the link down
 *   even while a read or write is blocked), the accessory is opened again with
 *   the usual backoff, for as long as it is attached and access is granted. Android sends
 *   `USB_ACCESSORY_ATTACHED` only on a real attach, so nothing else would reopen it.
 * - [SINGLE_LINK_OPTIONS]: one link; its end closes the transport, and a new connection is a new
 *   [AccessoryTransport].
 *
 * Either way it ends at once on [onAccessoryDetached], or when the opener reports the accessory
 * gone ([LinkAttempt.Gone]). A busy device node (the previous descriptor not yet released) is
 * retried.
 */
class AccessoryTransport(
    opener: LinkOpener,
    options: LinkOptions = SINGLE_LINK_OPTIONS,
    nanoClock: () -> Long = System::nanoTime,
) : LinkTransport(ENDPOINT, opener, options, nanoClock, "t2m-aoa") {

    /**
     * `ACTION_USB_ACCESSORY_DETACHED`: ends now with [ConnectionState.Closed], without draining
     * and without waiting for the pending read. Idempotent.
     */
    fun onAccessoryDetached() = terminate(DETACHED)

    companion object {
        const val ENDPOINT: String = "aoa://Tab2Mac"

        /** The [ConnectionState.Closed] reason after [onAccessoryDetached]. */
        const val DETACHED: String = "accessory detached"

        /** 64 KiB reads, which the kernel caps at its 16 KiB bulk buffer. */
        private const val READ_CHUNK = 64 * 1024

        /**
         * Nothing received for 4 s while streaming (the Mac answers a PING every second), or a
         * write blocked that long, means the Mac is gone: over USB nothing else says so.
         */
        const val SILENCE_TIMEOUT_MS: Long = 4_000

        /** One link; up to 4 opens while the device node is busy (0.25 + 0.5 + 1 s). */
        val SINGLE_LINK_OPTIONS: LinkOptions = LinkOptions(
            readChunkBytes = READ_CHUNK, singleLink = true, maxOpenAttempts = 4, silenceTimeoutMs = SILENCE_TIMEOUT_MS,
            resyncAtStart = true,
        )

        /** Reopens after every link with the usual backoff (0.25 → 5 s) while the accessory is attached. */
        val RECONNECTING_OPTIONS: LinkOptions = LinkOptions(
            readChunkBytes = READ_CHUNK, autoReconnect = true, silenceTimeoutMs = SILENCE_TIMEOUT_MS,
            // A fresh link can begin with the tail of the previous link's last partial write.
            resyncAtStart = true,
        )

        fun options(autoReconnect: Boolean): LinkOptions = if (autoReconnect) RECONNECTING_OPTIONS else SINGLE_LINK_OPTIONS
    }
}
