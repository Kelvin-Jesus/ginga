package dev.tab2mac.transport

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbAccessory
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.ParcelFileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The Mac as a USB accessory, through [UsbManager]: finds it, asks the user for access, builds an
 * [AccessoryTransport] over it, and reports when it is unplugged. The decisions live in pure,
 * unit-tested code ([TransportSelector], [AccessoryIdentity], [AccessoryTransport]); this class
 * only adapts the framework. Nothing here polls: attach arrives as an activity intent, detach
 * and permission results as broadcasts.
 */
class UsbAccessories(context: Context) {
    private val context = context.applicationContext
    private val usb: UsbManager? = this.context.getSystemService(UsbManager::class.java)

    /** The Mac's accessory, if it is attached. */
    fun find(): UsbAccessory? = attached().firstOrNull { AccessoryIdentity.matches(it.info()) }

    /** Direct USB when the Mac's accessory is attached (asking for access if needed), ADB otherwise. */
    fun choose(): TransportChoice<UsbAccessory> = TransportSelector.choose(attached(), { it.info() }, ::hasPermission)

    fun hasPermission(accessory: UsbAccessory): Boolean = usb?.hasPermission(accessory) == true

    /**
     * Shows Android's "Allow Tab2Mac to access …?" dialog; [onResult] runs on the main thread
     * once the dialog closes, however it closes (Android always answers). Granted at once, without
     * a dialog, when access was already given.
     */
    fun requestPermission(accessory: UsbAccessory, onResult: (granted: Boolean) -> Unit) {
        val usb = usb ?: return onResult(false)
        val action = context.packageName + PERMISSION_ACTION_SUFFIX
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                unregister(this)
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                TransportLog.i("accessory.permission", "granted" to granted)
                onResult(granted)
            }
        }
        register(receiver, IntentFilter(action))
        // Mutable so that UsbManager can add its extras; explicit (package set), as Android 14+ requires.
        val request = Intent(action).setPackage(context.packageName)
        val pending = PendingIntent.getBroadcast(context, 0, request, PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        TransportLog.i("accessory.permission-requested", "model" to accessory.model)
        usb.requestPermission(accessory, pending)
    }

    /**
     * A transport over the Mac's accessory; it opens the device when [Transport.connect] is called
     * and, with [autoReconnect], again after every link while the accessory stays attached.
     */
    fun transport(autoReconnect: Boolean): AccessoryTransport =
        AccessoryTransport(UsbAccessoryOpener(usb), AccessoryTransport.options(autoReconnect))

    /**
     * Calls [onDetached] on the main thread when the Mac's accessory is unplugged, until the
     * returned handle is closed.
     */
    fun watchDetach(onDetached: () -> Unit): AutoCloseable {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val accessory = intent.accessoryExtra()
                if (accessory != null && !AccessoryIdentity.matches(accessory.info())) return
                TransportLog.i("accessory.detached")
                onDetached()
            }
        }
        register(receiver, IntentFilter(UsbManager.ACTION_USB_ACCESSORY_DETACHED))
        val closed = AtomicBoolean(false)
        return AutoCloseable { if (closed.compareAndSet(false, true)) unregister(receiver) }
    }

    private fun attached(): List<UsbAccessory> = usb?.accessoryList?.toList().orEmpty()

    /** Only the system (detach) and this app (the permission PendingIntent) can reach these receivers. */
    private fun register(receiver: BroadcastReceiver, filter: IntentFilter) {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Context.RECEIVER_NOT_EXPORTED else 0
        context.registerReceiver(receiver, filter, flags)
    }

    private fun unregister(receiver: BroadcastReceiver) {
        try {
            context.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
            // Already unregistered.
        }
    }

    private companion object {
        const val PERMISSION_ACTION_SUFFIX = ".USB_ACCESSORY_PERMISSION"
    }
}

/**
 * Opens the Mac's accessory: [LinkAttempt.Gone] when it is no longer attached or access was not
 * granted (retrying can't help), [LinkAttempt.Failed] when the device node is busy (the previous
 * descriptor is still being released).
 */
internal class UsbAccessoryOpener(private val usb: UsbManager?) : LinkOpener {
    override fun open(): LinkAttempt {
        val usb = usb ?: return LinkAttempt.Gone("USB is not available")
        // A fresh instance each time: UsbAccessory.equals() reads the serial, which needs access.
        val accessory = usb.accessoryList?.firstOrNull { AccessoryIdentity.matches(it.info()) }
            ?: return LinkAttempt.Gone(AccessoryTransport.DETACHED)
        if (!usb.hasPermission(accessory)) return LinkAttempt.Gone("no access to the USB accessory")
        val descriptor: ParcelFileDescriptor? = try {
            usb.openAccessory(accessory)
        } catch (e: IllegalArgumentException) {
            // "no accessory attached" / "does not match current accessory": unplugged meanwhile.
            return LinkAttempt.Gone(e.message ?: AccessoryTransport.DETACHED)
        } catch (e: SecurityException) {
            return LinkAttempt.Gone(e.message ?: "no access to the USB accessory")
        }
        if (descriptor == null) return LinkAttempt.Failed("could not open the USB accessory (busy)")
        TransportLog.i("accessory.opened", "manufacturer" to accessory.manufacturer, "model" to accessory.model)
        return LinkAttempt.Opened(ParcelFileDescriptorLink(descriptor))
    }
}

/**
 * The accessory's bulk endpoints as streams over one descriptor. [close] closes the descriptor,
 * which also wakes a thread blocked in a read or write on it (Android signals such threads).
 */
internal class ParcelFileDescriptorLink(private val descriptor: ParcelFileDescriptor) : ByteLink {
    override val input: InputStream = FileInputStream(descriptor.fileDescriptor)
    override val output: OutputStream = FileOutputStream(descriptor.fileDescriptor)

    override fun close() {
        descriptor.close()
    }
}

internal fun UsbAccessory.info(): AccessoryInfo = AccessoryInfo(manufacturer, model, version)

private fun Intent.accessoryExtra(): UsbAccessory? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        getParcelableExtra(UsbManager.EXTRA_ACCESSORY, UsbAccessory::class.java)
    } else {
        legacyAccessoryExtra()
    }

/** The typed getter exists from API 33 but is unreliable there; AndroidX also waits for 34. */
@Suppress("DEPRECATION")
private fun Intent.legacyAccessoryExtra(): UsbAccessory? = getParcelableExtra(UsbManager.EXTRA_ACCESSORY)
