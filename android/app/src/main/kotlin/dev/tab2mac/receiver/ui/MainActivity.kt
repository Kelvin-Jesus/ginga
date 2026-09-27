package dev.tab2mac.receiver.ui

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.graphics.Typeface
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.RadioGroup
import android.widget.Switch
import android.widget.TextView
import dev.tab2mac.protocol.PairingCode
import dev.tab2mac.receiver.BuildConfig
import dev.tab2mac.receiver.R
import dev.tab2mac.receiver.ReceiverController
import dev.tab2mac.receiver.ReceiverState
import dev.tab2mac.receiver.Tab2MacApplication
import dev.tab2mac.receiver.WifiMac
import dev.tab2mac.receiver.direct.DirectKey
import dev.tab2mac.protocol.hexToBytes
import dev.tab2mac.receiver.session.SessionState
import dev.tab2mac.receiver.ui.widget.SegmentedControl
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.launch

/**
 * Connection screen: status, Connect/Disconnect (USB), the Macs found on the Wi‑Fi network,
 * the pairing prompt, and settings.
 *
 * Opened for the Mac's USB accessory (through [AccessoryActivity]) or from the launcher while the
 * accessory is attached, it connects over direct USB and opens the display as soon as the
 * session starts. Network discovery runs only while this screen is visible.
 */
class MainActivity : Activity() {
    private lateinit var controller: ReceiverController
    private lateinit var status: TextView
    private lateinit var statusDetail: TextView
    private lateinit var connect: Button
    private lateinit var openStream: Button
    private lateinit var wifiHint: TextView
    private lateinit var wifiList: LinearLayout
    private lateinit var direct: Button
    private lateinit var directStatus: TextView
    private val scope = MainScope()

    /** The pairing prompt on screen, and the state it shows. */
    private var pairingDialog: AlertDialog? = null
    private var pairingShown: SessionState.Pairing? = null

    /** Open the display as soon as a session is active (not only once it streams). */
    private var openStreamWhenActive = false

    /** The appearance this activity was themed with; a different setting recreates it. */
    private lateinit var appearance: Appearance

    override fun onCreate(savedInstanceState: Bundle?) {
        controller = (application as Tab2MacApplication).controller
        appearance = controller.settings.appearance
        appearance.apply(this)
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        status = findViewById(R.id.status)
        statusDetail = findViewById(R.id.status_detail)
        connect = findViewById(R.id.connect)
        openStream = findViewById(R.id.open_stream)
        wifiHint = findViewById(R.id.wifi_hint)
        wifiList = findViewById(R.id.wifi_macs)
        direct = findViewById(R.id.direct)
        directStatus = findViewById(R.id.direct_status)
        direct.setOnClickListener {
            val state = controller.state.value
            if (DirectText.of(state.direct, state.directKeyMac).inProgress) controller.cancelDirect() else startDirectWithPermissions()
        }

        connect.setOnClickListener {
            openStreamWhenActive = false
            if (controller.state.value.active) controller.disconnect() else controller.connect()
        }
        openStream.setOnClickListener { showStream() }

        val settings = controller.settings
        findViewById<Switch>(R.id.auto_reconnect).apply {
            isChecked = settings.autoReconnect
            setOnCheckedChangeListener { _, checked -> settings.autoReconnect = checked }
        }
        findViewById<RadioGroup>(R.id.refresh).apply {
            check(
                when (settings.preferredRefreshRate) {
                    60 -> R.id.refresh_60
                    120 -> R.id.refresh_120
                    else -> R.id.refresh_mac
                },
            )
            setOnCheckedChangeListener { _, id ->
                settings.preferredRefreshRate = when (id) {
                    R.id.refresh_60 -> 60
                    R.id.refresh_120 -> 120
                    else -> null
                }
            }
        }
        findViewById<CheckBox>(R.id.fast_decoder).apply {
            isChecked = settings.fastDecoder
            setOnCheckedChangeListener { _, checked -> settings.fastDecoder = checked }
        }
        findViewById<CheckBox>(R.id.show_diagnostics).apply {
            isChecked = settings.showDiagnostics
            setOnCheckedChangeListener { _, checked -> settings.showDiagnostics = checked }
        }
        findViewById<SegmentedControl>(R.id.appearance).apply {
            val choices = Appearance.entries
            setOptions(choices.map { getString(it.labelRes) }, choices.indexOf(settings.appearance))
            onChange = { index ->
                settings.appearance = choices[index]
                recreate()
            }
        }
        if (savedInstanceState == null) {
            handleLaunch(intent, fresh = intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0)
        } else {
            openStreamWhenActive = savedInstanceState.getBoolean(STATE_OPEN_STREAM_WHEN_ACTIVE)
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
    }

    override fun onRestart() {
        super.onRestart()
        if (controller.settings.appearance != appearance) recreate()
    }

    override fun onStart() {
        super.onStart()
        controller.refreshAccessory()
        controller.startDiscovery()
        scope.launch { controller.wifiMacs.collect(::renderWifi) }
        scope.launch {
            // The display opens by itself only when a stream *starts* while this screen is shown.
            // Coming back here (Back from the display, relaunching the app) never reopens it.
            var previous: SessionState? = null
            controller.state.collect { state ->
                render(state)
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
        dismissPairing()
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
     * `adb shell am start --activity-clear-top -n dev.tab2mac.receiver/.ui.MainActivity --ez disconnect true`.
     */
    private fun handleAutomation(intent: Intent?) {
        if (!BuildConfig.DEBUG || intent == null) return
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

    private fun render(state: ReceiverState) {
        val text = StatusText.of(state)
        status.text = text.headline
        statusDetail.text = text.detail
        connect.setText(if (state.active) R.string.disconnect else R.string.connect)
        openStream.isEnabled = state.session is SessionState.Streaming || state.session is SessionState.Suspended
        // The prompt appears once the code exists: after both nonces are known (§6).
        renderPairing((state.session as? SessionState.Pairing)?.takeIf { it.code != null })
        val directText = DirectText.of(state.direct, state.directKeyMac)
        direct.setText(if (directText.inProgress) R.string.direct_cancel else R.string.direct_start)
        direct.isEnabled = directText.inProgress || state.directKeyMac != null
        directStatus.text = directText.status
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
        }
    }

    /** One row per Mac on the network: name, pairing status, Connect (or Pair again). */
    private fun renderWifi(macs: List<WifiMac>) {
        wifiList.removeAllViews()
        wifiHint.setText(if (macs.isEmpty()) R.string.wifi_searching else R.string.wifi_pick)
        val padding = (8 * resources.displayMetrics.density).toInt()
        for (item in macs) {
            val status = getString(
                when {
                    item.identityChanged -> R.string.wifi_status_changed
                    item.paired -> R.string.wifi_status_paired
                    else -> R.string.wifi_status_new
                },
            )
            val label = TextView(this).apply {
                text = SpannableStringBuilder(item.mac.displayName)
                    .apply { setSpan(StyleSpan(Typeface.BOLD), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE) }
                    .append('\n')
                    .append(status)
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            }
            val button = Button(this).apply {
                setText(if (item.identityChanged) R.string.wifi_pair_again else R.string.wifi_connect)
                setOnClickListener {
                    openStreamWhenActive = false
                    // Pair again = forget the old pin first, so the Mac's new identity can pair.
                    if (item.identityChanged) controller.forgetMac(item.mac.id)
                    controller.connectWifi(item.mac)
                }
            }
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, padding, 0, padding)
                addView(label)
                addView(button)
                if (item.paired) {
                    setOnLongClickListener {
                        confirmForget(item)
                        true
                    }
                }
            }
            wifiList.addView(row)
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

    /**
     * §6 pairing prompt: the Mac's name and the 6-digit code, "Codes match" (PAIRING `confirmed`)
     * or Cancel (`rejected`, GOODBYE `user`). After confirming, it waits for the Mac's user.
     */
    private fun renderPairing(pairing: SessionState.Pairing?) {
        if (pairing == pairingShown) return
        dismissPairing()
        if (pairing == null) return
        pairingShown = pairing
        val code = PairingCode.display(pairing.code ?: return)
        val explanation = if (pairing.confirmed) getString(R.string.pairing_waiting, pairing.macName) else getString(R.string.pairing_compare)
        val message = SpannableStringBuilder(code)
            .apply {
                setSpan(RelativeSizeSpan(2.5f), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                setSpan(StyleSpan(Typeface.BOLD), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            .append("\n\n")
            .append(explanation)
        val builder = AlertDialog.Builder(this)
            .setTitle(getString(R.string.pairing_title, pairing.macName))
            .setMessage(message)
            .setCancelable(false)
            .setNegativeButton(R.string.cancel) { _, _ -> controller.rejectPairing() }
        if (!pairing.confirmed) builder.setPositiveButton(R.string.pairing_match) { _, _ -> controller.confirmPairing() }
        pairingDialog = builder.show()
    }

    private fun dismissPairing() {
        pairingDialog?.setOnDismissListener(null)
        pairingDialog?.dismiss()
        pairingDialog = null
        pairingShown = null
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
        private const val STATE_OPEN_STREAM_WHEN_ACTIVE = "openStreamWhenActive"
        private const val REQUEST_DIRECT_PERMISSIONS = 1
    }
}
