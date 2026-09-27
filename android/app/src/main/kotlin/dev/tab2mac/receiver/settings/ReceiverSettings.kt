package dev.tab2mac.receiver.settings

import android.content.Context
import android.content.SharedPreferences
import dev.tab2mac.receiver.ui.Appearance
import java.util.UUID

/** User settings and the app-scoped device id, in SharedPreferences. */
class ReceiverSettings(context: Context) {
    private val preferences: SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** Reconnect with backoff after the connection drops (0.25 → 5 s). */
    var autoReconnect: Boolean
        get() = preferences.getBoolean(KEY_AUTO_RECONNECT, true)
        set(value) = preferences.edit().putBoolean(KEY_AUTO_RECONNECT, value).apply()

    /**
     * 60 or 120 Hz, asked of the Mac after WELCOME as a preference (its power setting decides,
     * 60 Hz by default); null — the default — lets the Mac decide. The panel follows the stream.
     */
    var preferredRefreshRate: Int?
        get() = preferences.getInt(KEY_REFRESH, 0).takeIf { it == 60 || it == 120 }
        set(value) = preferences.edit().putInt(KEY_REFRESH, value ?: 0).apply()

    /**
     * Run the decoder with 2× clock headroom (`operating-rate` = 2 × fps): lower decode latency
     * for more power. Off by default.
     */
    var fastDecoder: Boolean
        get() = preferences.getBoolean(KEY_FAST_DECODER, false)
        set(value) = preferences.edit().putBoolean(KEY_FAST_DECODER, value).apply()

    /** The diagnostics overlay; off by default (it samples every frame's timing while shown). */
    var showDiagnostics: Boolean
        get() = preferences.getBoolean(KEY_DIAGNOSTICS, false)
        set(value) = preferences.edit().putBoolean(KEY_DIAGNOSTICS, value).apply()

    /** Sistema, Claro, Escuro or Black espacial; Sistema by default. */
    var appearance: Appearance
        get() = Appearance.fromStorage(preferences.getString(KEY_APPEARANCE, null))
        set(value) = preferences.edit().putString(KEY_APPEARANCE, value.storageValue).apply()

    /**
     * HELLO `device.id`: a stable, app-scoped random id (§3.1). The Mac derives the virtual
     * display's serial number from it, so it must never change for this install.
     */
    val deviceId: String
        get() = synchronized(this) {
            preferences.getString(KEY_DEVICE_ID, null) ?: UUID.randomUUID().toString().replace("-", "").take(16).also {
                preferences.edit().putString(KEY_DEVICE_ID, it).apply()
            }
        }

    private companion object {
        const val FILE = "tab2mac"
        const val KEY_AUTO_RECONNECT = "auto_reconnect"
        const val KEY_REFRESH = "preferred_refresh_hz"
        const val KEY_DIAGNOSTICS = "show_diagnostics"
        const val KEY_FAST_DECODER = "fast_decoder"
        const val KEY_DEVICE_ID = "device_id"
        const val KEY_APPEARANCE = "appearance"
    }
}
