package dev.ginga.receiver.stats

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import kotlin.math.abs

/**
 * Battery current and power, to compare settings on the tablet (diagnostics overlay only; read
 * at most twice a second while the overlay is visible).
 *
 * @property currentMa net battery current in mA: negative while discharging, positive while
 *   charging. While the tablet is plugged into the Mac, it shows the net charge current, not the
 *   app's consumption; unplug (Wi‑Fi, M7) or compare deltas.
 */
data class PowerSample(val currentMa: Int, val voltageMv: Int?, val charging: Boolean) {
    /** Battery power in watts (negative = draining), when the voltage is known. */
    val watts: Double? get() = voltageMv?.let { currentMa / 1_000.0 * it / 1_000.0 }
}

/** Reads [PowerSample]s from `BatteryManager`. */
class PowerMonitor(context: Context) {
    private val appContext = context.applicationContext
    private val battery = appContext.getSystemService(BatteryManager::class.java)

    /** The current reading, or null if the device doesn't report current. */
    fun sample(): PowerSample? {
        val manager = battery ?: return null
        val raw = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
        if (raw == Int.MIN_VALUE || raw == 0) return null
        return PowerSample(currentMa = normalizeToMilliamps(raw), voltageMv = voltageMv(), charging = manager.isCharging)
    }

    private fun voltageMv(): Int? {
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val sticky = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(null, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            appContext.registerReceiver(null, filter)
        }
        return sticky?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1)?.takeIf { it > 0 }
    }

    companion object {
        /**
         * `BATTERY_PROPERTY_CURRENT_NOW` is specified in µA, but some devices report mA. A tablet
         * with its screen on draws hundreds of mA, so small magnitudes are taken as mA already.
         */
        fun normalizeToMilliamps(raw: Int): Int = if (abs(raw) >= 20_000) raw / 1_000 else raw
    }
}
