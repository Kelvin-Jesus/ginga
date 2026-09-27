package dev.tab2mac.receiver.ui

import android.app.Activity
import android.os.Bundle
import android.widget.Button
import dev.tab2mac.receiver.R
import dev.tab2mac.receiver.Tab2MacApplication
import dev.tab2mac.receiver.settings.ReceiverSettings
import dev.tab2mac.receiver.ui.widget.SegmentedControl
import dev.tab2mac.receiver.ui.widget.SwitchRow

/**
 * Ajustes: what applies at once is a toggle; the refresh rate and the appearance are Segmented
 * controls. Changing the appearance recreates the screen (and the home screen when it comes back).
 */
class SettingsActivity : Activity() {
    private lateinit var settings: ReceiverSettings

    override fun onCreate(savedInstanceState: Bundle?) {
        settings = (application as Tab2MacApplication).controller.settings
        settings.appearance.apply(this)
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)
        findViewById<Button>(R.id.back).setOnClickListener { finish() }

        findViewById<SwitchRow>(R.id.auto_reconnect).apply {
            isChecked = settings.autoReconnect
            onCheckedChange = { settings.autoReconnect = it }
        }
        findViewById<SwitchRow>(R.id.fast_decoder).apply {
            isChecked = settings.fastDecoder
            onCheckedChange = { settings.fastDecoder = it }
        }
        findViewById<SwitchRow>(R.id.show_diagnostics).apply {
            isChecked = settings.showDiagnostics
            onCheckedChange = { settings.showDiagnostics = it }
        }
        findViewById<SegmentedControl>(R.id.refresh).apply {
            setOptions(
                RefreshChoice.entries.map { getString(it.labelRes) },
                RefreshChoice.of(settings.preferredRefreshRate).ordinal,
            )
            onChange = { index -> settings.preferredRefreshRate = RefreshChoice.entries[index].hz }
        }
        findViewById<SegmentedControl>(R.id.appearance).apply {
            val choices = Appearance.entries
            setOptions(choices.map { getString(it.labelRes) }, choices.indexOf(settings.appearance))
            onChange = { index ->
                settings.appearance = choices[index]
                // Let the thumb land before the screen is rebuilt in the new theme.
                postDelayed({ if (!isFinishing) recreate() }, Motion.DUR_UI)
            }
        }
    }
}

/** Taxa preferida: the Mac decides (null), 60 Hz or 120 Hz. */
enum class RefreshChoice(val hz: Int?, val labelRes: Int) {
    MAC(null, R.string.refresh_mac),
    HZ_60(60, R.string.refresh_60),
    HZ_120(120, R.string.refresh_120),
    ;

    companion object {
        fun of(hz: Int?): RefreshChoice = entries.firstOrNull { it.hz == hz } ?: MAC
    }
}
