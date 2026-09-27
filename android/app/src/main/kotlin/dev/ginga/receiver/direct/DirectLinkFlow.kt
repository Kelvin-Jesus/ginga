package dev.ginga.receiver.direct

import dev.ginga.protocol.DirectAddress
import dev.ginga.protocol.DirectCredentials
import dev.ginga.protocol.DirectLinkCrypto
import dev.ginga.protocol.toHex
import java.util.concurrent.TimeUnit

/** The no-router key the Mac handed over (§6b DIRECT_LINK), for one Mac. A secret: never logged. */
class DirectKey(val keyId: ByteArray, val key: ByteArray, val macName: String) {
    init {
        require(keyId.size == DirectLinkCrypto.KEY_ID_SIZE && key.size == DirectLinkCrypto.KEY_SIZE) { "malformed direct key" }
    }

    val keyIdHex: String get() = keyId.toHex()

    override fun toString(): String = "DirectKey(keyId=$keyIdHex, mac=$macName)"
}

/** Where a direct link is (§6b), for the UI. */
sealed interface DirectState {
    data object Idle : DirectState

    /** Bringing up the tablet's own network ([network] names the kind being tried). */
    data class CreatingNetwork(val network: String) : DirectState

    /** The network is up and the credentials are offered over Bluetooth LE; the Mac hasn't come yet. */
    data class WaitingForMac(val ssid: String, val network: String) : DirectState

    /** The Mac joined and said where it listens; the Wi‑Fi session is connecting (TLS, pinning, pairing). */
    data class Connecting(val host: String, val port: Int) : DirectState

    /** The session runs over the tablet's network. */
    data object Connected : DirectState

    /** Over: the network and Bluetooth LE are torn down. */
    data class Ended(val reason: String) : DirectState
}

/** A way for the tablet to host a network: a Wi‑Fi Direct group, or a local-only hotspot. */
interface DirectNetwork {
    /** For the UI and logs, e.g. "Wi‑Fi Direct". */
    val kind: String

    /**
     * Brings the network up with [name] and [passphrase] where the system lets us choose them;
     * [onUp] reports what it really is. Exactly one of the callbacks runs, later [onLost] may.
     */
    fun start(name: String, passphrase: String, onUp: (ssid: String, passphrase: String) -> Unit, onFailed: (String) -> Unit, onLost: (String) -> Unit)

    /** Tears it down; idempotent. */
    fun stop()
}

/** The Bluetooth LE side of §6b: offers the credentials, receives the Mac's address. */
interface CredentialServer {
    /**
     * Starts the GATT service and advertising. [credentials] is asked on every read (a fresh blob
     * each time); [onAddress] gets each written address blob and says whether it was accepted.
     */
    fun start(credentials: () -> ByteArray, onAddress: (ByteArray) -> Boolean, onFailed: (String) -> Unit)

    /** Stops advertising and the service; idempotent. */
    fun stop()
}

/**
 * The tablet's side of a direct link (§6b) as a state machine: bring up a network (the first of
 * [networks] that works), offer its credentials over Bluetooth LE, accept one address from the Mac,
 * connect to it like any Wi‑Fi session, and tear everything down when the session ends, on
 * Cancel, or on any failure. Thread-safe: the Android callbacks come from the main thread (Wi‑Fi)
 * and Binder threads (GATT).
 *
 * Refusals: an address sealed for another key or tampered with, for another session (a replay
 * from an earlier link), after the credentials expired, or after one was already accepted.
 */
class DirectLinkFlow(
    private val key: DirectKey,
    private val networks: List<DirectNetwork>,
    private val server: CredentialServer,
    /** Starts the Wi‑Fi session to the Mac. */
    private val connect: (host: String, port: Int) -> Unit,
    private val onState: (DirectState) -> Unit,
    /** Unix time, ms. */
    private val now: () -> Long = System::currentTimeMillis,
    private val random: (size: Int) -> ByteArray,
    /** How long offered credentials are valid. */
    private val credentialsLifetimeMs: Long = TimeUnit.MINUTES.toMillis(5),
) {
    @Volatile
    var state: DirectState = DirectState.Idle
        private set

    private val credentialsKey = DirectLinkCrypto.subkey(key.key, DirectLinkCrypto.Purpose.CREDENTIALS)
    private val addressKey = DirectLinkCrypto.subkey(key.key, DirectLinkCrypto.Purpose.ADDRESS)
    private val session = random(16).toHex()
    private var networkIndex = -1
    private var network: DirectNetwork? = null
    private var ssid = ""
    private var passphrase = ""

    /** When the latest offered credentials expire (unix ms); 0 until one was read. */
    private var offeredUntil = 0L
    private var accepted = false

    @Synchronized
    fun start() {
        if (state != DirectState.Idle) return
        tryNextNetwork(null)
    }

    /** The user cancelled. */
    @Synchronized
    fun cancel() = end("cancelled")

    /** The Wi‑Fi session reached the Mac: stop offering credentials (Bluetooth LE costs power). */
    @Synchronized
    fun onConnected() {
        if (state !is DirectState.Connecting) return
        server.stop()
        setState(DirectState.Connected)
    }

    /** The Wi‑Fi session ended: the network must not outlive it. */
    @Synchronized
    fun onSessionEnded(reason: String) = end(reason)

    /** The current credentials blob, fresh nonce and expiry every time (GATT read). */
    @Synchronized
    fun credentials(): ByteArray {
        val expires = now() + credentialsLifetimeMs
        offeredUntil = expires
        val plaintext = DirectCredentials(TimeUnit.MILLISECONDS.toSeconds(expires), passphrase, session, ssid).encode()
        return DirectLinkCrypto.seal(credentialsKey, key.keyId, random(DirectLinkCrypto.NONCE_SIZE), plaintext)
    }

    /** The Mac wrote its address (GATT write). Returns whether it was accepted. */
    @Synchronized
    fun onAddress(sealed: ByteArray): Boolean {
        if (state !is DirectState.WaitingForMac || accepted) return refuse("unexpected")
        val plaintext = DirectLinkCrypto.open(addressKey, key.keyId, sealed) ?: return refuse("undecryptable")
        val address = DirectAddress.decode(plaintext) ?: return refuse("malformed")
        if (address.session != session) return refuse("another session")
        if (offeredUntil == 0L || now() > offeredUntil) return refuse("expired")
        accepted = true
        setState(DirectState.Connecting(address.host, address.port))
        connect(address.host, address.port)
        return true
    }

    private fun tryNextNetwork(previousFailure: String?) {
        networkIndex++
        val next = networks.getOrNull(networkIndex) ?: return end("no network could be created: ${previousFailure ?: "none available"}")
        network = next
        setState(DirectState.CreatingNetwork(next.kind))
        val name = "DIRECT-Ginga-" + key.keyIdHex.take(4)
        val secret = passphrase()
        next.start(
            name, secret,
            onUp = { actualSsid, actualPassphrase -> onNetworkUp(next, actualSsid, actualPassphrase) },
            onFailed = { reason -> if (network === next && state is DirectState.CreatingNetwork) tryNextNetwork("${next.kind}: $reason") },
            onLost = { reason -> if (network === next) end("${next.kind} network lost: $reason") },
        )
    }

    private fun onNetworkUp(from: DirectNetwork, actualSsid: String, actualPassphrase: String) {
        if (network !== from || state !is DirectState.CreatingNetwork) return
        ssid = actualSsid
        passphrase = actualPassphrase
        setState(DirectState.WaitingForMac(actualSsid, from.kind))
        server.start(::credentials, ::onAddress) { reason -> end("Bluetooth LE: $reason") }
    }

    private fun end(reason: String) {
        if (state is DirectState.Ended) return
        server.stop()
        network?.stop()
        network = null
        setState(DirectState.Ended(reason))
    }

    private fun refuse(why: String): Boolean {
        onRefused?.invoke(why)
        return false
    }

    /** Called with the reason of every refused address (for logs; never the content). */
    var onRefused: ((String) -> Unit)? = null

    /** 24 characters from 57 unambiguous letters and digits (≈ 140 bits); new for every link. */
    private fun passphrase(): String {
        val bytes = random(PASSPHRASE_LENGTH)
        return String(CharArray(PASSPHRASE_LENGTH) { ALPHABET[(bytes[it].toInt() and 0xFF) % ALPHABET.length] })
    }

    private fun setState(newState: DirectState) {
        state = newState
        onState(newState)
    }

    private companion object {
        const val PASSPHRASE_LENGTH = 24
        const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
    }
}
