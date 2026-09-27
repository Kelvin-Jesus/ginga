package dev.ginga.receiver.device

import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.hardware.display.DisplayManager
import android.os.Build
import android.provider.Settings
import android.view.Display
import android.view.InputDevice
import android.view.MotionEvent
import android.view.Surface
import dev.ginga.decoder.CodecCatalog
import dev.ginga.decoder.DecoderConfigPlanner
import dev.ginga.protocol.Feature
import dev.ginga.protocol.Hello
import dev.ginga.protocol.Orientation
import dev.ginga.protocol.TransportKind
import dev.ginga.protocol.VersionNegotiation
import dev.ginga.receiver.AppLog
import dev.ginga.receiver.BuildConfig
import dev.ginga.receiver.settings.ReceiverSettings
import kotlin.math.roundToInt

/** Builds HELLO from what this device really has (display, decoders, touch and stylus). */
class DeviceCapabilities(context: Context, private val settings: ReceiverSettings) {
    private val appContext = context.applicationContext

    /** Can this tablet host a §6b direct link: its own Wi‑Fi network plus a Bluetooth LE peripheral. */
    private val canHostDirectLink: Boolean by lazy {
        val packages = appContext.packageManager
        packages.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE) && packages.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)
    }

    /** Decoder capabilities are fixed for the device; enumerating MediaCodecList is slow. */
    private val decoders: List<Hello.Decoder> by lazy { queryDecoders() }

    /**
     * HELLO for a new connection over [transport]; [resumeSession] is the token of the previous
     * WELCOME.
     */
    fun hello(resumeSession: String?, transport: TransportKind): Hello = Hello(
        versions = VersionNegotiation.SUPPORTED,
        app = Hello.App(APP_NAME, BuildConfig.VERSION_NAME),
        device = Hello.Device(Build.MANUFACTURER, Build.MODEL, Build.VERSION.RELEASE, settings.deviceId, deviceName()),
        display = display(),
        decoders = decoders,
        input = input(),
        transport = transport,
        features = features(transport),
        resume = resumeSession?.let(Hello::Resume),
    ).also { AppLog.i("hello.built", "transport" to transport, "display" to it.display, "decoders" to it.decoders.map { d -> d.mime }) }

    /**
     * The name the owner gave this device in Settings › About ("Galaxy S25 Ultra" by default on
     * Galaxy devices), so the Mac can show it instead of a model number. No permission needed.
     */
    private fun deviceName(): String? =
        runCatching { Settings.Global.getString(appContext.contentResolver, Settings.Global.DEVICE_NAME) }
            .getOrNull()
            ?.let(::cleanDeviceName)

    /**
     * What this receiver supports: clock sync, reports, pause, drawing the pointer itself
     * (`cursor`, §3.3b), forwarding a hardware keyboard (`keyboard`, §3.3c); over Wi‑Fi also
     * `pairing` (§6), which the Mac requires there.
     */
    fun features(transport: TransportKind): List<Feature> =
        listOf(Feature.CLOCK_SYNC, Feature.RECEIVER_REPORT, Feature.PAUSE, Feature.CURSOR, Feature.KEYBOARD) +
            (if (canHostDirectLink) listOf(Feature.DIRECT_LINK) else emptyList()) +
            if (transport == TransportKind.WIFI_TLS) listOf(Feature.PAIRING) else emptyList()

    /** The panel in its current orientation; physical pixels and physical density. */
    fun display(): Hello.Display {
        val display = defaultDisplay()
        val mode = display?.mode
        val rotationDegrees = when (display?.rotation) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
        val metrics = appContext.resources.displayMetrics
        val naturalWidth = mode?.physicalWidth ?: metrics.widthPixels
        val naturalHeight = mode?.physicalHeight ?: metrics.heightPixels
        val swapped = rotationDegrees == 90 || rotationDegrees == 270
        val refreshRates = display?.supportedModes
            ?.filter { mode == null || (it.physicalWidth == mode.physicalWidth && it.physicalHeight == mode.physicalHeight) }
            ?.map { it.refreshRate.roundToInt().toDouble() }
            ?.distinct()
            ?.sorted()
            .orEmpty()
            .ifEmpty { listOf(60.0) }
        val physicalDpi = (metrics.xdpi + metrics.ydpi) / 2f
        return Hello.Display(
            widthPx = if (swapped) naturalHeight else naturalWidth,
            heightPx = if (swapped) naturalWidth else naturalHeight,
            densityDpi = if (physicalDpi in 100f..1000f) physicalDpi.roundToInt() else metrics.densityDpi,
            refreshRates = refreshRates,
            rotation = rotationDegrees,
            wideColor = display?.isWideColorGamut,
        )
    }

    /** Landscape or portrait, from the current configuration. */
    fun orientation(configuration: Configuration = appContext.resources.configuration): Orientation =
        if (configuration.orientation == Configuration.ORIENTATION_PORTRAIT) Orientation.PORTRAIT else Orientation.LANDSCAPE

    private fun defaultDisplay(): Display? =
        appContext.getSystemService(DisplayManager::class.java)?.getDisplay(Display.DEFAULT_DISPLAY)

    private fun queryDecoders(): List<Hello.Decoder> {
        val display = display()
        val width = maxOf(display.widthPx, display.heightPx)
        val height = minOf(display.widthPx, display.heightPx)
        return listOf(DecoderConfigPlanner.MIME_HEVC, DecoderConfigPlanner.MIME_AVC).mapNotNull { mime ->
            try {
                CodecCatalog.capability(mime, width, height)?.let {
                    AppLog.i("decoder.capability", "mime" to mime, "codec" to it.codecName, "lowLatency" to it.lowLatency, "maxFps" to it.maxFps)
                    Hello.Decoder(it.mimeType, it.profiles, it.maxWidth, it.maxHeight, it.maxFps, it.lowLatency)
                }
            } catch (e: RuntimeException) {
                AppLog.e("decoder.capability-failed", e, "mime" to mime)
                null
            }
        }
    }

    private fun input(): Hello.Input {
        val packages = appContext.packageManager
        val maxPointers = when {
            packages.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN_MULTITOUCH_JAZZHAND) -> 10
            packages.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN_MULTITOUCH_DISTINCT) -> 2
            else -> 1
        }
        val styluses = InputDevice.getDeviceIds().toList()
            .mapNotNull { InputDevice.getDevice(it) }
            .filter { it.supportsSource(InputDevice.SOURCE_STYLUS) }
        val stylus = styluses.takeIf { it.isNotEmpty() }?.let { devices ->
            fun has(axis: Int) = devices.any { it.getMotionRange(axis, InputDevice.SOURCE_STYLUS) != null }
            Hello.Input.Stylus(
                pressure = has(MotionEvent.AXIS_PRESSURE),
                tilt = has(MotionEvent.AXIS_TILT),
                hover = true,
                buttons = 1,
            )
        }
        return Hello.Input(touch = Hello.Input.Touch(maxPointers), stylus = stylus)
    }

    private companion object {
        const val APP_NAME = "Ginga for Android"
    }
}

/** A device name as HELLO carries it: no control characters, whitespace collapsed, at most 64 characters; null if empty. */
internal fun cleanDeviceName(raw: String): String? =
    raw.filterNot { it.isISOControl() }.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        .take(64).ifEmpty { null }

