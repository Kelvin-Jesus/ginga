package dev.tab2mac.receiver.ui.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.os.SystemClock
import android.util.AttributeSet
import android.view.View
import dev.tab2mac.receiver.R
import dev.tab2mac.receiver.ui.Motion
import dev.tab2mac.receiver.ui.themeBoolean

/**
 * Draws a [DitherField] (Black espacial only): the field fills a small bitmap, one bitmap cell per
 * `ditherCell` (3dp), scaled up without filtering so the pixels stay coarse.
 *
 * Power: about 10 frames per second ([FRAME_MS]), asked for only from onDraw and only while the
 * view is shown, the theme is Black espacial and animations are on; otherwise one still frame.
 * Outside Black espacial the view is GONE and draws nothing. Its size follows the grid, so the
 * bitmap and buffers are allocated once.
 */
class DitherView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : View(context, attrs) {
    private val field: DitherField
    private val bitmap: Bitmap
    private val cellPx: Float
    private val paint = Paint().apply { isFilterBitmap = false; isAntiAlias = false; isDither = false }
    private val destination = Rect()
    private val space = context.themeBoolean(R.attr.gingaIsSpace)
    private val animated = space && !Motion.reduced(context)
    private val startTime = SystemClock.uptimeMillis()
    private var frame = 0

    init {
        val a = context.obtainStyledAttributes(attrs, R.styleable.DitherView)
        val scene = DitherField.Scene.entries[a.getInt(R.styleable.DitherView_ditherScene, 0)]
        val columns = a.getInt(R.styleable.DitherView_ditherColumns, 120)
        val rows = a.getInt(R.styleable.DitherView_ditherRows, 60)
        cellPx = a.getDimension(R.styleable.DitherView_ditherCell, 3 * resources.displayMetrics.density)
        a.recycle()
        field = DitherField(columns, rows, scene)
        bitmap = Bitmap.createBitmap(columns, rows, Bitmap.Config.ARGB_8888)
        visibility = if (space) VISIBLE else GONE
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(
            resolveSize((field.columns * cellPx).toInt(), widthMeasureSpec),
            resolveSize((field.rows * cellPx).toInt(), heightMeasureSpec),
        )
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        if (isVisible && animated) invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        if (!space) return
        val time = if (animated) SystemClock.uptimeMillis() - startTime else STILL_TIME_MS
        // The dither's phase moves every few frames: a faint shimmer, not motion.
        field.render(time, shimmer = if (animated) (frame / SHIMMER_FRAMES) and 3 else 0)
        bitmap.setPixels(field.pixels, 0, field.columns, 0, 0, field.columns, field.rows)
        destination.set(0, 0, width, height)
        canvas.drawBitmap(bitmap, null, destination, paint)
        frame++
        if (animated && isShown) postInvalidateDelayed(FRAME_MS)
    }

    private companion object {
        /** ~10 fps: the motion is very slow (a galaxy turn takes 2 minutes). */
        const val FRAME_MS = 100L
        const val SHIMMER_FRAMES = 6

        /** The still frame (reduced motion). */
        const val STILL_TIME_MS = 18_000L
    }
}
