package dev.tab2mac.receiver

import android.content.Context
import android.hardware.usb.UsbAccessory
import android.net.wifi.WifiManager
import android.view.Surface
import dev.tab2mac.discovery.DiscoveredMac
import dev.tab2mac.discovery.MacDiscovery
import dev.tab2mac.discovery.NsdMacDiscovery
import dev.tab2mac.discovery.NsdMacResolver
import dev.tab2mac.protocol.DirectLink
import dev.tab2mac.protocol.ErrorMessage
import dev.tab2mac.protocol.Fingerprint
import dev.tab2mac.protocol.GoodbyeReason
import dev.tab2mac.protocol.InputMessage
import dev.tab2mac.protocol.Orientation
import dev.tab2mac.protocol.TransportKind
import dev.tab2mac.receiver.adb.LoopbackToken
import dev.tab2mac.receiver.adb.LoopbackTokenStore
import dev.tab2mac.receiver.adb.PreferencesTokenPersistence
import dev.tab2mac.receiver.device.DeviceCapabilities
import dev.tab2mac.receiver.direct.BleCredentialServer
import dev.tab2mac.receiver.direct.DirectKey
import dev.tab2mac.receiver.direct.DirectLinkFlow
import dev.tab2mac.receiver.direct.DirectState
import dev.tab2mac.receiver.direct.LocalHotspotNetwork
import dev.tab2mac.receiver.direct.WifiDirectNetwork
import dev.tab2mac.receiver.security.DirectKeyStore
import dev.tab2mac.receiver.security.KeystorePinStore
import dev.tab2mac.receiver.security.TabletIdentity
import dev.tab2mac.receiver.session.PairingContext
import dev.tab2mac.receiver.session.Session
import dev.tab2mac.receiver.session.SessionConfig
import dev.tab2mac.receiver.session.SessionListener
import dev.tab2mac.receiver.session.SessionState
import dev.tab2mac.receiver.session.endedByMac
import dev.tab2mac.receiver.settings.ReceiverSettings
import dev.tab2mac.receiver.stats.StreamStats
import dev.tab2mac.receiver.ui.CursorLayer
import dev.tab2mac.receiver.video.VideoPipeline
import dev.tab2mac.transport.AccessoryTransport
import dev.tab2mac.transport.ConnectionState
import dev.tab2mac.transport.MacLocator
import dev.tab2mac.transport.MacVerifier
import dev.tab2mac.transport.PinStore
import dev.tab2mac.transport.PinnedMac
import dev.tab2mac.transport.PinnedMacVerifier
import dev.tab2mac.transport.TcpTransport
import dev.tab2mac.transport.TcpTransportConfig
import dev.tab2mac.transport.Transport
import dev.tab2mac.transport.TransportChoice
import dev.tab2mac.transport.UsbAccessories
import dev.tab2mac.transport.WifiTransport
import dev.tab2mac.transport.WifiTransportConfig
import java.io.IOException
import java.net.InetSocketAddress
import java.security.GeneralSecurityException
import java.security.ProviderException
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** What the UI shows about the receiver. */
data class ReceiverState(
    /** A connection was requested and not yet ended. */
    val active: Boolean = false,
    /** How the current (or last) session reaches the Mac: `aoa`, `adb-tcp` or `wifi-tls`. */
    val transport: TransportKind? = null,
    /** The Mac of the current (or last) Wi‑Fi session. */
    val wifiMacName: String? = null,
    /** The Mac is attached as a USB accessory (it switched this tablet into accessory mode). */
    val accessoryAttached: Boolean = false,
    val connection: ConnectionState = ConnectionState.Idle,
    val session: SessionState = SessionState.Idle,
    val clockOffsetUs: Long? = null,
    val rttUs: Long? = null,
    val lastRemoteError: ErrorMessage? = null,
    /** Why the last session ended, if it did. */
    val endReason: String? = null,
    /** The no-router link (§6b), when one was started. */
    val direct: DirectState = DirectState.Idle,
    /** The Mac whose no-router key this tablet holds (the most recent), if any. */
    val directKeyMac: String? = null,
)

/** A Mac in the Wi‑Fi list: [paired] when its certificate is pinned; [identityChanged] when it presented another one. */
data class WifiMac(val mac: DiscoveredMac, val paired: Boolean, val identityChanged: Boolean)

/**
 * Process-wide owner of the connection: transport, [Session], video pipeline and statistics.
 * Activities come and go; the session keeps running on its own thread ("t2m-session"), and a
 * failure in it ends the session, never the process.
 *
 * Transports:
 * - **USB**, the Connect button: direct USB (Android Open Accessory) whenever the Mac's accessory
 *   is attached, TCP through `adb reverse` otherwise ([UsbAccessories.choose]). The accessory is
 *   watched for the whole process: unplugging ends a direct USB session (Idle, no fallback to
 *   ADB); after a disconnect, Connect reopens the accessory and says HELLO again, and plugging in
 *   opens the app through Android's accessory intent ([connectAccessory]).
 * - **Wi‑Fi**, only when the user picks a discovered Mac ([connectWifi]): its service is resolved
 *   again before every connection attempt, then TLS 1.3 with this tablet's KeyStore identity,
 *   the Mac pinned by fingerprint, pairing when it isn't ([confirmPairing], [rejectPairing]).
 *   USB keeps priority: attaching the accessory replaces a Wi‑Fi session.
 */
class ReceiverController(context: Context, val settings: ReceiverSettings) {
    private val appContext = context.applicationContext
    private val sessionThread = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "t2m-session").apply { priority = Thread.MAX_PRIORITY }
    }
    private val crashGuard = CoroutineExceptionHandler { _, error -> onSessionCrashed(error) }
    private val scope = CoroutineScope(SupervisorJob() + sessionThread.asCoroutineDispatcher() + crashGuard)
    private val capabilities = DeviceCapabilities(context, settings)
    private val accessories = UsbAccessories(context)

    /** The Mac's adb loopback token, sent in HELLO over adb-tcp only. */
    private val loopbackTokens = LoopbackTokenStore(PreferencesTokenPersistence(context))

    /** Created on the session thread when first needed: KeyStore operations are slow. */
    private val identity: TabletIdentity by lazy { TabletIdentity.loadOrCreate() }
    private val pins: PinStore by lazy { KeystorePinStore(appContext) }
    private val directKeys: DirectKeyStore by lazy { DirectKeyStore(appContext) }

    /** The no-router link in progress (§6b), if any. */
    @Volatile
    private var directFlow: DirectLinkFlow? = null

    /** Session thread: the current session runs over the direct link. */
    private var directSession = false
    private val discovery: MacDiscovery = NsdMacDiscovery(context)

    /** Wi‑Fi latency mode, held only while a Wi‑Fi stream is live on screen. */
    private val wifiLock: WifiManager.WifiLock? = appContext.getSystemService(WifiManager::class.java)
        ?.createWifiLock(WifiManager.WIFI_MODE_FULL_LOW_LATENCY, "Tab2Mac:stream")
        ?.apply { setReferenceCounted(false) }

    /** Receiver statistics (reports and overlay). */
    val stats: StreamStats = StreamStats(decoderQueue = { pipeline.pendingInputCount })

    /** The pointer the tablet draws itself (§3.3b); the stream activity attaches its view here. */
    val cursor: CursorLayer = CursorLayer()

    /** Decoder and renderer; the stream activity attaches its Surface here. */
    val pipeline: VideoPipeline = VideoPipeline(
        stats = stats,
        keyframeRequester = { reason -> scope.launch { session?.requestKeyframe(reason) } },
        clockOffset = { session?.clockOffsetUs },
        operatingRateFactor = { if (settings.fastDecoder) 2.0 else 1.0 },
    )

    @Volatile
    private var session: Session? = null
    private var sessionJob: Job? = null

    /** The current session's transport when it is direct USB; read by the detach receiver (main thread). */
    @Volatile
    private var accessoryTransport: AccessoryTransport? = null

    /** The current session's transport when it is adb-tcp; a new loopback token wakes it. */
    @Volatile
    private var adbTransport: TcpTransport? = null

    // Session thread only.
    private var permissionPending = false
    /** No automatic direct USB connection: the user disconnected, or the Mac ended the session for good. */
    private var autoConnectBlocked = false
    /** The session runs over Wi‑Fi (a network Mac or a direct link): the WifiLock applies. */
    private var wifiSession = false

    /** Whether a video Surface exists (the stream screen is visible). Survives sessions. */
    @Volatile
    private var surfaceAvailable = false

    /** Wakes the timer loop when the session's deadlines may have changed. */
    private val wake = Channel<Unit>(Channel.CONFLATED)

    private val mutableState = MutableStateFlow(ReceiverState())
    val state: StateFlow<ReceiverState> = mutableState.asStateFlow()

    private val pinnedIds = MutableStateFlow<Set<String>>(emptySet())
    private val identityChangedIds = MutableStateFlow<Set<String>>(emptySet())

    /** Macs on the local network while discovery runs ([startDiscovery]), with their pairing status. */
    val wifiMacs: StateFlow<List<WifiMac>> = combine(discovery.macs, pinnedIds, identityChangedIds) { macs, pinned, changed ->
        macs.filter { it.isCompatible }.map { WifiMac(it, it.id in pinned, it.id in changed) }
    }.stateIn(scope, SharingStarted.Eagerly, emptyList())

    init {
        pipeline.setTimingSampleInterval(HIDDEN_TIMING_SAMPLE_INTERVAL)
        // Watched for the whole process: the status says whether Connect will use the accessory,
        // and unplugging ends a direct USB session at once. A broadcast, not polling.
        accessories.watchDetach {
            accessoryTransport?.onAccessoryDetached()
            mutableState.update { it.copy(accessoryAttached = false) }
        }
        refreshAccessory()
        scope.launch { mutableState.update { it.copy(directKeyMac = directKeys.latest()?.macName) } }
    }

    /**
     * "Direct connection (no router)" (§6b): bring up this tablet's own network, offer its
     * credentials to the Mac over Bluetooth LE, and connect when the Mac says where it listens.
     * Needs a key a Mac handed over in an earlier session. The runtime permissions are the
     * caller's to request.
     */
    fun startDirect(testKey: DirectKey? = null, hotspotOnly: Boolean = false) {
        scope.launch {
            if (directFlow?.state.let { it != null && it !is DirectState.Ended }) return@launch
            val key = testKey ?: directKeys.latest()
            if (key == null) {
                mutableState.update {
                    it.copy(direct = DirectState.Ended("no key yet: connect once over USB or Wi‑Fi, so the Mac can hand one over"))
                }
                return@launch
            }
            val random = SecureRandom()
            val flow = DirectLinkFlow(
                key = key,
                networks = if (hotspotOnly) {
                    listOf(LocalHotspotNetwork(appContext))
                } else {
                    listOf(WifiDirectNetwork(appContext), LocalHotspotNetwork(appContext))
                },
                server = BleCredentialServer(appContext),
                connect = { host, port ->
                    scope.launch {
                        replaceCurrentSession()
                        directSession = true
                        start(TransportKind.WIFI_TLS, direct = DirectTarget(host, port, key.macName))
                        if (session == null) {
                            directSession = false
                            directFlow?.onSessionEnded(mutableState.value.endReason ?: "the Wi‑Fi session couldn't start")
                        }
                    }
                },
                onState = { state -> onDirectState(state) },
                random = { size -> ByteArray(size).also(random::nextBytes) },
            )
            flow.onRefused = { why -> AppLog.w("direct.address-refused", "why" to why) }
            directFlow = flow
            AppLog.i("direct.start", "keyId" to key.keyIdHex, "mac" to key.macName)
            flow.start()
        }
    }

    /** Cancel: ends the direct link's network and Bluetooth LE, and its session if one runs. */
    fun cancelDirect() {
        scope.launch {
            directFlow?.cancel()
            if (directSession) session?.let { current ->
                current.close(GoodbyeReason.USER)
                teardown()
            }
        }
    }

    private fun onDirectState(state: DirectState) {
        AppLog.i("direct.state", "state" to state.javaClass.simpleName, "reason" to (state as? DirectState.Ended)?.reason)
        mutableState.update { it.copy(direct = state) }
        if (state is DirectState.Ended) {
            // The network is gone: a session over it can't go on.
            scope.launch {
                if (directSession) session?.let { current ->
                    current.close(GoodbyeReason.USER)
                    teardown()
                }
            }
        }
    }

    /**
     * Connects over USB: direct USB when the Mac's accessory is attached (asking the user for
     * access first if needed), ADB otherwise. Does nothing while a session runs.
     */
    fun connect() {
        scope.launch {
            autoConnectBlocked = false
            if (session != null) return@launch
            when (val choice = accessories.choose()) {
                TransportChoice.AdbTcp -> start(TransportKind.ADB_TCP)
                is TransportChoice.Accessory -> start(TransportKind.AOA)
                is TransportChoice.AccessoryNeedsPermission -> requestAccessoryPermission(choice.accessory)
            }
        }
    }

    /**
     * Android opened the app for the Mac's accessory, which also granted access to it: connect
     * over it now. Any other session gives way (USB has priority; switching to accessory mode cut
     * an ADB tunnel anyway); a direct USB session that is still alive is kept.
     */
    fun connectAccessory() {
        scope.launch {
            autoConnectBlocked = false
            mutableState.update { it.copy(accessoryAttached = true) }
            val current = session
            val directState = accessoryTransport?.state?.value
            if (current != null && current.state !is SessionState.Ended && directState != null && directState !is ConnectionState.Closed) {
                return@launch
            }
            val accessory = accessories.find()
            if (accessory == null) {
                AppLog.w("accessory.gone-before-connect")
                return@launch
            }
            if (!accessories.hasPermission(accessory)) {
                requestAccessoryPermission(accessory)
                return@launch
            }
            replaceCurrentSession()
            start(TransportKind.AOA)
        }
    }

    /** Connects to [mac] over Wi‑Fi, replacing any current session: the user picked it. */
    fun connectWifi(mac: DiscoveredMac) {
        scope.launch {
            replaceCurrentSession()
            start(TransportKind.WIFI_TLS, mac)
        }
    }

    /** The user checked that both screens show the same pairing code. */
    fun confirmPairing() {
        scope.launch { session?.confirmPairing() }
    }

    /** The user cancelled pairing. */
    fun rejectPairing() {
        scope.launch { session?.rejectPairing() }
    }

    /** Forgets a paired Mac (for example one whose identity changed): it must pair again. */
    fun forgetMac(id: String) {
        scope.launch {
            pins.remove(id)
            identityChangedIds.update { it - id }
            refreshPins()
            AppLog.i("wifi.forgotten", "mac" to id)
        }
    }

    /** Looks for Macs on the network; only while a picker is on screen, as browsing costs radio time. */
    fun startDiscovery() {
        discovery.start()
        scope.launch { refreshPins() }
    }

    fun stopDiscovery() {
        discovery.stop()
    }

    /**
     * The app started or came to the foreground: re-reads whether the Mac's accessory is attached
     * (a real attach arrives as an intent) and, with "Reconnect automatically", opens it if nothing
     * else does ([AccessoryAutoConnect]).
     */
    fun refreshAccessory() {
        scope.launch {
            val accessory = accessories.find()
            mutableState.update { it.copy(accessoryAttached = accessory != null) }
            val current = session
            val decision = AccessoryAutoConnect.decide(
                accessoryReady = accessory != null && accessories.hasPermission(accessory),
                autoReconnect = settings.autoReconnect,
                blocked = autoConnectBlocked,
                current = current?.let { mutableState.value.transport },
                streaming = current?.state is SessionState.Streaming,
            )
            if (decision == AccessoryAutoConnect.Decision.NONE) return@launch
            AppLog.i("accessory.auto-connect", "decision" to decision)
            replaceCurrentSession()
            start(TransportKind.AOA)
        }
    }

    /**
     * The Mac handed over its adb loopback token ([dev.tab2mac.receiver.adb.LoopbackTokenReceiver]).
     * A well-formed one is kept, and an adb session waiting to reconnect (for example after ERROR
     * `unauthorized`) retries at once. Returns whether the token was accepted.
     */
    fun acceptLoopbackToken(text: String?): Boolean {
        if (!loopbackTokens.offer(text)) return false
        adbTransport?.retryNow()
        return true
    }

    /** Whether the Mac is attached as a USB accessory (the cable is in and Tab2Mac on the Mac switched it). */
    fun accessoryAttached(): Boolean = accessories.find() != null

    private fun requestAccessoryPermission(accessory: UsbAccessory) {
        if (permissionPending) return
        permissionPending = true
        accessories.requestPermission(accessory) { granted ->
            scope.launch {
                permissionPending = false
                if (!granted) {
                    AppLog.w("accessory.permission-denied")
                    mutableState.update { it.copy(transport = TransportKind.AOA, endReason = "access to the USB accessory was not allowed") }
                } else if (session == null) {
                    start(TransportKind.AOA)
                }
            }
        }
    }

    /** Ends the current session, if any, without flipping the UI to "not connected" in between. */
    private fun replaceCurrentSession() {
        val current = session ?: return
        AppLog.i("receiver.replace-session", "transport" to mutableState.value.transport)
        session = null // its last callbacks no longer update the state
        current.close(GoodbyeReason.USER)
        stopSessionJobs()
    }

    /** Starts a session over [kind] ([mac] for Wi‑Fi). Session thread. */
    /** A Mac that joined this tablet's direct link (§6b) and listens at [host]:[port]. */
    private class DirectTarget(val host: String, val port: Int, val macName: String)

    private fun start(kind: TransportKind, mac: DiscoveredMac? = null, direct: DirectTarget? = null) {
        stats.reset()
        val transport: Transport
        var pairing: PairingContext? = null
        var config = SessionConfig()
        when (kind) {
            TransportKind.AOA -> {
                // With "Reconnect automatically" it reopens the fresh link the Mac offers after each session.
                transport = accessories.transport(settings.autoReconnect).also { accessoryTransport = it }
                config = ACCESSORY_SESSION_CONFIG
            }
            TransportKind.WIFI_TLS -> {
                val displayName = mac?.displayName ?: checkNotNull(direct).macName
                val tablet = try {
                    identity
                } catch (e: GeneralSecurityException) {
                    AppLog.e("identity.unavailable", e)
                    null
                } catch (e: IOException) {
                    AppLog.e("identity.unavailable", e)
                    null
                } catch (e: ProviderException) {
                    AppLog.e("identity.unavailable", e)
                    null
                }
                if (tablet == null) {
                    val reason = "this tablet's Wi‑Fi identity is unavailable"
                    mutableState.update { it.copy(active = false, transport = kind, wifiMacName = displayName, endReason = reason) }
                    updateWifiLock()
                    return
                }
                wifiSession = true
                // Pins are kept by the Mac's id, the first 12 hex digits of its certificate fingerprint
                // (§6): the TXT id for a Mac found on the network, computed for a direct link.
                val pinIdOf: (Fingerprint) -> String = { fingerprint -> mac?.id ?: fingerprint.hex.take(12) }
                val locator: MacLocator
                val verifier: MacVerifier
                if (mac != null) {
                    // Resolved again before every attempt: the Mac's port changes whenever Tab2Mac starts.
                    val resolver = NsdMacResolver(appContext, mac.serviceName)
                    locator = MacLocator {
                        resolver.resolve()?.let { found -> found.preferredAddress?.let { InetSocketAddress(it, found.port) } }
                    }
                    verifier = PinnedMacVerifier(pins, mac.id)
                } else {
                    val target = checkNotNull(direct)
                    locator = MacLocator { InetSocketAddress(target.host, target.port) }
                    verifier = MacVerifier { fingerprint ->
                        val pinned = pins.get(pinIdOf(fingerprint))
                        if (pinned == null || pinned.fingerprint == fingerprint) null else PinnedMacVerifier.IDENTITY_CHANGED
                    }
                }
                transport = WifiTransport(
                    WifiTransportConfig(name = displayName, autoReconnect = settings.autoReconnect),
                    locator,
                    tablet.keyManager,
                    verifier,
                )
                pairing = PairingContext(
                    tabletFingerprint = tablet.fingerprint,
                    isPinned = { fingerprint -> pins.get(pinIdOf(fingerprint))?.fingerprint == fingerprint },
                    onPaired = { fingerprint, name ->
                        val id = pinIdOf(fingerprint)
                        pins.put(PinnedMac(id, name, fingerprint))
                        identityChangedIds.update { it - id }
                        refreshPins()
                    },
                )
                config = WIFI_SESSION_CONFIG
            }
            else -> transport = TcpTransport(TcpTransportConfig(autoReconnect = settings.autoReconnect)).also { adbTransport = it }
        }
        val listener = Listener()
        val newSession = Session(
            transport = transport,
            // Built per connection, so a token that arrived meanwhile goes out with the next HELLO.
            hello = { resume -> LoopbackToken.applyTo(capabilities.hello(resume, kind), loopbackTokens.token) },
            video = pipeline,
            stats = stats,
            clock = { System.nanoTime() },
            listener = listener,
            log = AppLog.session,
            config = config,
            pairing = pairing,
            cursor = cursor,
        ).apply {
            preferredRefreshRate = settings.preferredRefreshRate?.toDouble()
            desiredOrientation = capabilities.orientation()
            onVideoSurfaceChanged(surfaceAvailable)
        }
        listener.owner = newSession
        session = newSession
        mutableState.update {
            ReceiverState(
                active = true, transport = kind, wifiMacName = mac?.displayName ?: direct?.macName,
                accessoryAttached = it.accessoryAttached, direct = it.direct,
            )
        }
        AppLog.i("receiver.connect", "transport" to kind, "endpoint" to transport.endpoint, "autoReconnect" to settings.autoReconnect)
        sessionJob = scope.launch {
            launch {
                transport.state.collect { connection ->
                    newSession.onConnectionState(connection)
                    if (session === newSession) mutableState.update { it.copy(connection = connection) }
                    if (connection is ConnectionState.Closed && connection.reason == PinnedMacVerifier.IDENTITY_CHANGED && mac != null) {
                        identityChangedIds.update { it + mac.id }
                    }
                    wake.trySend(Unit)
                }
            }
            launch { transport.incoming.collect { newSession.onIncoming(it) } }
            // Timers without polling: sleep until the session's next deadline (1 Hz while
            // streaming, 4 Hz reports on Wi‑Fi, nothing at all while idle), or until its state changes.
            launch {
                while (isActive) {
                    newSession.onTick()
                    val waitNanos = newSession.nanosUntilNextTick()
                    if (waitNanos == null) {
                        wake.receive()
                    } else {
                        withTimeoutOrNull(TimeUnit.NANOSECONDS.toMillis(waitNanos) + 1) { wake.receive() }
                    }
                }
            }
        }
        transport.connect()
    }

    /** Says GOODBYE and disconnects. A direct USB accessory stays watched: Connect reopens it. */
    fun disconnect() {
        scope.launch {
            autoConnectBlocked = true
            val current = session ?: return@launch
            AppLog.i("receiver.disconnect")
            current.close(GoodbyeReason.USER)
            teardown()
        }
    }

    /** The stream screen's Surface exists: decode into it, and resume a paused or suspended stream. */
    fun attachSurface(surface: Surface) {
        surfaceAvailable = true
        pipeline.attachSurface(surface)
        scope.launch {
            session?.onVideoSurfaceChanged(true)
            updateWifiLock()
            wake.trySend(Unit)
        }
    }

    /** The Surface is going away: stop decoding now; the session pauses the stream shortly after. */
    fun detachSurface() {
        surfaceAvailable = false
        pipeline.detachSurface()
        scope.launch {
            session?.onVideoSurfaceChanged(false)
            updateWifiLock()
            wake.trySend(Unit)
        }
    }

    /** Sends one `MotionEvent`'s worth of touch / S Pen input in one write. UI thread; never blocks. */
    fun sendInput(batch: List<InputMessage>) {
        if (session?.sendInputs(batch) == true) stats.onInputSent(batch.size)
    }

    /** Sends one key of a hardware keyboard (§3.3c); false when nothing takes it. UI thread; never blocks. */
    fun sendKey(down: Boolean, usage: Int, modifiers: Int, eventTimeNanos: Long): Boolean =
        session?.sendKey(down, usage, modifiers, eventTimeNanos / 1_000) == true

    /** The tablet's orientation changed. */
    fun requestOrientation(orientation: Orientation) {
        scope.launch { session?.requestOrientation(orientation) }
    }

    /** Record every frame's latencies while the overlay shows them, 1 in [HIDDEN_TIMING_SAMPLE_INTERVAL] otherwise. */
    fun setDiagnosticsVisible(visible: Boolean) {
        pipeline.setTimingSampleInterval(if (visible) 1 else HIDDEN_TIMING_SAMPLE_INTERVAL)
    }

    private fun teardown() {
        if (directSession) {
            directSession = false
            directFlow?.onSessionEnded(mutableState.value.endReason ?: "session ended")
        }
        stopSessionJobs()
        session = null
        mutableState.update { it.copy(active = false, accessoryAttached = accessories.find() != null) }
        updateWifiLock()
    }

    private fun stopSessionJobs() {
        sessionJob?.cancel()
        sessionJob = null
        accessoryTransport = null
        adbTransport = null
        wifiSession = false
    }

    private fun refreshPins() {
        pinnedIds.value = pins.all().mapTo(HashSet()) { it.id }
    }

    /**
     * `WIFI_MODE_FULL_LOW_LATENCY` only while a Wi‑Fi stream is live and on screen (Android also
     * ignores it in the background); released when paused, hidden or disconnected. Session thread.
     */
    private fun updateWifiLock() {
        val lock = wifiLock ?: return
        val streaming = session?.state as? SessionState.Streaming
        val wanted = wifiSession && streaming != null && !streaming.paused && surfaceAvailable
        if (wanted == lock.isHeld) return
        if (wanted) lock.acquire() else lock.release()
        AppLog.i("wifi.low-latency", "held" to wanted)
    }

    /** A bug in the session's coroutines: end the session cleanly instead of crashing the app. */
    private fun onSessionCrashed(error: Throwable) {
        AppLog.e("receiver.session-crashed", error)
        val broken = session
        mutableState.update { it.copy(endReason = "internal error: ${error.message ?: error.javaClass.simpleName}") }
        scope.launch {
            try {
                broken?.close(GoodbyeReason.ERROR)
            } catch (e: RuntimeException) {
                AppLog.e("receiver.close-after-crash-failed", e)
            }
            pipeline.onStreamStopped()
            if (session === broken) teardown()
        }
    }

    /** Session callbacks, on the session thread; ignored once [owner] was replaced. */
    private inner class Listener : SessionListener {
        var owner: Session? = null

        private val current: Boolean get() = owner != null && session === owner

        override fun onStateChanged(state: SessionState) {
            if (!current) return
            wake.trySend(Unit)
            mutableState.update { current ->
                current.copy(session = state, endReason = (state as? SessionState.Ended)?.reason ?: current.endReason)
            }
            updateWifiLock()
            if (state is SessionState.Streaming && directSession) directFlow?.onConnected()
            if (state is SessionState.Ended) {
                AppLog.i("receiver.session-ended", "reason" to state.reason)
                // GOODBYE user/replaced: the Mac ended it on purpose; don't come back by ourselves.
                if (state.reason == endedByMac(GoodbyeReason.USER) || state.reason == endedByMac(GoodbyeReason.REPLACED)) autoConnectBlocked = true
                // Let the current callback finish before cancelling the collectors.
                scope.launch { if (session?.state is SessionState.Ended) teardown() }
            }
        }

        override fun onClockSync(offsetUs: Long, rttUs: Long) {
            if (current) mutableState.update { it.copy(clockOffsetUs = offsetUs, rttUs = rttUs) }
        }

        override fun onRemoteError(error: ErrorMessage) {
            if (current) mutableState.update { it.copy(lastRemoteError = error) }
        }

        override fun onDirectLink(message: DirectLink) {
            if (!current) return
            val macName = (owner?.state as? SessionState.Streaming)?.welcome?.mac?.name ?: "Mac"
            if (directKeys.put(message, macName)) {
                mutableState.update { it.copy(directKeyMac = macName) }
            } else {
                AppLog.w("direct.key-malformed")
            }
        }
    }

    private companion object {
        /** Latency samples while nobody looks: 15 per second at 60 fps, plenty for the Mac's report. */
        const val HIDDEN_TIMING_SAMPLE_INTERVAL = 4

        /**
         * Direct USB: RECEIVER_REPORT and PING at 1 Hz like ADB (fixed bitrate over USB). No
         * handshake timeout: the Mac reads HELLO whenever it opens its side of the link.
         */
        val ACCESSORY_SESSION_CONFIG = SessionConfig(handshakeTimeoutNanos = null)

        /** Wi‑Fi: RECEIVER_REPORT every 250 ms, which the Mac's bitrate controller adapts to. */
        val WIFI_SESSION_CONFIG = SessionConfig(reportIntervalNanos = TimeUnit.MILLISECONDS.toNanos(250))
    }
}
