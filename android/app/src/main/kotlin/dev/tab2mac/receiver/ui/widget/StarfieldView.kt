package dev.tab2mac.receiver.ui.widget

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.SystemClock
import android.util.AttributeSet
import android.view.View
import dev.tab2mac.receiver.ui.Motion
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * The brand's sky: stardust stars, a few cobalt and star ones, twinkling and drifting slowly,
 * drawn by this one View on its Canvas (the only Canvas animation of the app). [warp] stretches
 * them from the centre for dur-warp while the stream is about to start.
 *
 * Power: all arrays are allocated when the size changes, nothing per frame; the next frame is
 * asked for only from onDraw, so the loop stops by itself as soon as the view is hidden, gone or
 * its window stops, and resumes when it is shown again. Reduced motion draws one still frame.
 */
class StarfieldView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : View(context, attrs) {
    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val reduced = Motion.reduced(context)
    private val random = Random(SEED)

    private var count = 0
    private var xs = FloatArray(0)
    private var ys = FloatArray(0)
    private var zs = FloatArray(0)
    private var radii = FloatArray(0)
    private var phases = FloatArray(0)
    private var speeds = FloatArray(0)
    private var colors = IntArray(0)

    private val warpAngles = FloatArray(StarfieldMath.WARP_STREAKS)
    private val warpDistances = FloatArray(StarfieldMath.WARP_STREAKS)
    private val warpVelocities = FloatArray(StarfieldMath.WARP_STREAKS)
    private val warpColors = IntArray(StarfieldMath.WARP_STREAKS)
    private var warpStart = 0L
    private var warping = false

    private var startTime = SystemClock.uptimeMillis()
    private var lastFrame = 0L

    init {
        paint.style = Paint.Style.FILL
        paint.strokeCap = Paint.Cap.ROUND
    }

    /** Stars stretch from the centre for dur-warp, then settle back into the sky. */
    fun warp() {
        if (reduced) return
        for (i in 0 until StarfieldMath.WARP_STREAKS) {
            warpAngles[i] = StarfieldMath.angle(random.nextFloat())
            warpDistances[i] = random.nextFloat() * 40f * density
            warpVelocities[i] = 0.6f + random.nextFloat() * 1.6f
            warpColors[i] = when {
                random.nextFloat() < 0.15f -> STAR
                random.nextFloat() < 0.3f -> COBALT
                else -> STARDUST
            }
        }
        warpStart = SystemClock.uptimeMillis()
        lastFrame = warpStart
        warping = true
        invalidate()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        count = StarfieldMath.starCount(w, h, density)
        xs = FloatArray(count) { random.nextFloat() * w }
        ys = FloatArray(count) { random.nextFloat() * h }
        zs = FloatArray(count) { random.nextFloat() }
        radii = FloatArray(count) { (random.nextFloat() * 1.1f + 0.3f) * density }
        phases = FloatArray(count) { random.nextFloat() * 6.28f }
        speeds = FloatArray(count) { 0.6f + random.nextFloat() * 1.6f }
        colors = IntArray(count) { PALETTE[random.nextInt(PALETTE.size)] }
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        // Shown again: pick the loop up where onDraw left it.
        if (isVisible) {
            lastFrame = SystemClock.uptimeMillis()
            invalidate()
        }
    }

    override fun onDraw(canvas: Canvas) {
        val now = SystemClock.uptimeMillis()
        val time = (now - startTime).toFloat()
        val width = width.toFloat()
        for (i in 0 until count) {
            val z = zs[i]
            val alpha = StarfieldMath.alpha(phases[i], speeds[i], z, time, reduced)
            val x = if (reduced) xs[i] else StarfieldMath.driftX(xs[i], z, time, density, width)
            paint.color = withAlpha(colors[i], alpha)
            canvas.drawCircle(x, ys[i], radii[i] * (0.6f + z * 0.6f), paint)
        }
        if (warping) drawWarp(canvas, now)
        lastFrame = now
        if (reduced || !isShown) return
        if (warping) postInvalidateOnAnimation() else postInvalidateDelayed(StarfieldMath.TWINKLE_FRAME_MS)
    }

    private fun drawWarp(canvas: Canvas, now: Long) {
        val progress = min(1f, (now - warpStart).toFloat() / Motion.DUR_WARP)
        val speed = StarfieldMath.warpSpeed(progress)
        // The reference advances once per 60 Hz frame; follow the clock instead of the frame rate.
        val frames = max(0f, (now - lastFrame) / FRAME_60HZ_MS)
        val cx = width / 2f
        val cy = height / 2f
        val reach = max(width, height).toFloat()
        paint.strokeWidth = (1f + progress * 1.5f) * density
        for (i in 0 until StarfieldMath.WARP_STREAKS) {
            val from = warpDistances[i]
            var to = from + warpVelocities[i] * speed * frames * density
            // The trail the reference leaves by fading its canvas: a few frames of motion behind.
            val tail = max(from - (to - from) * 3f, 0f)
            paint.color = withAlpha(warpColors[i], min(1f, 0.3f + progress))
            val dx = cos(warpAngles[i])
            val dy = sin(warpAngles[i])
            canvas.drawLine(cx + dx * tail, cy + dy * tail, cx + dx * to, cy + dy * to, paint)
            if (to > reach) to = random.nextFloat() * 20f * density
            warpDistances[i] = to
        }
        if (progress >= 1f) warping = false
    }

    private fun withAlpha(color: Int, alpha: Float): Int = (color and 0x00FFFFFF) or ((alpha * 255).toInt().coerceIn(0, 255) shl 24)

    private companion object {
        const val SEED = 0x6167L
        const val FRAME_60HZ_MS = 1000f / 60f

        /** Brand constants (tokens.json): stardust, cobalt (night), star. */
        val STARDUST = Color.rgb(242, 243, 248)
        val COBALT = Color.rgb(111, 130, 255)
        val STAR = Color.rgb(255, 196, 61)
        val PALETTE = intArrayOf(STARDUST, STARDUST, STARDUST, COBALT, STAR)
    }
}
