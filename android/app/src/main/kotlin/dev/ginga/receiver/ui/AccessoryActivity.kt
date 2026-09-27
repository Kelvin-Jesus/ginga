package dev.ginga.receiver.ui

import android.app.Activity
import android.content.Intent
import android.hardware.usb.UsbManager
import android.os.Bundle
import dev.ginga.receiver.AppLog

/**
 * Target of `USB_ACCESSORY_ATTACHED` for the Mac's accessory (`res/xml/accessory_filter.xml`).
 * Shows nothing: it brings [MainActivity] to the front (closing a stream screen above it), which
 * connects over the accessory and opens the display. Launched from Recents it only opens the
 * app, since that intent is a stale attach.
 */
class AccessoryActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val fromHistory = intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        val attached = intent.action == UsbManager.ACTION_USB_ACCESSORY_ATTACHED && !fromHistory && savedInstanceState == null
        AppLog.i("accessory.intent", "attached" to attached, "fromHistory" to fromHistory)
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(MainActivity.EXTRA_ACCESSORY_ATTACHED, attached),
        )
        finish()
    }
}
