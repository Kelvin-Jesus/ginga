package dev.tab2mac.receiver.ui

import android.app.Activity
import android.content.res.Configuration
import android.os.Bundle
import android.view.KeyEvent
import android.view.SurfaceHolder
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.ImageView
import android.widget.TextView
import dev.tab2mac.input.InputCapture
import dev.tab2mac.input.InputMapper
import dev.tab2mac.input.KeyboardCapture
import dev.tab2mac.input.NormalizationRect
import dev.tab2mac.protocol.Orientation
import dev.tab2mac.receiver.AppLog
import dev.tab2mac.receiver.R
import dev.tab2mac.receiver.ReceiverController
import dev.tab2mac.receiver.ReceiverState
import dev.tab2mac.receiver.Tab2MacApplication
import dev.tab2mac.receiver.session.SessionState
import dev.tab2mac.receiver.stats.DiagnosticsFormatter
import dev.tab2mac.receiver.stats.DiagnosticsSnapshot
import dev.tab2mac.receiver.stats.PowerMonitor
import dev.tab2mac.renderer.SurfaceFrameRate
import dev.tab2mac.renderer.VideoRect
import dev.tab2mac.renderer.VideoSurfaceLayout
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * The extended display: fullscreen and immersive, both orientations. Rotation is handled in place
 * (no recreation) and reported to the Mac as a CONFIGURE request.
 *
 * Power:
 * - video goes MediaCodec → this SurfaceView's Surface with no copy, GL or TextureView;
 * - the Surface votes for exactly the stream's frame rate, so a 60 fps stream lets the 120 Hz
 *   panel drop to 60 Hz;
 * - when the Surface goes away (Home, Back, screen off) the stream is paused on the Mac;
 * - the screen is kept on only while a stream is live and decoding;
 * - the diagnostics overlay (off by default) refreshes once a second, only while visible.
 */
class StreamActivity : Activity(), SurfaceHolder.Callback {
    private lateinit var controller: ReceiverController
    private lateinit var video: VideoSurfaceLayout
    private lateinit var overlay: TextView
    private lateinit var streamStatus: TextView
    private lateinit var cursorView: ImageView

    /** The stream's width in stream pixels (the scale of the pointer images). */
    private var streamWidth = 0
    private lateinit var input: InputCapture
    private lateinit var power: PowerMonitor
    private val mapper = InputMapper()
    private val keyboard = KeyboardCapture { down, usage, modifiers, time -> controller.sendKey(down, usage, modifiers, time) }
    private val scope = MainScope()
    private var overlayJob: Job? = null
    private var votedFrameRate = 0f
    private var keepingScreenOn = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        controller = (application as Tab2MacApplication).controller
        power = PowerMonitor(this)
        setContentView(R.layout.activity_stream)
        video = findViewById(R.id.video)
        overlay = findViewById(R.id.overlay)
        streamStatus = findViewById(R.id.stream_status)
        cursorView = findViewById(R.id.cursor)

        window.attributes = window.attributes.apply {
            layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
        }
        hideSystemBars()

        video.surfaceView.holder.addCallback(this)
        video.onVideoRectChanged = ::onVideoRect
        onVideoRect(video.videoRect)
        input = InputCapture(video, mapper) { batch -> controller.sendInput(batch) }
        input.attach()
    }

    /** A hardware keyboard (the Book Cover, Bluetooth, USB) goes to the Mac; everything else stays. */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean = keyboard.onKeyEvent(event) || super.dispatchKeyEvent(event)

    override fun onStart() {
        super.onStart()
        controller.cursor.attach(cursorView)
        controller.cursor.setVideoGeometry(video.videoRect, streamWidth)
        controller.requestOrientation(orientationOf(resources.configuration))
        scope.launch {
            controller.pipeline.videoSize.collect { size ->
                if (size != null) {
                    video.setVideoSize(size.width, size.height)
                    streamWidth = size.width
                    controller.cursor.setVideoGeometry(video.videoRect, streamWidth)
                }
            }
        }
        scope.launch { controller.state.collect(::render) }
        scope.launch { controller.pipeline.error.collect { render(controller.state.value) } }
    }

    override fun onStop() {
        scope.coroutineContext.cancelChildren()
        keyboard.releaseAll(System.nanoTime())
        controller.cursor.detach()
        overlayJob = null
        controller.setDiagnosticsVisible(false)
        setKeepScreenOn(false)
        super.onStop()
    }

    override fun onDestroy() {
        input.detach()
        scope.cancel()
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars() else keyboard.releaseAll(System.nanoTime())
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        val orientation = orientationOf(newConfig)
        AppLog.i("stream.rotated", "orientation" to orientation)
        controller.requestOrientation(orientation)
    }

    // SurfaceHolder.Callback

    override fun surfaceCreated(holder: SurfaceHolder) {
        AppLog.i("stream.surface-created")
        votedFrameRate = 0f
        controller.attachSurface(holder.surface)
        voteFrameRate(holder)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        AppLog.i("stream.surface-changed", "width" to width, "height" to height)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        AppLog.i("stream.surface-destroyed")
        controller.detachSurface()
    }

    private fun render(state: ReceiverState) {
        if (!state.active) {
            finish()
            return
        }
        val streaming = state.session as? SessionState.Streaming
        val error = controller.pipeline.error.value
        val live = streaming != null && !streaming.paused && error == null
        streamStatus.visibility = if (live && streaming.format != null) View.GONE else View.VISIBLE
        streamStatus.text = error ?: StatusText.of(state).headline
        setKeepScreenOn(live)
        video.surfaceView.holder.takeIf { it.surface?.isValid == true }?.let(::voteFrameRate)
        updateOverlayVisibility()
    }

    private fun setKeepScreenOn(on: Boolean) {
        if (on == keepingScreenOn) return
        keepingScreenOn = on
        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        AppLog.i("stream.keep-screen-on", "on" to on)
    }

    private fun updateOverlayVisibility() {
        val show = controller.settings.showDiagnostics
        overlay.visibility = if (show) View.VISIBLE else View.GONE
        controller.setDiagnosticsVisible(show)
        if (show && overlayJob?.isActive != true) {
            overlayJob = scope.launch {
                while (isActive) {
                    updateOverlay()
                    delay(OVERLAY_REFRESH_MS)
                }
            }
        } else if (!show) {
            overlayJob?.cancel()
            overlayJob = null
        }
    }

    private fun updateOverlay() {
        val state = controller.state.value
        val streaming = state.session as? SessionState.Streaming
        val plan = controller.pipeline.plan.value
        val snapshot = DiagnosticsSnapshot(
            connection = StatusText.short(state),
            width = streaming?.format?.width ?: streaming?.stream?.width,
            height = streaming?.format?.height ?: streaming?.stream?.height,
            codec = streaming?.stream?.codec?.value,
            decoderName = plan?.codecName,
            lowLatencyDecoder = plan?.lowLatency == true,
            rates = controller.stats.overlayRates(),
            rttUs = state.rttUs,
            clockOffsetUs = state.clockOffsetUs,
            displayRefreshHz = display?.refreshRate,
            votedFrameRate = votedFrameRate.takeIf { it > 0f },
            power = power.sample(),
            error = controller.pipeline.error.value,
        )
        overlay.text = DiagnosticsFormatter.format(snapshot)
    }

    /**
     * Votes for the stream's frame rate on the video Surface (FIXED_SOURCE), updated whenever
     * WELCOME or CONFIGURE changes it. Until the stream's rate is known nothing is voted.
     */
    private fun voteFrameRate(holder: SurfaceHolder) {
        val streaming = controller.state.value.session as? SessionState.Streaming ?: return
        val target = streaming.stream.fps.toFloat()
        if (target <= 0f || target == votedFrameRate) return
        if (SurfaceFrameRate.apply(holder.surface, target)) votedFrameRate = target
    }

    private fun onVideoRect(rect: VideoRect) {
        if (::cursorView.isInitialized) controller.cursor.setVideoGeometry(rect, streamWidth)
        mapper.videoRect = if (rect.isEmpty) null else NormalizationRect(rect.left.toFloat(), rect.top.toFloat(), rect.width.toFloat(), rect.height.toFloat())
    }

    private fun hideSystemBars() {
        window.insetsController?.let { controller ->
            controller.hide(WindowInsets.Type.systemBars())
            controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    }

    private fun orientationOf(configuration: Configuration): Orientation =
        if (configuration.orientation == Configuration.ORIENTATION_PORTRAIT) Orientation.PORTRAIT else Orientation.LANDSCAPE

    private companion object {
        /** 1 Hz. */
        const val OVERLAY_REFRESH_MS = 1_000L
    }
}
