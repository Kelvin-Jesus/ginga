package dev.ginga.receiver.ui.widget

import android.animation.Animator
import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.util.AttributeSet
import android.view.Gravity
import android.view.View
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import dev.ginga.receiver.R
import dev.ginga.receiver.ui.Motion
import dev.ginga.receiver.ui.themeColor

/**
 * The tablet's search radar (reference/demo-conexao.html `.radar`): two orbits in `line`, a
 * cobalt-brand planet with a pulse, a `star` satellite turning in dur-orbit and a cobalt one
 * turning back in 1.7 s. Rotations, scale and opacity only; everything stops when the radar is
 * not on screen, and reduced motion shows it still.
 */
class RadarView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : FrameLayout(context, attrs) {
    private val density = resources.displayMetrics.density
    private val ping = View(context)
    private val outerSatellite = FrameLayout(context)
    private val innerSatellite = FrameLayout(context)
    private val animators = mutableListOf<Animator>()
    private var visibleOnScreen = false

    init {
        clipChildren = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        addView(ring(), LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(ring(), inset(22))
        addView(View(context).apply { tinted(R.drawable.g_oval, R.attr.gingaCobaltBrand) }, inset(44))
        ping.tinted(R.drawable.g_ring, R.attr.gingaCobalt)
        ping.alpha = 0f
        addView(ping, inset(44))

        outerSatellite.clipChildren = false
        val star = View(context).apply { tinted(R.drawable.g_oval, R.attr.gingaStar) }
        outerSatellite.addView(star, LayoutParams(dp(8), dp(8), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply { topMargin = -dp(4) })
        Glow.apply(star, context.themeColor(R.attr.gingaStar), 3f)
        addView(outerSatellite, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        innerSatellite.clipChildren = false
        val moon = View(context).apply { tinted(R.drawable.g_oval, R.attr.gingaCobalt) }
        innerSatellite.addView(moon, LayoutParams(dp(6), dp(6), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply { topMargin = -dp(3) })
        addView(innerSatellite, inset(22))
        // Reduced motion: the satellites stay where a still frame puts them.
        innerSatellite.rotation = 200f
        outerSatellite.rotation = 40f
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        visibleOnScreen = isVisible
        update()
    }

    override fun onDetachedFromWindow() {
        stop()
        super.onDetachedFromWindow()
    }

    private fun update() {
        val run = visibleOnScreen && isAttachedToWindow && !Motion.reduced(context)
        if (run == animators.isNotEmpty()) return
        if (!run) {
            stop()
            return
        }
        animators += spin(outerSatellite, 0f, 360f, Motion.DUR_ORBIT)
        animators += spin(innerSatellite, 360f, 0f, INNER_ORBIT_MS)
        animators += ObjectAnimator.ofPropertyValuesHolder(
            ping,
            PropertyValuesHolder.ofFloat(View.SCALE_X, 0.8f, 2.4f),
            PropertyValuesHolder.ofFloat(View.SCALE_Y, 0.8f, 2.4f),
            PropertyValuesHolder.ofFloat(View.ALPHA, 0.7f, 0f),
        ).apply {
            duration = PING_MS
            interpolator = Motion.easeOut
            repeatCount = ValueAnimator.INFINITE
            start()
        }
    }

    private fun stop() {
        animators.forEach { it.cancel() }
        animators.clear()
        ping.alpha = 0f
    }

    private fun spin(view: View, from: Float, to: Float, ms: Long): Animator =
        ObjectAnimator.ofFloat(view, View.ROTATION, from, to).apply {
            duration = ms
            interpolator = LinearInterpolator()
            repeatCount = ValueAnimator.INFINITE
            start()
        }

    private fun ring() = View(context).apply { setBackgroundResource(R.drawable.g_ring_line) }

    private fun View.tinted(drawable: Int, colorAttr: Int) {
        setBackgroundResource(drawable)
        backgroundTintList = ColorStateList.valueOf(context.themeColor(colorAttr))
    }

    private fun inset(value: Int) = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT).apply {
        val px = dp(value)
        setMargins(px, px, px, px)
    }

    private fun dp(value: Int): Int = (value * density).toInt()

    private companion object {
        const val INNER_ORBIT_MS = 1_700L
        const val PING_MS = 2_200L
    }
}
