package dev.ginga.receiver.adb

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dev.ginga.receiver.AppLog
import dev.ginga.receiver.GingaApplication

/**
 * Receives the adb loopback token from the Mac, which runs after `adb reverse`:
 * `am broadcast -a dev.ginga.action.LOOPBACK_TOKEN -n dev.ginga.receiver/.adb.LoopbackTokenReceiver --es token …`.
 * The manifest guards it with `android.permission.DUMP`, which only the adb shell holds, so no
 * other app can plant a token. A well-formed token is stored and wakes an adb session waiting to
 * reconnect; anything else is ignored. The token is never logged.
 */
class LoopbackTokenReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val controller = (context.applicationContext as GingaApplication).controller
        val accepted = controller.acceptLoopbackToken(intent.getStringExtra(EXTRA_TOKEN))
        AppLog.i("adb.token-received", "accepted" to accepted)
    }

    companion object {
        const val ACTION = "dev.ginga.action.LOOPBACK_TOKEN"
        const val EXTRA_TOKEN = "token"
    }
}
