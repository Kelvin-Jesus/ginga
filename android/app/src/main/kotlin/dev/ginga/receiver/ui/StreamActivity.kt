package dev.ginga.receiver.ui

import android.app.Activity
import android.content.res.Configuration
import android.os.Bundle
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.ImageView
import android.widget.TextView
import dev.ginga.input.InputCapture
import dev.ginga.input.InputMapper
import dev.ginga.input.KeyboardCapture
import dev.ginga.input.NormalizationRect
import dev.ginga.protocol.Orientation
import dev.ginga.receiver.AppLog
import dev.ginga.receiver.R
import dev.ginga.receiver.ReceiverController
import dev.ginga.receiver.ReceiverState
import dev.ginga.receiver.GingaApplication
import dev.ginga.receiver.session.SessionState
import dev.ginga.receiver.stats.DiagnosticsFormatter
import dev.ginga.receiver.stats.DiagnosticsSnapshot
import dev.ginga.receiver.stats.PowerMonitor
import dev.ginga.receiver.ui.widget.BlackHoleTouch
import dev.ginga.receiver.ui.widget.DitherSpaceView
import dev.ginga.receiver.ui.widget.StarfieldView
import dev.ginga.receiver.ui.widget.StatusOrbitView
import dev.ginga.renderer.SurfaceFrameRate
import dev.ginga.renderer.VideoRect
import dev.ginga.renderer.VideoSurfaceLayout
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.abs

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
 * - the diagnostics overlay (off by default) refreshes once a second, only while visible;
 * - before the first frame, the Ginga sky: a pixel sky and the dithered black hole (DitherSpace,
 *   ~24 fps). Touches on it play with the hole and never reach the Mac. At the first frame the
 *   hole stops at once, a short warp plays while the sky fades, and the sky is GONE: nothing is
 *   drawn over the video but the cursor and the 3 s first-frame toast.
 */
class StreamActivity : Activity(), SurfaceHolder.Callback {
    private lateinit var controller: ReceiverController
    private lateinit var video: VideoSurfaceLayout
    private lateinit var overlay: TextView
    private lateinit var streamStatus: TextView
    private lateinit var cursorView: ImageView
    private lateinit var sky: View
    private lateinit var pixelSky: View
    private lateinit var blackHole: DitherSpaceView
    private lateinit var warp: StarfieldView
    private lateinit var streamOrbit: StatusOrbitView
    private var touchDownX = 0f
    private var touchDownY = 0f
    private lateinit var toast: StatusOrbitView

    /** Video is on screen (the sky is gone). */
    private var videoShowing = false

    /** The session whose first frame already had its toast. */
    private var toastedConnection: Long? = null

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
        controller = (application as GingaApplication).controller
        // Black espacial: the waiting sky is #000 instead of cosmos (gingaSky).
        setTheme(if (controller.settings.appearance.pureBlack) R.style.Theme_Ginga_Stream_Space else R.style.Theme_Ginga_Stream)
        super.onCreate(savedInstanceState)
        power = PowerMonitor(this)
        setContentView(R.layout.activity_stream)
        video = findViewById(R.id.video)
        overlay = findViewById(R.id.overlay)
        streamStatus = findViewById(R.id.stream_status)
        cursorView = findViewById(R.id.cursor)
        sky = findViewById(R.id.sky)
        pixelSky = findViewById(R.id.pixel_sky)
        blackHole = findViewById(R.id.black_hole)
        warp = findViewById(R.id.warp)
        warp.showStars = false
        streamOrbit = findViewById(R.id.stream_orbit)
        streamOrbit.onSky = true
        toast = findViewById(R.id.toast)
        toast.onSky = true
        // While waiting, the sky keeps every touch, hover and pen event: none reaches the Mac.
        sky.setOnTouchListener { _, event -> onSkyTouch(event) }
        sky.setOnGenericMotionListener { _, _ -> !videoShowing }
        sky.setOnHoverListener { _, _ -> !videoShowing }

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
        hideToast(animate = false)
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
        showVideo(live && streaming.format != null, state)
        streamStatus.text = error ?: StreamWaitingText.of(state).resolve(this)
        if (streaming?.paused == true || state.session is SessionState.Suspended) {
            streamOrbit.setState(Orbit.PAUSED, getString(R.string.status_paused))
        } else if (error != null) {
            streamOrbit.setState(Orbit.ERROR, getString(R.string.status_error))
        } else {
            streamOrbit.setState(Orbit.SEARCHING, getString(R.string.status_connecting))
        }
        setKeepScreenOn(live)
        video.surfaceView.holder.takeIf { it.surface?.isValid == true }?.let(::voteFrameRate)
        updateOverlayVisibility()
    }

    /**
     * The sky until video shows; then it is GONE (its Canvas stops) and, once per session, the
     * StatusOrbit toast "Conectado · 60 Hz · Wi‑Fi" appears for 3 s.
     */
    private fun showVideo(show: Boolean, state: ReceiverState) {
        if (show == videoShowing) return
        videoShowing = show
        blackHole.blackHole?.pullT = 0.0
        // The dithered scenes stop the moment video shows (GONE stops their frames).
        blackHole.visibility = if (show) View.GONE else View.VISIBLE
        pixelSky.visibility = if (show) View.GONE else View.VISIBLE
        sky.animate().cancel()
        if (!show) {
            warp.visibility = View.GONE
            sky.alpha = 1f
            sky.visibility = View.VISIBLE
        } else if (Motion.reduced(this)) {
            sky.visibility = View.GONE
        } else {
            // Warp: the stars stretch while the sky fades over the first frames, then it is gone.
            warp.visibility = View.VISIBLE
            warp.warp()
            sky.animate().alpha(0f).setDuration(WARP_FADE_MS).setInterpolator(Motion.easeOut).withEndAction {
                sky.visibility = View.GONE
                sky.alpha = 1f
                warp.visibility = View.GONE
            }.start()
        }
        val streaming = state.session as? SessionState.Streaming ?: return
        if (!show || toastedConnection == streaming.connectionId) return
        toastedConnection = streaming.connectionId
        toast.setState(Orbit.CONNECTED, HomeModel.connectedText(streaming, state).resolve(this))
        toast.visibility = View.VISIBLE
        toast.animate().cancel()
        if (Motion.reduced(this)) {
            toast.alpha = 1f
            toast.translationY = 0f
        } else {
            toast.alpha = 0f
            toast.translationY = -12f * resources.displayMetrics.density
            toast.animate().alpha(1f).translationY(0f).setDuration(TOAST_FADE_MS).setInterpolator(Motion.easeGinga).start()
        }
        toast.removeCallbacks(hideToastLater)
        toast.postDelayed(hideToastLater, Motion.TOAST_MS)
    }

    /**
     * The black hole under the finger (reference: dither-espaco.html): the closer, the more its
     * orbits collapse; a tap on the horizon bursts the particles. Consumed while waiting, so
     * nothing is sent to the Mac; once video shows, touches pass to the video.
     */
    private fun onSkyTouch(event: MotionEvent): Boolean {
        if (videoShowing) return false
        val shader = blackHole.blackHole ?: return true
        val dx = event.x - (blackHole.left + blackHole.width * 0.5f)
        val dy = event.y - (blackHole.top + blackHole.height * BlackHoleTouch.CENTER_Y)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                touchDownX = event.x
                touchDownY = event.y
                shader.pullT = BlackHoleTouch.pull(dx, dy, blackHole.width.toFloat())
            }
            MotionEvent.ACTION_MOVE -> shader.pullT = BlackHoleTouch.pull(dx, dy, blackHole.width.toFloat())
            MotionEvent.ACTION_UP -> {
                val slop = ViewConfiguration.get(this).scaledTouchSlop
                val tap = abs(event.x - touchDownX) < slop && abs(event.y - touchDownY) < slop
                if (tap && BlackHoleTouch.onHorizon(dx, dy, blackHole.height.toFloat())) blackHole.burst()
                shader.pullT = 0.0
            }
            MotionEvent.ACTION_CANCEL -> shader.pullT = 0.0
        }
        return true
    }

    private val hideToastLater = Runnable { hideToast(animate = true) }

    private fun hideToast(animate: Boolean) {
        toast.removeCallbacks(hideToastLater)
        toast.animate().cancel()
        if (!animate || Motion.reduced(this) || toast.visibility != View.VISIBLE) {
            toast.visibility = View.GONE
            return
        }
        toast.animate()
            .alpha(0f)
            .translationY(-12f * resources.displayMetrics.density)
            .setDuration(TOAST_FADE_MS)
            .setInterpolator(Motion.easeOut)
            .withEndAction { toast.visibility = View.GONE }
            .start()
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

        /** The sky's fade over the first frames, with the warp. */
        const val WARP_FADE_MS = 800L

        /** The toast's entrance and exit (reference: 500 ms). */
        const val TOAST_FADE_MS = 500L
    }
}
