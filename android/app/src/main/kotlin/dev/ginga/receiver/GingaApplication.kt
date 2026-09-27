package dev.ginga.receiver

import android.app.Application
import dev.ginga.receiver.settings.ReceiverSettings

/** Holds the process-wide [ReceiverController]. */
class GingaApplication : Application() {
    /** Created on first use, then shared by every activity. */
    val controller: ReceiverController by lazy { ReceiverController(this, ReceiverSettings(this)) }

    override fun onCreate() {
        super.onCreate()
        AppLog.i("app.start", "version" to BuildConfig.VERSION_NAME)
    }
}
