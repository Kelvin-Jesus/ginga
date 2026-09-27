package dev.ginga.receiver.ui.widget

import android.view.View
import android.view.ViewGroup
import dev.ginga.receiver.R
import dev.ginga.receiver.ui.Motion
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/**
 * The spark (Ginga.spark in reference/bundle.js): seven `star` dots leave the centre of a view
 * when a toggle turns ON or a primary action is confirmed; never when turning off. They live in
 * the window's overlay for 520 ms (translation, scale and opacity only) and are then removed.
 * Nothing with reduced motion.
 */
object Spark {
    private const val COUNT = 7
    private const val DURATION_MS = 520L

    fun burst(anchor: View) {
        if (Motion.reduced(anchor.context) || !anchor.isAttachedToWindow) return
        val root = anchor.rootView as? ViewGroup ?: return
        val density = anchor.resources.displayMetrics.density
        val location = IntArray(2)
        anchor.getLocationInWindow(location)
        val cx = location[0] + anchor.width / 2
        val cy = location[1] + anchor.height / 2
        val half = (2.5f * density).toInt().coerceAtLeast(1)
        repeat(COUNT) { i ->
            val dot = View(anchor.context)
            dot.background = anchor.context.getDrawable(R.drawable.g_spark_dot)
            dot.layout(cx - half, cy - half, cx + half, cy + half)
            root.overlay.add(dot)
            val angle = i.toDouble() / COUNT * 2 * Math.PI + Random.nextDouble() * 0.5
            val distance = (16 + Random.nextDouble() * 12) * density
            dot.animate()
                .translationX((cos(angle) * distance).toFloat())
                .translationY((sin(angle) * distance).toFloat())
                .scaleX(0.2f).scaleY(0.2f)
                .alpha(0f)
                .setDuration(DURATION_MS)
                .setInterpolator(Motion.easeOut)
                .withEndAction { root.overlay.remove(dot) }
                .start()
        }
    }
}
