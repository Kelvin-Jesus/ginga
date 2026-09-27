package dev.ginga.receiver.ui.widget

import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * The pure part of the sky (components/Starfield.md, reference/bundle.js `starfield` and `warp`):
 * how many stars, how bright each one is at a given time, and how fast the warp stretches them.
 * Sizes are in dp, the CSS pixels of the reference.
 */
object StarfieldMath {
    /** ~0.22 stars per 1000 dp². */
    const val STARS_PER_DP2 = 0.00022

    /** Streaks in the warp. */
    const val WARP_STREAKS = 140

    /** Drift to the right, in dp per millisecond, scaled by depth (0.3 + z). */
    const val DRIFT_DP_PER_MS = 0.012f

    /**
     * The twinkle is slow (periods of 4–10 s): 30 frames per second are enough and cost half of
     * the panel's 60 Hz. The warp runs at the display's rate.
     */
    const val TWINKLE_FRAME_MS = 33L

    /** Stars for a sky of [widthPx] × [heightPx] at [density] px per dp. */
    fun starCount(widthPx: Int, heightPx: Int, density: Float): Int {
        if (widthPx <= 0 || heightPx <= 0 || density <= 0f) return 0
        val areaDp2 = (widthPx / density).toDouble() * (heightPx / density)
        return (areaDp2 * STARS_PER_DP2).roundToInt()
    }

    /**
     * Opacity of a star with [phase] and twinkle [speed] at [timeMs], with depth [z] (0 far, 1 near).
     * Reduced motion: a still 0.7, scaled by depth.
     */
    fun alpha(phase: Float, speed: Float, z: Float, timeMs: Float, reduced: Boolean): Float {
        val twinkle = if (reduced) 0.7f else 0.35f + 0.55f * (0.5f + 0.5f * sin(phase + timeMs * 0.001f * speed))
        return (twinkle * (0.4f + z * 0.6f)).coerceIn(0f, 1f)
    }

    /** Horizontal position after drifting for [timeMs], wrapped to [width]. */
    fun driftX(x: Float, z: Float, timeMs: Float, dpToPx: Float, width: Float): Float {
        if (width <= 0f) return x
        val moved = x + timeMs * DRIFT_DP_PER_MS * dpToPx * (0.3f + z)
        return moved % width
    }

    /** Warp speed factor at [progress] (0 → 1 over dur-warp): starts at 1, ends at 27. */
    fun warpSpeed(progress: Float): Float {
        val p = progress.coerceIn(0f, 1f)
        return p * p * 26f + 1f
    }

    /** A random angle, for the warp streaks. */
    fun angle(unit: Float): Float = (unit * 2 * PI).toFloat()
}
