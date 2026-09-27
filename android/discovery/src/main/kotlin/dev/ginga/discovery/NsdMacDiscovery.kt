package dev.ginga.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.util.Log
import java.net.InetAddress
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * [MacDiscovery] with `NsdManager` (the system's mDNS service: no multicast lock needed). Found
 * services are resolved with `registerServiceInfoCallback` on API 34+, which also follows address
 * changes and loss, or one at a time with `resolveService` before that (older versions refuse
 * concurrent resolves). Everything is callback-driven; nothing polls.
 */
class NsdMacDiscovery(context: Context) : MacDiscovery {
    private val nsd = context.applicationContext.getSystemService(NsdManager::class.java)
    private val executor: Executor = Executors.newSingleThreadExecutor { Thread(it, "ginga-nsd").apply { isDaemon = true } }
    private val lock = Any()
    private val found = LinkedHashMap<String, DiscoveredMac>()
    private val infoCallbacks = HashMap<String, NsdManager.ServiceInfoCallback>()
    private val pendingResolves = ArrayDeque<NsdServiceInfo>()
    private var resolving = false
    private val mutableMacs = MutableStateFlow<List<DiscoveredMac>>(emptyList())

    /** The listener of the current browse; a new one each time, as NsdManager requires. */
    private var listener: NsdManager.DiscoveryListener? = null

    override val macs: StateFlow<List<DiscoveredMac>> = mutableMacs.asStateFlow()

    override fun start() {
        val manager = nsd ?: return
        val browse = synchronized(lock) {
            if (listener != null) return
            Listener().also { listener = it }
        }
        manager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, browse)
    }

    override fun stop() {
        val manager = nsd ?: return
        val (browse, callbacks) = synchronized(lock) {
            val browse = listener ?: return
            listener = null
            found.clear()
            pendingResolves.clear()
            mutableMacs.value = emptyList()
            browse to infoCallbacks.values.toList().also { infoCallbacks.clear() }
        }
        try {
            manager.stopServiceDiscovery(browse)
        } catch (e: IllegalArgumentException) {
            log("discovery.stop-ignored error=\"${e.message}\"")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            callbacks.forEach { callback ->
                try {
                    manager.unregisterServiceInfoCallback(callback)
                } catch (e: IllegalArgumentException) {
                    log("resolve.unregister-ignored error=\"${e.message}\"")
                }
            }
        }
    }

    private inner class Listener : NsdManager.DiscoveryListener {
        private val current: Boolean get() = synchronized(lock) { listener === this }

        override fun onDiscoveryStarted(serviceType: String) {
            log("discovery.started type=$serviceType")
        }

        override fun onDiscoveryStopped(serviceType: String) {
            log("discovery.stopped type=$serviceType")
        }

        override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
            log("discovery.start-failed type=$serviceType code=$errorCode")
            synchronized(lock) { if (listener === this) listener = null }
        }

        override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
            log("discovery.stop-failed type=$serviceType code=$errorCode")
        }

        override fun onServiceFound(serviceInfo: NsdServiceInfo) {
            if (!current) return
            log("service.found name=\"${serviceInfo.serviceName}\"")
            resolve(serviceInfo)
        }

        override fun onServiceLost(serviceInfo: NsdServiceInfo) {
            log("service.lost name=\"${serviceInfo.serviceName}\"")
            forget(serviceInfo.serviceName)
        }
    }

    private fun resolve(service: NsdServiceInfo) {
        val manager = nsd ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val callback = object : NsdManager.ServiceInfoCallback {
                override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {
                    log("resolve.failed name=\"${service.serviceName}\" code=$errorCode")
                }

                override fun onServiceUpdated(serviceInfo: NsdServiceInfo) {
                    remember(serviceInfo, serviceInfo.hostAddresses)
                }

                override fun onServiceLost() {
                    forget(service.serviceName)
                }

                override fun onServiceInfoCallbackUnregistered() = Unit
            }
            synchronized(lock) {
                if (service.serviceName in infoCallbacks) return
                infoCallbacks[service.serviceName] = callback
            }
            manager.registerServiceInfoCallback(service, executor, callback)
        } else {
            synchronized(lock) {
                pendingResolves.addLast(service)
                if (resolving) return
                resolving = true
            }
            resolveNextLegacy(manager)
        }
    }

    /** Before API 34: one `resolveService` at a time. */
    private fun resolveNextLegacy(manager: NsdManager) {
        val next = synchronized(lock) {
            pendingResolves.removeFirstOrNull() ?: run {
                resolving = false
                return
            }
        }
        @Suppress("DEPRECATION")
        manager.resolveService(
            next,
            object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    log("resolve.failed name=\"${serviceInfo.serviceName}\" code=$errorCode")
                    resolveNextLegacy(manager)
                }

                override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                    @Suppress("DEPRECATION")
                    remember(serviceInfo, listOfNotNull(serviceInfo.host))
                    resolveNextLegacy(manager)
                }
            },
        )
    }

    private fun remember(info: NsdServiceInfo, addresses: List<InetAddress>) {
        val mac = DiscoveredMac(info.serviceName, addresses, info.port, TxtRecord.parse(info.attributes))
        log("service.resolved name=\"${mac.serviceName}\" port=${mac.port} addresses=${addresses.size} pv=${mac.txt.protocolVersion}")
        synchronized(lock) {
            if (listener == null) return
            found[mac.serviceName] = mac
            mutableMacs.value = found.values.toList()
        }
    }

    private fun forget(serviceName: String) {
        synchronized(lock) {
            if (found.remove(serviceName) != null) mutableMacs.value = found.values.toList()
        }
    }

    private fun log(message: String) {
        Log.i(TAG, message)
    }

    private companion object {
        const val TAG = "Ginga/discovery"
    }
}
