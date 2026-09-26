package dev.tab2mac.receiver

import android.app.Application
import dev.tab2mac.receiver.settings.ReceiverSettings

/** Holds the process-wide [ReceiverController]. */
class Tab2MacApplication : Application() {
    /** Created on first use, then shared by every activity. */
    val controller: ReceiverController by lazy { ReceiverController(this, ReceiverSettings(this)) }

    override fun onCreate() {
        super.onCreate()
        AppLog.i("app.start", "version" to BuildConfig.VERSION_NAME)
    }
}
