package dev.tab2mac.receiver.ui

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import dev.tab2mac.protocol.hexToBytes
import dev.tab2mac.receiver.BuildConfig
import dev.tab2mac.receiver.R
import dev.tab2mac.receiver.ReceiverController
import dev.tab2mac.receiver.ReceiverState
import dev.tab2mac.receiver.Tab2MacApplication
import dev.tab2mac.receiver.WifiMac
import dev.tab2mac.receiver.direct.DirectKey
import dev.tab2mac.receiver.session.SessionState
import dev.tab2mac.receiver.ui.widget.PairingCodeView
import dev.tab2mac.receiver.ui.widget.Spark
import dev.tab2mac.receiver.ui.widget.StatusOrbitView
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.launch

/**
 * Home (design/ginga-design/flows.md, "Tablet"): the StatusOrbit at the top, then one panel for
 * where the connection is ([HomeModel]): Procurando, Mac encontrado, Cabo USB, Sem roteador,
 * Pareando, Conectando, Conectado/Pausado. The chips pick the method while nothing is connected;
 * the technical line (codec, ports, adb) is collapsed in Diagnóstico; settings are in
 * [SettingsActivity].
 *
 * Opened for the Mac's USB accessory (through [AccessoryActivity]) or from the launcher while the
 * accessory is attached, it connects over direct USB and opens the display as soon as the
 * session starts. Network discovery runs only while this screen is visible.
 */
class MainActivity : Activity() {
    private lateinit var controller: ReceiverController
    private lateinit var statusOrbit: StatusOrbitView
    private lateinit var panels: Map<Class<out HomePanel>, View>
    private lateinit var macList: LinearLayout
    private lateinit var usbTitle: TextView
    private lateinit var usbSub: TextView
    private lateinit var directStatus: TextView
    private lateinit var directStart: Button
    private lateinit var directCancel: Button
    private lateinit var pairingTitle: TextView
    private lateinit var pairingCode: PairingCodeView
    private lateinit var pairingSub: TextView
    private lateinit var pairingAccept: Button
    private lateinit var pairingReject: Button
    private lateinit var connectingTitle: TextView
    private lateinit var connectingDetail: TextView
    private lateinit var connectedTitle: TextView
    private lateinit var connectedSub: TextView
    private lateinit var connectedSpecs: TextView
    private lateinit var openStream: Button
    private lateinit var notice: TextView
    private lateinit var chips: View
    private lateinit var chipViews: Map<ConnectMethod, TextView>
    private lateinit var diagnosticsAction: TextView
    private lateinit var diagnosticsText: TextView
    private val scope = MainScope()

    /** The appearance this activity was themed with; a different setting recreates it. */
    private lateinit var appearance: Appearance

    /** The chip the user picked; null follows the situation (USB when the cable is in). */
    private var chosenMethod: ConnectMethod? = null
    private var diagnosticsExpanded = false
    private var lastState = ReceiverState()
    private var lastMacs: List<WifiMac> = emptyList()
    private var shownPanel: Class<out HomePanel>? = null

    /** Device rows on screen, by Mac id, so only new Macs rise in. */
    private val macRows = LinkedHashMap<String, View>()

    /** The permission refusal replaces the direct link's status line until the state changes. */
    private var directStatusOverride = false

    /** Open the display as soon as a session is active (not only once it streams). */
    private var openStreamWhenActive = false

    override fun onCreate(savedInstanceState: Bundle?) {
        controller = (application as Tab2MacApplication).controller
        appearance = controller.settings.appearance
        appearance.apply(this)
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        statusOrbit = findViewById(R.id.status_orbit)
        panels = mapOf(
            HomePanel.Searching::class.java to findViewById(R.id.panel_searching),
            HomePanel.Found::class.java to findViewById(R.id.panel_found),
            HomePanel.Usb::class.java to findViewById(R.id.panel_usb),
            HomePanel.Direct::class.java to findViewById(R.id.panel_direct),
            HomePanel.Pairing::class.java to findViewById(R.id.panel_pairing),
            HomePanel.Connecting::class.java to findViewById(R.id.panel_connecting),
            HomePanel.Connected::class.java to findViewById(R.id.panel_connected),
        )
        macList = findViewById(R.id.mac_list)
        usbTitle = findViewById(R.id.usb_title)
        usbSub = findViewById(R.id.usb_sub)
        directStatus = findViewById(R.id.direct_status)
        directStart = findViewById(R.id.direct)
        directCancel = findViewById(R.id.direct_cancel)
        pairingTitle = findViewById(R.id.pairing_title)
        pairingCode = findViewById(R.id.pairing_code)
        pairingSub = findViewById(R.id.pairing_sub)
        pairingAccept = findViewById(R.id.pairing_accept)
        pairingReject = findViewById(R.id.pairing_reject)
        connectingTitle = findViewById(R.id.connecting_title)
        connectingDetail = findViewById(R.id.connecting_detail)
        connectedTitle = findViewById(R.id.connected_title)
        connectedSub = findViewById(R.id.connected_sub)
        connectedSpecs = findViewById(R.id.connected_specs)
        openStream = findViewById(R.id.open_stream)
        notice = findViewById(R.id.notice)
        chips = findViewById(R.id.chips)
        chipViews = mapOf(
            ConnectMethod.WIFI to findViewById(R.id.chip_wifi),
            ConnectMethod.USB to findViewById(R.id.chip_usb),
            ConnectMethod.DIRECT to findViewById(R.id.chip_direct),
        )
        diagnosticsAction = findViewById(R.id.diagnostics_action)
        diagnosticsText = findViewById(R.id.diagnostics_text)

        findViewById<Button>(R.id.settings).setOnClickListener { startActivity(Intent(this, SettingsActivity::class.java)) }
        chipViews.forEach { (method, chip) ->
            chip.setOnClickListener {
                chosenMethod = method
                render()
            }
        }
        findViewById<Button>(R.id.usb_connect).setOnClickListener {
            Spark.burst(it)
            openStreamWhenActive = false
            controller.connect()
        }
        directStart.setOnClickListener {
            Spark.burst(it)
            startDirectWithPermissions()
        }
        directCancel.setOnClickListener { controller.cancelDirect() }
        pairingAccept.setOnClickListener {
            Spark.burst(it)
            controller.confirmPairing()
        }
        pairingReject.setOnClickListener { controller.rejectPairing() }
        findViewById<Button>(R.id.connecting_cancel).setOnClickListener { disconnect() }
        findViewById<Button>(R.id.disconnect).setOnClickListener { disconnect() }
        openStream.setOnClickListener { showStream() }
        findViewById<View>(R.id.diagnostics_toggle).setOnClickListener {
            diagnosticsExpanded = !diagnosticsExpanded
            render()
        }

        if (savedInstanceState == null) {
            handleLaunch(intent, fresh = intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0)
        } else {
            openStreamWhenActive = savedInstanceState.getBoolean(STATE_OPEN_STREAM_WHEN_ACTIVE)
            chosenMethod = savedInstanceState.getString(STATE_METHOD)?.let { name -> ConnectMethod.entries.firstOrNull { it.name == name } }
            diagnosticsExpanded = savedInstanceState.getBoolean(STATE_DIAGNOSTICS)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLaunch(intent, fresh = false)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean(STATE_OPEN_STREAM_WHEN_ACTIVE, openStreamWhenActive)
        outState.putString(STATE_METHOD, chosenMethod?.name)
        outState.putBoolean(STATE_DIAGNOSTICS, diagnosticsExpanded)
    }

    override fun onRestart() {
        super.onRestart()
        if (controller.settings.appearance != appearance) recreate()
    }

    override fun onStart() {
        super.onStart()
        controller.refreshAccessory()
        controller.startDiscovery()
        scope.launch {
            controller.wifiMacs.collect { macs ->
                lastMacs = macs
                render()
            }
        }
        scope.launch {
            // The display opens by itself only when a stream *starts* while this screen is shown.
            // Coming back here (Back from the display, relaunching the app) never reopens it.
            var previous: SessionState? = null
            controller.state.collect { state ->
                if (state.direct != lastState.direct) directStatusOverride = false
                lastState = state
                render()
                val starting = previous != null && previous !is SessionState.Streaming && state.session is SessionState.Streaming
                if (openStreamWhenActive && state.active) {
                    openStreamWhenActive = false
                    showStream()
                } else if (starting) {
                    showStream()
                }
                previous = state.session
            }
        }
    }

    override fun onStop() {
        scope.coroutineContext.cancelChildren()
        controller.stopDiscovery()
        super.onStop()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    /**
     * The Mac's accessory was just attached ([AccessoryActivity]): connect over it and open the
     * display right away. On a fresh launch from the launcher with the accessory already attached
     * (for example after dismissing Android's prompt), do the same, asking for access first.
     */
    private fun handleLaunch(intent: Intent, fresh: Boolean) {
        when {
            intent.getBooleanExtra(EXTRA_ACCESSORY_ATTACHED, false) -> {
                openStreamWhenActive = true
                controller.connectAccessory()
            }
            fresh && intent.action == Intent.ACTION_MAIN && !controller.state.value.active && controller.accessoryAttached() -> {
                openStreamWhenActive = true
                controller.connect()
            }
        }
        handleAutomation(intent)
    }

    /**
     * Debug builds only, for scripted smoke tests:
     * `adb shell am start -n dev.tab2mac.receiver/.ui.MainActivity --ez connect true`, and
     * `adb shell am start --activity-clear-top -n dev.tab2mac.receiver/.ui.MainActivity --ez disconnect true`,
     * `--es appearance space` (system, light, dark, space).
     */
    private fun handleAutomation(intent: Intent?) {
        if (!BuildConfig.DEBUG || intent == null) return
        // `--es appearance system|light|dark|space`: screenshots of each theme without tapping.
        intent.getStringExtra(EXTRA_APPEARANCE)?.let { value ->
            controller.settings.appearance = Appearance.fromStorage(value)
            if (controller.settings.appearance != appearance) recreate()
        }
        when {
            intent.getBooleanExtra(EXTRA_CONNECT, false) && !controller.state.value.active -> controller.connect()
            intent.getBooleanExtra(EXTRA_DISCONNECT, false) && controller.state.value.active -> controller.disconnect()
            // The §6b network and Bluetooth LE with the protocol's test key (32 × 0x55), no Mac needed.
            intent.getBooleanExtra(EXTRA_DIRECT_TEST, false) -> controller.startDirect(
                DirectKey("0102030405060708".hexToBytes(), ByteArray(32) { 0x55 }, "test Mac"),
                hotspotOnly = intent.getBooleanExtra(EXTRA_DIRECT_HOTSPOT, false),
            )
            intent.getBooleanExtra(EXTRA_DIRECT_CANCEL, false) -> controller.cancelDirect()
        }
    }

    private fun disconnect() {
        openStreamWhenActive = false
        controller.disconnect()
    }

    /** Draws [HomeModel] for the latest state and Macs. */
    private fun render() {
        val model = HomeModel.of(lastState, lastMacs, chosenMethod)
        statusOrbit.setState(model.pill.orbit, model.pill.text.resolve(this))
        showPanel(model.panel)
        when (val panel = model.panel) {
            HomePanel.Searching -> Unit
            is HomePanel.Found -> renderMacs(panel.macs)
            is HomePanel.Usb -> {
                usbTitle.setText(if (panel.attached) R.string.usb_title_attached else R.string.usb_title_plug)
                usbSub.setText(if (panel.attached) R.string.usb_sub_attached else R.string.usb_sub_plug)
            }
            is HomePanel.Direct -> {
                if (!directStatusOverride) directStatus.text = panel.status.resolve(this)
                directStart.visibility = if (panel.inProgress) View.GONE else View.VISIBLE
                directStart.setGingaEnabled(panel.canStart)
                directCancel.visibility = if (panel.inProgress) View.VISIBLE else View.GONE
            }
            is HomePanel.Pairing -> renderPairing(panel)
            is HomePanel.Connecting -> {
                connectingTitle.text = panel.title.resolve(this)
                connectingDetail.text = panel.detail?.resolve(this)
                connectingDetail.visibility = if (panel.detail == null) View.GONE else View.VISIBLE
            }
            is HomePanel.Connected -> {
                connectedTitle.setText(if (panel.paused) R.string.paused_title else R.string.connected_title)
                connectedSub.text = panel.explanation.resolve(this)
                connectedSpecs.text = panel.specs?.resolve(this)
                connectedSpecs.visibility = if (panel.specs == null) View.GONE else View.VISIBLE
                openStream.setGingaEnabled(panel.canShowDisplay)
            }
        }
        chips.visibility = if (model.method == null) View.GONE else View.VISIBLE
        chipViews.forEach { (method, chip) ->
            val selected = method == model.method
            chip.isSelected = selected
            chip.setTextColor(themeColor(if (selected) R.attr.gingaInk else R.attr.gingaInkMuted))
        }
        notice.text = model.notice?.resolve(this)
        notice.visibility = if (model.notice == null) View.GONE else View.VISIBLE
        diagnosticsAction.setText(if (diagnosticsExpanded) R.string.details_hide else R.string.details_show)
        diagnosticsText.visibility = if (diagnosticsExpanded) View.VISIBLE else View.GONE
        if (diagnosticsExpanded) {
            val text = StatusText.of(lastState)
            diagnosticsText.text = if (text.detail.isEmpty()) text.headline else "${text.headline}\n${text.detail}"
        }
    }

    /** One panel at a time; a new one fades in (dur-ui), at once with reduced motion. */
    private fun showPanel(panel: HomePanel) {
        val type = panel.javaClass
        if (type == shownPanel) return
        shownPanel = type
        val reduced = Motion.reduced(this)
        panels.forEach { (key, view) ->
            if (key == type) {
                view.visibility = View.VISIBLE
                view.animate().cancel()
                if (reduced) {
                    view.alpha = 1f
                } else {
                    view.alpha = 0f
                    view.animate().alpha(1f).setDuration(Motion.DUR_UI).setInterpolator(Motion.easeOut).start()
                }
            } else {
                view.visibility = View.GONE
            }
        }
        if (type != HomePanel.Found::class.java) {
            macList.removeAllViews()
            macRows.clear()
        }
    }

    /**
     * One DeviceRow per Mac: name, meta in mono (pairing status · Wi‑Fi), Conectar / Reconectar /
     * Parear de novo. Rows already shown are updated in place; new ones rise in, 120 ms apart.
     */
    private fun renderMacs(rows: List<MacRow>) {
        val ids = rows.map { it.mac.mac.id }.toSet()
        macRows.keys.filter { it !in ids }.forEach { id -> macList.removeView(macRows.remove(id)) }
        val reduced = Motion.reduced(this)
        var entering = 0
        rows.forEachIndexed { index, row ->
            val item = row.mac
            val view = macRows[item.mac.id] ?: LayoutInflater.from(this).inflate(R.layout.item_device_row, macList, false).also {
                macList.addView(it, index.coerceAtMost(macList.childCount))
                macRows[item.mac.id] = it
                Motion.rise(it, entering++, reduced)
            }
            view.findViewById<TextView>(R.id.device_name).text = item.mac.displayName
            view.findViewById<TextView>(R.id.device_meta).text = row.meta.resolve(this)
            view.findViewById<Button>(R.id.device_action).apply {
                text = row.action.resolve(this@MainActivity)
                setOnClickListener {
                    Spark.burst(it)
                    openStreamWhenActive = false
                    // Pair again = forget the old pin first, so the Mac's new identity can pair.
                    if (item.identityChanged) controller.forgetMac(item.mac.id)
                    controller.connectWifi(item.mac)
                }
            }
            if (item.paired) {
                view.setOnLongClickListener {
                    confirmForget(item)
                    true
                }
            } else {
                view.setOnLongClickListener(null)
                view.isLongClickable = false
            }
        }
    }

    /**
     * §6 pairing: the Mac's name and the six digits. "Parear" (PAIRING `confirmed`) or "Não
     * parear" (`rejected`, GOODBYE `user`); once confirmed, it waits for the Mac's user.
     */
    private fun renderPairing(pairing: HomePanel.Pairing) {
        val code = pairing.code
        if (code != null) pairingCode.setCode(code)
        pairingCode.visibility = if (code == null) View.INVISIBLE else View.VISIBLE
        when {
            code == null -> {
                pairingTitle.text = getString(R.string.pairing_title, pairing.macName)
                pairingSub.setText(R.string.pairing_exchanging)
            }
            pairing.confirmed -> {
                pairingTitle.setText(R.string.pairing_confirm_title)
                pairingSub.text = getString(R.string.pairing_waiting, pairing.macName)
            }
            else -> {
                pairingTitle.text = getString(R.string.pairing_title, pairing.macName)
                pairingSub.setText(R.string.pairing_sub)
            }
        }
        val asking = code != null && !pairing.confirmed
        pairingAccept.visibility = if (asking) View.VISIBLE else View.GONE
        pairingReject.setText(if (asking) R.string.pairing_dont else R.string.cancel)
    }

    /** Disabled controls are at 45% opacity (Button.md). */
    private fun Button.setGingaEnabled(enabled: Boolean) {
        isEnabled = enabled
        alpha = if (enabled) 1f else 0.45f
    }

    /** The runtime permissions a direct link needs (§6b): Bluetooth LE, and the tablet's own network. */
    private fun directPermissions(): List<String> = listOf(
        Manifest.permission.BLUETOOTH_ADVERTISE,
        Manifest.permission.BLUETOOTH_CONNECT,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Manifest.permission.NEARBY_WIFI_DEVICES else Manifest.permission.ACCESS_FINE_LOCATION,
    )

    /** Asks for what's missing through the system dialog, then starts. */
    private fun startDirectWithPermissions() {
        val missing = directPermissions().filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) controller.startDirect() else requestPermissions(missing.toTypedArray(), REQUEST_DIRECT_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_DIRECT_PERMISSIONS) return
        if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            controller.startDirect()
        } else {
            directStatus.setText(R.string.direct_permissions_denied)
            directStatusOverride = true
        }
    }

    private fun confirmForget(item: WifiMac) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.forget_title, item.mac.displayName))
            .setMessage(R.string.forget_message)
            .setPositiveButton(R.string.forget) { _, _ -> controller.forgetMac(item.mac.id) }
            .setNegativeButton(R.string.cancel, null)
            .show()
    }

    private fun showStream() {
        startActivity(Intent(this, StreamActivity::class.java))
    }

    companion object {
        /** Boolean extra from [AccessoryActivity]: the Mac's accessory was just attached. */
        const val EXTRA_ACCESSORY_ATTACHED = "dev.tab2mac.receiver.extra.ACCESSORY_ATTACHED"

        private const val EXTRA_CONNECT = "connect"
        private const val EXTRA_DISCONNECT = "disconnect"
        private const val EXTRA_DIRECT_TEST = "directTest"
        private const val EXTRA_DIRECT_CANCEL = "directCancel"
        private const val EXTRA_DIRECT_HOTSPOT = "directHotspot"
        private const val EXTRA_APPEARANCE = "appearance"
        private const val STATE_OPEN_STREAM_WHEN_ACTIVE = "openStreamWhenActive"
        private const val STATE_METHOD = "method"
        private const val STATE_DIAGNOSTICS = "diagnosticsExpanded"
        private const val REQUEST_DIRECT_PERMISSIONS = 1
    }
}
