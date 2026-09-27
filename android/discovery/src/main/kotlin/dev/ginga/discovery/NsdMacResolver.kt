package dev.ginga.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.util.Log
import java.net.InetAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Resolves one Mac's `_ginga._tcp` service on demand, right before a connection attempt: the
 * Mac's Wi‑Fi port is chosen by the system each time Ginga starts (PROTOCOL.md §6), so an
 * address found earlier goes stale. A resolve is one mDNS query; nothing runs between attempts.
 */
class NsdMacResolver(context: Context, private val serviceName: String) {
    private val nsd = context.applicationContext.getSystemService(NsdManager::class.java)

    /** Blocks for up to [timeoutMs]: the Mac's current addresses, port and TXT, or null. */
    fun resolve(timeoutMs: Long = 3_000): DiscoveredMac? {
        val manager = nsd ?: return null
        val request = NsdServiceInfo().apply {
            serviceName = this@NsdMacResolver.serviceName
            serviceType = SERVICE_TYPE
        }
        val found = AtomicReference<DiscoveredMac?>()
        val done = CountDownLatch(1)
        fun accept(info: NsdServiceInfo, addresses: List<InetAddress>) {
            if (addresses.isEmpty() || info.port <= 0) return
            found.compareAndSet(null, DiscoveredMac(info.serviceName, addresses, info.port, TxtRecord.parse(info.attributes)))
            done.countDown()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val callback = object : NsdManager.ServiceInfoCallback {
                override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {
                    log("resolve.failed name=\"$serviceName\" code=$errorCode")
                    done.countDown()
                }

                override fun onServiceUpdated(serviceInfo: NsdServiceInfo) = accept(serviceInfo, serviceInfo.hostAddresses)

                override fun onServiceLost() = Unit

                override fun onServiceInfoCallbackUnregistered() = Unit
            }
            try {
                manager.registerServiceInfoCallback(request, EXECUTOR, callback)
            } catch (e: IllegalArgumentException) {
                log("resolve.refused name=\"$serviceName\" error=\"${e.message}\"")
                return null
            }
            await(done, timeoutMs)
            try {
                manager.unregisterServiceInfoCallback(callback)
            } catch (_: IllegalArgumentException) {
                // Already gone.
            }
        } else {
            @Suppress("DEPRECATION")
            manager.resolveService(
                request,
                object : NsdManager.ResolveListener {
                    override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                        // FAILURE_ALREADY_ACTIVE while another resolve runs: the transport retries.
                        log("resolve.failed name=\"$serviceName\" code=$errorCode")
                        done.countDown()
                    }

                    override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                        @Suppress("DEPRECATION")
                        accept(serviceInfo, listOfNotNull(serviceInfo.host))
                    }
                },
            )
            await(done, timeoutMs)
        }
        val mac = found.get()
        log("resolve.done name=\"$serviceName\" port=${mac?.port} addresses=${mac?.addresses?.size}")
        return mac
    }

    private fun await(latch: CountDownLatch, timeoutMs: Long) {
        try {
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    private fun log(message: String) {
        Log.i(TAG, message)
    }

    private companion object {
        const val TAG = "Ginga/discovery"

        /** Callbacks of every resolver; they only record the answer. */
        val EXECUTOR: Executor = Executors.newSingleThreadExecutor { Thread(it, "ginga-nsd-resolve").apply { isDaemon = true } }
    }
}
