package dev.ginga.receiver.direct

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.wifi.WifiInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pGroup
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Looper
import dev.ginga.receiver.AppLog

/**
 * The tablet's own network as a Wi‑Fi Direct autonomous group (§6b): this tablet is the group
 * owner, on 5 GHz, with our network name and a passphrase new for every link, not persisted. The
 * Mac joins it like an access point. Callbacks on the main thread.
 */
class WifiDirectNetwork(context: Context) : DirectNetwork {
    override val kind: String = "Wi‑Fi Direct"

    private val context = context.applicationContext
    private val manager: WifiP2pManager? = this.context.getSystemService(WifiP2pManager::class.java)
    private var channel: WifiP2pManager.Channel? = null
    private var receiver: BroadcastReceiver? = null
    private var up = false

    @SuppressLint("MissingPermission") // requested by MainActivity before a direct link starts
    override fun start(name: String, passphrase: String, onUp: (String, String) -> Unit, onFailed: (String) -> Unit, onLost: (String) -> Unit) {
        val manager = manager ?: return onFailed("Wi‑Fi Direct unavailable")
        val channel = manager.initialize(context, Looper.getMainLooper()) { if (up) onLost("Wi‑Fi Direct framework went away") }
            ?: return onFailed("Wi‑Fi Direct unavailable")
        this.channel = channel
        val watcher = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val group = intent.groupExtra()
                if (!up && group != null && group.isGroupOwner && group.networkName == name) {
                    up = true
                    AppLog.i("direct.group-up", "frequencyMhz" to group.frequency, "interface" to group.`interface`)
                    onUp(group.networkName, group.passphrase ?: passphrase)
                } else if (up && (group == null || group.networkName != name)) {
                    up = false
                    onLost("the group was removed")
                }
            }
        }
        receiver = watcher
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Context.RECEIVER_NOT_EXPORTED else 0
        context.registerReceiver(watcher, IntentFilter(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION), flags)
        // On the channel of the tablet's own 5 GHz Wi‑Fi if it has one: one channel for both
        // links, so the radio doesn't hop between them (multi-channel concurrency costs latency
        // and power). Otherwise, or if the driver refuses, any 5 GHz channel.
        val staFrequency = currentWifiFrequency()?.takeIf { it in 5_000..5_900 }
        fun create(frequency: Int?) {
            val config = WifiP2pConfig.Builder()
                .setNetworkName(name)
                .setPassphrase(passphrase)
                .apply { if (frequency != null) setGroupOperatingFrequency(frequency) else setGroupOperatingBand(WifiP2pConfig.GROUP_OWNER_BAND_5GHZ) }
                .enablePersistentMode(false)
                .build()
            try {
                manager.createGroup(
                    channel, config,
                    object : WifiP2pManager.ActionListener {
                        override fun onSuccess() = AppLog.i("direct.group-requested", "frequencyMhz" to frequency)

                        override fun onFailure(reason: Int) {
                            if (frequency != null) create(null) else onFailed("createGroup failed (${reasonName(reason)})")
                        }
                    },
                )
            } catch (e: SecurityException) {
                onFailed("no permission for Wi‑Fi Direct")
            }
        }
        create(staFrequency)
    }

    /** The frequency of the Wi‑Fi network the tablet is on, if any (MHz). */
    private fun currentWifiFrequency(): Int? {
        val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return null
        val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork) ?: return null
        return (capabilities.transportInfo as? WifiInfo)?.frequency?.takeIf { it > 0 }
    }

    override fun stop() {
        val manager = manager
        val channel = channel
        up = false
        receiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
            }
        }
        receiver = null
        if (manager != null && channel != null) {
            manager.removeGroup(channel, null)
            channel.close()
        }
        this.channel = null
    }

    private fun reasonName(reason: Int) = when (reason) {
        WifiP2pManager.P2P_UNSUPPORTED -> "unsupported"
        WifiP2pManager.BUSY -> "busy"
        WifiP2pManager.ERROR -> "error"
        else -> reason.toString()
    }

    private fun Intent.groupExtra(): WifiP2pGroup? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_GROUP, WifiP2pGroup::class.java)
        } else {
            legacyGroupExtra()
        }

    @Suppress("DEPRECATION")
    private fun Intent.legacyGroupExtra(): WifiP2pGroup? = getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_GROUP)
}
