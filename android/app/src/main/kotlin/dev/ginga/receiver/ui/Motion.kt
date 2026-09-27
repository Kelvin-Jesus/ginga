package dev.ginga.receiver.ui

import android.content.Context
import android.provider.Settings
import android.view.View
import android.view.animation.Interpolator
import android.view.animation.PathInterpolator

/**
 * Motion tokens (tokens.json "duration", "easing") and the rules of the brand's movement:
 * transform and opacity only, nothing animating off screen, and a static equivalent when the
 * system's animations are off (reduced motion).
 */
object Motion {
    const val DUR_TAP = 120L
    const val DUR_UI = 220L
    const val DUR_SHEET = 420L
    const val DUR_ORBIT = 2400L
    const val DUR_WARP = 1400L

    /** DeviceRow entrance: rows appear one after another, like stars. */
    const val RISE_STAGGER = 120L

    /** PairingCode: each digit 60 ms after the previous one. */
    const val DIGIT_STAGGER = 60L

    /** How long the "Conectado · 60 Hz · Wi‑Fi" toast stays over the first frame. */
    const val TOAST_MS = 3_000L

    /** ease-ginga, cubic-bezier(0.34, 1.36, 0.64, 1): passes the mark ~6% and comes back. */
    val easeGinga: Interpolator by lazy { PathInterpolator(0.34f, 1.36f, 0.64f, 1f) }

    /** ease-out, cubic-bezier(0.2, 0.8, 0.2, 1): entrances and fades. */
    val easeOut: Interpolator by lazy { PathInterpolator(0.2f, 0.8f, 0.2f, 1f) }

    /** Reduced motion is the system's animator duration scale set to 0 (animations off). */
    fun isReduced(animatorDurationScale: Float): Boolean = animatorDurationScale == 0f

    fun reduced(context: Context): Boolean =
        isReduced(Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f))

    /** Delay of the [index]th item of a staggered entrance. */
    fun staggerDelay(index: Int, step: Long): Long = index.coerceAtLeast(0) * step

    /**
     * g-rise: from 8dp below and transparent to its place, in dur-sheet with ease-out, [index]
     * steps of [RISE_STAGGER] after the first. Reduced motion: shown at once.
     */
    fun rise(view: View, index: Int, reduced: Boolean) {
        view.animate().cancel()
        if (reduced) {
            view.alpha = 1f
            view.translationY = 0f
            return
        }
        view.alpha = 0f
        view.translationY = 8f * view.resources.displayMetrics.density
        view.animate()
            .alpha(1f)
            .translationY(0f)
            .setStartDelay(staggerDelay(index, RISE_STAGGER))
            .setDuration(DUR_SHEET)
            .setInterpolator(easeOut)
            .start()
    }
}
