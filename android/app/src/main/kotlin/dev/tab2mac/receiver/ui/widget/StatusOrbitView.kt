package dev.tab2mac.receiver.ui.widget

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
import android.widget.LinearLayout
import android.widget.TextView
import dev.tab2mac.receiver.R
import dev.tab2mac.receiver.ui.Motion
import dev.tab2mac.receiver.ui.Orbit
import dev.tab2mac.receiver.ui.themeBoolean
import dev.tab2mac.receiver.ui.themeColor

/**
 * StatusOrbit (components/StatusOrbit.md): a coloured planet with an orbit, and the state in
 * words (the text always says it; colour is never alone).
 *
 * Searching: an arc turning. Pairing and Connected: a pulse expanding. Paused, Error, Off: still.
 * Only transform and opacity, only while the pill is visible on screen, never with reduced motion.
 */
class StatusOrbitView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : LinearLayout(context, attrs) {
    private val density = resources.displayMetrics.density
    private val orb = FrameLayout(context)
    private val ring = View(context)
    private val dot = View(context)
    private val label = TextView(context)
    private var orbit = Orbit.OFF
    private var animator: Animator? = null
    private var visibleOnScreen = false

    /** Over the stream's sky (the first-frame toast): cosmos at 72% and stardust text. */
    var onSky: Boolean = false
        set(value) {
            field = value
            setBackgroundResource(if (value) R.drawable.g_pill_sky else R.drawable.g_pill)
            label.setTextColor(context.themeColor(if (value) R.attr.gingaStardust else R.attr.gingaInk))
        }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        clipChildren = false
        clipToPadding = false
        minimumHeight = dp(28)
        setPadding(dp(8), 0, dp(12), 0)
        setBackgroundResource(R.drawable.g_pill)
        orb.clipChildren = false
        orb.addView(ring, FrameLayout.LayoutParams(dp(14), dp(14)))
        orb.addView(dot, FrameLayout.LayoutParams(dp(6), dp(6), Gravity.CENTER))
        dot.setBackgroundResource(R.drawable.g_oval)
        addView(orb, LayoutParams(dp(14), dp(14)))
        label.setTextAppearance(R.style.TextAppearance_Ginga_Label)
        addView(label, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { marginStart = dp(8) })
        // The pill reads as one line: "Conectado · 60 Hz · Wi‑Fi".
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        accessibilityLiveRegion = ACCESSIBILITY_LIVE_REGION_POLITE
        orb.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        render()
    }

    fun setState(orbit: Orbit, text: CharSequence) {
        if (label.text != text) {
            label.text = text
            contentDescription = text
        }
        if (orbit == this.orbit) return
        this.orbit = orbit
        render()
    }

    private fun render() {
        val color = context.themeColor(
            when (orbit) {
                Orbit.SEARCHING -> R.attr.gingaCobalt
                Orbit.PAIRING, Orbit.PAUSED -> R.attr.gingaWarning
                Orbit.CONNECTED -> R.attr.gingaSuccess
                Orbit.ERROR -> R.attr.gingaDanger
                Orbit.OFF -> R.attr.gingaInkMuted
            },
        )
        val tint = ColorStateList.valueOf(color)
        dot.backgroundTintList = tint
        if (context.themeBoolean(R.attr.gingaIsSpace)) Glow.apply(dot, color)
        ring.setBackgroundResource(if (orbit == Orbit.SEARCHING) R.drawable.g_arc else R.drawable.g_ring)
        ring.backgroundTintList = tint
        restartAnimation()
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        visibleOnScreen = isVisible
        restartAnimation()
    }

    override fun onDetachedFromWindow() {
        stopAnimation()
        super.onDetachedFromWindow()
    }

    private fun restartAnimation() {
        stopAnimation()
        val animated = orbit == Orbit.SEARCHING || orbit == Orbit.PAIRING || orbit == Orbit.CONNECTED
        if (!animated || Motion.reduced(context)) {
            // The static equivalent: the orbit drawn in place (searching), or no ring at all.
            ring.alpha = if (orbit == Orbit.SEARCHING) 0.9f else 0f
            return
        }
        if (!visibleOnScreen || !isAttachedToWindow) return
        animator = when (orbit) {
            Orbit.SEARCHING -> {
                ring.alpha = 0.9f
                ObjectAnimator.ofFloat(ring, View.ROTATION, 0f, 360f).apply {
                    duration = SPIN_MS
                    interpolator = LinearInterpolator()
                }
            }
            else -> ObjectAnimator.ofPropertyValuesHolder(
                ring,
                PropertyValuesHolder.ofFloat(View.SCALE_X, 0.8f, 2.4f),
                PropertyValuesHolder.ofFloat(View.SCALE_Y, 0.8f, 2.4f),
                PropertyValuesHolder.ofFloat(View.ALPHA, 0.7f, 0f),
            ).apply {
                duration = if (orbit == Orbit.PAIRING) PAIRING_PULSE_MS else CONNECTED_PULSE_MS
                interpolator = Motion.easeOut
            }
        }.apply {
            repeatCount = ValueAnimator.INFINITE
            start()
        }
    }

    private fun stopAnimation() {
        animator?.cancel()
        animator = null
        ring.rotation = 0f
        ring.scaleX = 1f
        ring.scaleY = 1f
    }

    private fun dp(value: Int): Int = (value * density).toInt()

    private companion object {
        /** bundle.css: the status arc turns in 1.1 s; pulses take 1.6 s (pairing) and 2.4 s (connected). */
        const val SPIN_MS = 1_100L
        const val PAIRING_PULSE_MS = 1_600L
        const val CONNECTED_PULSE_MS = 2_400L
    }
}
