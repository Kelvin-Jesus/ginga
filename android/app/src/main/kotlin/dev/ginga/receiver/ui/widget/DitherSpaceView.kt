package dev.ginga.receiver.ui.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.util.AttributeSet
import android.view.Choreographer
import android.view.View
import dev.ginga.receiver.R
import dev.ginga.receiver.ui.Motion
import dev.ginga.receiver.ui.themeBoolean
import kotlin.math.ceil

/**
 * Draws a DitherSpace scene (DitherSpace.kt): the black hole, the galaxy or the pixel sky. The
 * scene fills a small ARGB buffer (one buffer pixel per `ditherCell`, 4dp), copied into a Bitmap
 * with setPixels and drawn scaled up with filtering off, so the pixels stay coarse.
 *
 * Power: frames come from the Choreographer every [PixelScene.frameMs] (42 ms, ~24 fps; the sky
 * 90 ms) and only while the view is attached, shown, its window visible and the screen on.
 * Reduced motion draws one still frame. `spaceOnly` views are GONE outside Black espacial.
 */
class DitherSpaceView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : View(context, attrs), Choreographer.FrameCallback {
    private val kind: Int
    private val columns: Int
    private val rows: Int
    private val cellPx: Float
    private val reduced = Motion.reduced(context)
    private val paint = Paint().apply { isFilterBitmap = false; isAntiAlias = false; isDither = false }
    private val destination = Rect()
    private var scene: PixelScene? = null
    private var bitmap: Bitmap? = null
    private var startNanos = System.nanoTime()
    private var running = false
    private var visibleOnScreen = false
    private var screenOn = true

    /** The black hole's shader, to collapse its orbits ([BlackHoleShader.pullT]) or burst it. */
    var blackHole: BlackHoleShader? = null
        private set

    init {
        val a = context.obtainStyledAttributes(attrs, R.styleable.DitherSpaceView)
        kind = a.getInt(R.styleable.DitherSpaceView_ditherScene, SCENE_BLACK_HOLE)
        columns = a.getInt(R.styleable.DitherSpaceView_ditherColumns, 190)
        rows = a.getInt(R.styleable.DitherSpaceView_ditherRows, 122)
        cellPx = a.getDimension(R.styleable.DitherSpaceView_ditherCell, 4 * resources.displayMetrics.density)
        val spaceOnly = a.getBoolean(R.styleable.DitherSpaceView_spaceOnly, false)
        a.recycle()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        if (spaceOnly && !context.themeBoolean(R.attr.gingaIsSpace)) {
            visibility = GONE
        } else if (kind != SCENE_SKY) {
            val shader: DitherShader = if (kind == SCENE_GALAXY) GalaxyShader() else BlackHoleShader().also { blackHole = it }
            setScene(DitherLoop(columns, rows, shader))
        }
    }

    /** Seconds since the scene started: the clock of [BlackHoleShader.tb]. */
    fun now(): Double = (System.nanoTime() - startNanos) / 1e9

    /** Bursts the black hole's particles now. */
    fun burst() {
        blackHole?.tb = now()
        if (reduced) drawFrame()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        if (kind == SCENE_SKY) {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
            return
        }
        setMeasuredDimension(
            resolveSize((columns * cellPx).toInt(), widthMeasureSpec),
            resolveSize((rows * cellPx).toInt(), heightMeasureSpec),
        )
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (kind == SCENE_SKY && w > 0 && h > 0 && visibility != GONE) {
            setScene(PixelSky(ceil(w / cellPx).toInt(), ceil(h / cellPx).toInt()))
        }
    }

    private fun setScene(value: PixelScene) {
        scene = value
        bitmap?.recycle()
        bitmap = Bitmap.createBitmap(value.width, value.height, Bitmap.Config.ARGB_8888)
        drawFrame()
        update()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        update()
    }

    override fun onDetachedFromWindow() {
        stop()
        super.onDetachedFromWindow()
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        visibleOnScreen = isVisible
        update()
    }

    override fun onScreenStateChanged(screenState: Int) {
        super.onScreenStateChanged(screenState)
        screenOn = screenState == SCREEN_STATE_ON
        update()
    }

    private fun update() {
        val run = !reduced && scene != null && isAttachedToWindow && visibleOnScreen && screenOn
        if (run && !running) {
            running = true
            Choreographer.getInstance().postFrameCallback(this)
        } else if (!run) {
            stop()
        }
    }

    private fun stop() {
        running = false
        Choreographer.getInstance().removeFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!running) return
        drawFrame()
        Choreographer.getInstance().postFrameCallbackDelayed(this, scene?.frameMs ?: return)
    }

    private fun drawFrame() {
        val scene = scene ?: return
        val bitmap = bitmap ?: return
        scene.render(if (reduced) STILL_T else now())
        bitmap.setPixels(scene.pixels, 0, scene.width, 0, 0, scene.width, scene.height)
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        val scene = scene ?: return
        val bitmap = bitmap ?: return
        destination.set(0, 0, (scene.width * cellPx).toInt(), (scene.height * cellPx).toInt())
        canvas.drawBitmap(bitmap, null, destination, paint)
    }

    private companion object {
        const val SCENE_BLACK_HOLE = 0
        const val SCENE_GALAXY = 1
        const val SCENE_SKY = 2

        /** The still frame with reduced motion (the reference draws t = 0 first). */
        const val STILL_T = 0.0
    }
}
