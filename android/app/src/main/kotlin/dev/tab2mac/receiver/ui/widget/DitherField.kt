package dev.tab2mac.receiver.ui.widget

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.sqrt

/**
 * Black espacial's pixel skies, as on the website: a small grid of coarse cells (one cell ≈ 3dp)
 * whose colours are quantised into [Palette] with a 4×4 Bayer ordered dither, so gradients and
 * edges look dithered rather than smooth. Two scenes: a spiral galaxy and a black hole.
 *
 * Pure and allocation-free after construction: [render] fills [pixels] (ARGB, row-major,
 * [columns] × [rows]) for a time in milliseconds; a View copies it into a Bitmap and draws it
 * scaled up without filtering. Deterministic: the same time gives the same pixels.
 */
class DitherField(val columns: Int, val rows: Int, val scene: Scene) {
    enum class Scene { GALAXY, BLACK_HOLE }

    /** The palette (tokens and brand): the only colours a cell can take. */
    object Palette {
        const val BLACK = 0xFF000000.toInt()
        const val DEEP = 0xFF161B45.toInt()
        const val COBALT = 0xFF2E47F5.toInt()
        const val NIGHT = 0xFF6F82FF.toInt()
        const val PALE = 0xFFC8D0FF.toInt()
        const val WHITE = 0xFFF2F3F8.toInt()
        const val GOLD = 0xFFFFC43D.toInt()
        val ALL = intArrayOf(BLACK, DEEP, COBALT, NIGHT, PALE, WHITE, GOLD)
    }

    /** The rendered frame, ARGB. */
    val pixels = IntArray(columns * rows)

    /** Per cell: brightness in its ramp (0 → first colour, 1 → last), and which ramp. */
    private val intensity = FloatArray(columns * rows)
    private val ramp = ByteArray(columns * rows)

    init {
        require(columns > 0 && rows > 0) { "empty field" }
    }

    /**
     * Draws the scene at [timeMs]. [shimmer] shifts the Bayer matrix's phase (0–3): changing it
     * every few frames makes the dither shimmer faintly without moving the picture.
     */
    fun render(timeMs: Long, shimmer: Int = 0) {
        when (scene) {
            Scene.GALAXY -> galaxy(timeMs)
            Scene.BLACK_HOLE -> blackHole(timeMs)
        }
        for (y in 0 until rows) {
            for (x in 0 until columns) {
                val i = y * columns + x
                pixels[i] = quantize(intensity[i], RAMPS[ramp[i].toInt()], threshold(x + shimmer, y + (shimmer shr 1)))
            }
        }
    }

    /**
     * Two logarithmic-spiral arms in blue that fade to deep blue, white highlights along them,
     * a gold core; one turn every [GALAXY_TURN_MS]. Slightly inclined (the disc is an ellipse).
     */
    private fun galaxy(timeMs: Long) {
        val cx = (columns - 1) / 2f
        val cy = (rows - 1) / 2f
        val scale = minOf(columns.toFloat(), rows * GALAXY_TILT) / 2f * 1.08f
        val turn = ((timeMs % GALAXY_TURN_MS).toDouble() / GALAXY_TURN_MS * 2 * PI).toFloat()
        for (y in 0 until rows) {
            for (x in 0 until columns) {
                val i = y * columns + x
                val dx = (x - cx) / scale
                val dy = (y - cy) * GALAXY_TILT / scale
                val r = sqrt(dx * dx + dy * dy)
                val core = exp(-(r / CORE_RADIUS) * (r / CORE_RADIUS))
                if (core > 0.2f) {
                    ramp[i] = GOLD
                    intensity[i] = (0.25f + core * 0.75f).coerceAtMost(1f)
                    continue
                }
                val theta = atan2(dy, dx)
                // Distance, in angle, to the nearest of the two arms θ = ln(r) / tan(pitch) + turn.
                val onArm = theta - ln(r.coerceAtLeast(0.02f)) * ARM_WIND - turn
                val wrapped = ((onArm % PI_F) + PI_F) % PI_F
                val away = minOf(wrapped, PI_F - wrapped)
                val arm = exp(-(away * away) / ARM_WIDTH)
                val fade = exp(-r * 2.1f) * (if (r > 0.8f) exp(-(r - 0.8f) * 7f) else 1f)
                var value = arm * fade * 1.25f + fade * 0.12f + core * 0.5f
                if (value < 0.05f) value = 0f
                // Sparse white highlights (young stars) along the arms.
                if (arm > 0.7f && fade > 0.12f && hash(x, y, 7) > 0.93f) value = 1f
                ramp[i] = BLUE
                intensity[i] = value.coerceIn(0f, 1f)
            }
        }
    }

    /**
     * A dark disc with a thin white-blue photon ring; an inclined accretion disc crossing it,
     * blue with gold and white hot streaks, brighter on the approaching (left) side, its texture
     * drifting; the far half of the disc hidden behind the shadow; sparse star pixels around.
     */
    private fun blackHole(timeMs: Long) {
        val cx = (columns - 1) / 2f
        val cy = (rows - 1) / 2f
        // Lengths are in half-widths of the field, so the disc fits it horizontally.
        val unit = columns / 2f
        val drift = (timeMs % DISK_DRIFT_MS).toFloat() / DISK_DRIFT_MS
        for (y in 0 until rows) {
            for (x in 0 until columns) {
                val i = y * columns + x
                val dx = (x - cx) / unit
                val dy = (y - cy) / unit
                val r = sqrt(dx * dx + dy * dy)
                // The inclined disc: an ellipse flattened vertically.
                val u = dx / DISK_OUTER
                val v = dy / (DISK_OUTER * DISK_TILT)
                val rho = sqrt(u * u + v * v)
                val inDisk = rho in (DISK_INNER / DISK_OUTER)..1f
                val front = dy > 0f
                val shadowed = r < SHADOW_RADIUS
                ramp[i] = BLUE
                if (inDisk && (front || !shadowed)) {
                    val phi = atan2(v, u)
                    val band = floor((phi / (2 * PI_F) + drift) * STREAKS).toInt()
                    val ring = floor(rho * 9f).toInt()
                    val streak = hash(band, ring, 3)
                    // Doppler beaming: the side coming towards us (left) is brighter.
                    val beaming = (0.62f - u * 0.38f).coerceIn(0.2f, 1f)
                    val edge = 1f - abs(rho - 0.62f) / 0.38f
                    var value = (0.28f + 0.4f * edge.coerceIn(0f, 1f)) * beaming
                    if (streak > 0.86f && u < 0.3f) {
                        ramp[i] = GOLD
                        value = (0.55f + (streak - 0.86f) * 3f) * beaming + 0.15f
                    } else if (streak > 0.72f) {
                        value += 0.25f * beaming
                    }
                    intensity[i] = value.coerceIn(0f, 1f)
                } else if (shadowed) {
                    intensity[i] = 0f
                } else {
                    // The photon ring, thin and bright, just outside the shadow.
                    val ringDistance = abs(r - PHOTON_RADIUS)
                    val photon = exp(-(ringDistance * ringDistance) / 0.0002f)
                    var value = photon * 0.95f + exp(-(r - SHADOW_RADIUS) * 9f) * 0.2f
                    val star = hash(x, y, 11)
                    if (star > 0.988f) {
                        value = 0.55f + (star - 0.988f) * 35f
                        if (hash(x, y, 13) > 0.8f) ramp[i] = GOLD
                    }
                    intensity[i] = value.coerceIn(0f, 1f)
                }
            }
        }
    }

    companion object {
        private const val BLUE: Byte = 0
        private const val GOLD: Byte = 1

        /** Ramps from dark to bright, dithered between neighbours. */
        private val RAMPS = arrayOf(
            intArrayOf(Palette.BLACK, Palette.DEEP, Palette.COBALT, Palette.NIGHT, Palette.PALE, Palette.WHITE),
            intArrayOf(Palette.BLACK, Palette.DEEP, Palette.GOLD, Palette.WHITE),
        )

        /** The 4×4 Bayer matrix, 0–15. */
        val BAYER_4 = intArrayOf(
            0, 8, 2, 10,
            12, 4, 14, 6,
            3, 11, 1, 9,
            15, 7, 13, 5,
        )

        /** One galaxy turn every 2 minutes. */
        const val GALAXY_TURN_MS = 120_000L

        /** The disc texture drifts once around in 40 s. */
        const val DISK_DRIFT_MS = 40_000L

        private const val PI_F = PI.toFloat()
        private const val GALAXY_TILT = 1.9f
        private const val CORE_RADIUS = 0.12f
        private const val ARM_WIND = 2.6f
        private const val ARM_WIDTH = 0.16f
        private const val SHADOW_RADIUS = 0.2f
        private const val PHOTON_RADIUS = 0.225f
        private const val DISK_INNER = 0.3f
        private const val DISK_OUTER = 0.92f
        private const val DISK_TILT = 0.15f
        private const val STREAKS = 26f

        /** Threshold in (0, 1) of the Bayer cell at ([x], [y]), tiling every 4 cells. */
        fun threshold(x: Int, y: Int): Float = (BAYER_4[(y and 3) * 4 + (x and 3)] + 0.5f) / 16f

        /**
         * Ordered dither of [value] (0–1) along [ramp]: between the two nearest colours, the upper
         * one where the fractional part exceeds [threshold].
         */
        fun quantize(value: Float, ramp: IntArray, threshold: Float): Int {
            val position = value.coerceIn(0f, 1f) * (ramp.size - 1)
            val base = position.toInt().coerceAtMost(ramp.size - 1)
            val upper = position - base > threshold && base < ramp.size - 1
            return ramp[if (upper) base + 1 else base]
        }

        /** A stable pseudo-random value in [0, 1) for a cell (star positions, disc streaks). */
        fun hash(x: Int, y: Int, salt: Int): Float {
            var h = x * 374_761_393 + y * 668_265_263 + salt * 1_274_126_177
            h = (h xor (h ushr 13)) * 1_274_126_177
            h = h xor (h ushr 16)
            return (h ushr 8) / 16_777_216f
        }
    }
}
