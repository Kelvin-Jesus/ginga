package dev.ginga.receiver.direct

import android.annotation.SuppressLint
import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import dev.ginga.receiver.AppLog

/**
 * The tablet's own network as a local-only hotspot (§6b fallback): the system picks the name,
 * passphrase and band; no internet sharing. It lasts while the reservation is held. Callbacks on
 * the main thread.
 */
class LocalHotspotNetwork(context: Context) : DirectNetwork {
    override val kind: String = "local-only hotspot"

    private val wifi: WifiManager? = context.applicationContext.getSystemService(WifiManager::class.java)
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var stopped = false

    @SuppressLint("MissingPermission") // requested by MainActivity before a direct link starts
    override fun start(name: String, passphrase: String, onUp: (String, String) -> Unit, onFailed: (String) -> Unit, onLost: (String) -> Unit) {
        val wifi = wifi ?: return onFailed("Wi‑Fi unavailable")
        stopped = false
        try {
            wifi.startLocalOnlyHotspot(
                object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(started: WifiManager.LocalOnlyHotspotReservation) {
                        if (stopped) return started.close()
                        reservation = started
                        val config = started.softApConfiguration
                        val ssid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            config.wifiSsid?.bytes?.decodeToString()
                        } else {
                            @Suppress("DEPRECATION")
                            config.ssid
                        }
                        val psk = config.passphrase
                        if (ssid == null || psk == null) {
                            started.close()
                            return onFailed("the hotspot has no passphrase")
                        }
                        AppLog.i("direct.hotspot-up")
                        onUp(ssid, psk)
                    }

                    override fun onStopped() = onLost("stopped by the system")

                    override fun onFailed(reason: Int) = onFailed("hotspot failed ($reason)")
                },
                Handler(Looper.getMainLooper()),
            )
        } catch (e: SecurityException) {
            onFailed("no permission for a hotspot")
        } catch (e: IllegalStateException) {
            onFailed("a hotspot is already running")
        }
    }

    override fun stop() {
        stopped = true
        reservation?.close()
        reservation = null
    }
}
