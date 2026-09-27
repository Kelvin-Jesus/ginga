package dev.tab2mac.receiver.ui.widget

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/*
 * DitherSpace (design/ginga-design/components/DitherSpace.md), ported as is from
 * design/ginga-design/reference/bundle.js: `ditherLoop`, `blackHole`, `galaxy` and `pixelSky`.
 * Pure Kotlin: a scene fills an ARGB IntArray for a small buffer (1 buffer pixel = 4dp on
 * screen); DitherSpaceView copies it into a Bitmap and draws it scaled up without filtering.
 * Differences from the JavaScript: Math.random() is a seeded [Random] (deterministic, testable).
 */

/** Something drawn as ARGB pixels into a [width] × [height] buffer, redrawn every [frameMs]. */
interface PixelScene {
    val width: Int
    val height: Int
    val pixels: IntArray
    val frameMs: Long

    /** Draws the scene at [t] seconds since it started. */
    fun render(t: Double)
}

/** A "shader" for [DitherLoop]: a value 0–1 per buffer pixel (`shade.init`, `shade.at`, `shade.splat`). */
interface DitherShader {
    fun init(width: Int, height: Int)

    fun at(i: Int, t: Double): Double

    /** Adds to the values after [at] (the black hole's particles). */
    fun splat(buffer: FloatArray, width: Int, height: Int, t: Double) {}
}

/**
 * `ditherLoop`: every pixel's value, ordered-dithered with the 4×4 Bayer matrix into the six
 * [PALETTE] colours; level 0 (cosmos) is transparent, so the background shows through
 * (#000 in Black espacial stays pixels-off). About 24 fps (42 ms).
 */
class DitherLoop(override val width: Int, override val height: Int, val shader: DitherShader) : PixelScene {
    override val pixels = IntArray(width * height)
    override val frameMs: Long = 42
    private val buffer = FloatArray(width * height)

    init {
        require(width > 0 && height > 0) { "empty buffer" }
        shader.init(width, height)
    }

    override fun render(t: Double) {
        for (j in buffer.indices) buffer[j] = shader.at(j, t).toFloat()
        shader.splat(buffer, width, height, t)
        var i = 0
        for (y in 0 until height) {
            for (x in 0 until width) {
                pixels[i] = PALETTE[level(buffer[i].toDouble(), x, y)]
                i++
            }
        }
    }

    companion object {
        /** cosmos (transparent), Noite, cobalt-brand, Cobalto noturno, stardust, star. No other colours. */
        val PALETTE = intArrayOf(
            0x000A0C1C,
            0xFF141830.toInt(),
            0xFF2E47F5.toInt(),
            0xFF6F82FF.toInt(),
            0xFFF2F3F8.toInt(),
            0xFFFFC43D.toInt(),
        )
        private const val N = 5

        /** The 4×4 Bayer matrix. */
        val BAYER = intArrayOf(0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5)

        /** `lv = floor(v * N + (B + 0.5) / 16)`, clamped to the palette. */
        fun level(value: Double, x: Int, y: Int): Int {
            val threshold = (BAYER[(y and 3) * 4 + (x and 3)] + 0.5) / 16
            return floor(value * N + threshold).toInt().coerceIn(0, N)
        }
    }
}

/**
 * `blackHole()`: gas spiralling in on a tilted disc with Doppler beaming (the left side hot),
 * a photon ring, a lensed arc on top, background stars displaced by the lens, and up to 700
 * Keplerian particles. [pullT] (0–1) collapses the orbits: set it from the finger's distance.
 * [tb] = now (seconds) makes the particles burst.
 */
class BlackHoleShader(private val random: Random = Random(SEED)) : DitherShader {
    /** Target collapse of the orbits, 0–1; [pull] eases towards it by 0.08 per frame. */
    var pullT = 0.0
    var pull = 0.0
        private set

    /** When the burst started, in the loop's seconds. */
    var tb = -99.0

    /** The hole's centre in buffer pixels. */
    var cx = 0.0
        private set
    var cy = 0.0
        private set

    // Per buffer pixel, what does not change with time (the reference recomputes it every frame;
    // hoisting it keeps a 190×122 frame to the few sines that move).
    private var py = FloatArray(0)
    private var inside = BooleanArray(0)
    private var discBase = DoubleArray(0)
    private var discPhase1 = DoubleArray(0)
    private var discPhase2 = DoubleArray(0)
    private var arcBase = DoubleArray(0)
    private var arcPhase = DoubleArray(0)
    private var photon = DoubleArray(0)
    private var haloBase = DoubleArray(0)
    private var back = DoubleArray(0)
    private var st = DoubleArray(0)

    /** Particles: radius, angle, angular speed, brightness, height. */
    private var pr = DoubleArray(0)
    private var pa = DoubleArray(0)
    private var pw = DoubleArray(0)
    private var pb = DoubleArray(0)
    private var pz = DoubleArray(0)

    val particleCount: Int get() = pr.size

    override fun init(width: Int, height: Int) {
        val n = width * height
        py = FloatArray(n); inside = BooleanArray(n)
        discBase = DoubleArray(n); discPhase1 = DoubleArray(n); discPhase2 = DoubleArray(n)
        arcBase = DoubleArray(n); arcPhase = DoubleArray(n); photon = DoubleArray(n)
        haloBase = DoubleArray(n); back = DoubleArray(n); st = DoubleArray(n)
        cx = width * 0.5
        cy = height * 0.52
        var i = 0
        for (yy in 0 until height) {
            for (xx in 0 until width) {
                // g.x, g.y, g.rd, g.lrd, g.ang, g.rs are Float32Arrays in the reference.
                val gx = ((xx - cx) / (height / 2.0))
                val gy = ((yy - cy) / (height / 2.0))
                val v = gy / K
                val x = gx.toFloat().toDouble()
                val y = gy.toFloat().toDouble()
                val rd = sqrt(gx * gx + v * v).toFloat().toDouble()
                val lrd = ln(rd + 0.001).toFloat().toDouble()
                val a = atan2(v, gx).toFloat().toDouble()
                val radius = sqrt(gx * gx + gy * gy).toFloat().toDouble()
                py[i] = y.toFloat()
                inside[i] = radius < R
                val dop = 0.5 - 0.5 * cos(a)
                if (rd > R_IN && rd < R_OUT) {
                    val f = 1 - (rd - R_IN) / (R_OUT - R_IN)
                    discBase[i] = f.pow(1.05) * (0.35 + 0.75 * dop) * min(1.0, (rd - R_IN) / 0.06)
                    discPhase1[i] = a * 3 + lrd * 7
                    discPhase2[i] = a * 7 - lrd * 11
                }
                val dr = abs(radius - 0.47)
                if (dr < 0.17 && y < 0.05) {
                    val la = atan2(y, x)
                    arcBase[i] = (1 - dr / 0.17).pow(1.4) * (0.55 + 0.45 * (0.5 - 0.5 * cos(la)))
                    arcPhase[i] = la * 5 + radius * 20
                }
                photon[i] = max(0.0, 1 - abs(radius - R * 1.04) / 0.02)
                haloBase[i] = 0.18 * exp(-(radius - R) / 0.14)
                val b0 = min(1.0, max(0.0, (radius - 0.5) / 0.3))
                back[i] = b0 * b0 * (3 - 2 * b0)
                // The lens: the star seen here comes from a point pushed outwards (Einstein).
                val k = if (gx * gx + gy * gy > R * R) 1 + 0.09 / (gx * gx + gy * gy) else 0.0
                val h = hash(floor(gx * k * 60), floor(gy * k * 60))
                val sr = sqrt(gx * gx + gy * gy)
                st[i] = (if (sr > R * 1.1 && sr < 1.05 && h > 0.985) 0.28 + (h - 0.985) * 40 else 0.0).toFloat().toDouble()
                i++
            }
        }
        val count = min(700, (width * height * 0.03).roundToInt())
        pr = DoubleArray(count); pa = DoubleArray(count); pw = DoubleArray(count); pb = DoubleArray(count); pz = DoubleArray(count)
        for (p in 0 until count) {
            val r0 = R_IN * 0.9 + random.nextDouble().pow(0.8) * (R_OUT * 1.25 - R_IN)
            pr[p] = r0
            pa[p] = random.nextDouble() * 6.2832
            pw[p] = 0.9 / r0.pow(1.5)
            pb[p] = 0.35 + random.nextDouble() * 0.55
            pz[p] = (random.nextDouble() - 0.5) * 0.05
        }
    }

    override fun at(i: Int, t: Double): Double {
        var disc = 0.0
        val base = discBase[i]
        if (base > 0) {
            // Spirals pulling the gas inwards.
            val sw = 0.5 + 0.5 * sin(discPhase1[i] + t * 2.2)
            val sw2 = 0.5 + 0.5 * sin(discPhase2[i] + t * 3.1)
            disc = base * (0.45 + 0.4 * sw + 0.2 * sw2)
        }
        val below = py[i] > 0
        if (inside[i]) return if (below && disc > 0) disc else 0.0
        var arc = 0.0
        if (arcBase[i] > 0) arc = arcBase[i] * (0.7 + 0.3 * sin(arcPhase[i] + t * 2.4))
        val halo = haloBase[i] * (1 + 0.6 * pull)
        var v = max(max(if (below) disc else max(disc * back[i], arc), photon[i] * (0.85 + 0.15 * sin(t * 3))), halo)
        if (st[i] > 0) v += st[i] * (0.65 + 0.35 * sin(t * 1.7 + i))
        return if (v > 1) 1.0 else v
    }

    override fun splat(buffer: FloatArray, width: Int, height: Int, t: Double) {
        pull += (pullT - pull) * 0.08
        val e = t - tb
        val burst = if (e > 0 && e < 2.2) sin(PI * min(1.0, e / 2.2)) * exp(-e * 0.6) else 0.0
        val s = height / 2.0
        val dt = 0.042
        for (p in pr.indices) {
            pa[p] += pw[p] * dt * (1 + 1.4 * pull)
            val r = pr[p] * (1 - 0.38 * pull) * (1 + 1.6 * burst * (0.6 + pb[p]))
            for (k in 0 until 3) {
                val aa = pa[p] - k * 0.05 * (1 + pull)
                val px = r * cos(aa)
                val py = r * sin(aa) * K + pz[p]
                val radius = sqrt(px * px + py * py)
                if (radius < R && sin(aa) < 0) continue
                val bx = Math.round(cx + px * s).toInt()
                val by = Math.round(cy + py * s).toInt()
                if (bx < 0 || by < 0 || bx >= width || by >= height) continue
                val o = by * width + bx
                val add = pb[p] * (if (k == 0) 0.75 else 0.32 / k) * (0.6 + 0.6 * (0.5 - 0.5 * cos(aa)))
                buffer[o] = min(1.0, buffer[o] + add).toFloat()
            }
        }
    }

    companion object {
        const val R = 0.28
        const val K = 0.2
        const val R_IN = 0.42
        const val R_OUT = 1.6
        const val SEED = 0x6769_6E67L

        /** `hash(a, b)` of the reference: fract(sin(a·127.1 + b·311.7) · 43758.5453). */
        fun hash(a: Double, b: Double): Double {
            val x = sin(a * 127.1 + b * 311.7) * 43758.5453
            return x - floor(x)
        }
    }
}

/**
 * `galaxy({ cx, cy, s, spin })`: a tilted two-armed spiral, `star` core, `cobalt-brand` and
 * `cobalt` arms, turning at [spin] radians per second.
 */
class GalaxyShader(
    private val centerX: Double = 0.5,
    private val centerY: Double = 0.5,
    private val scale: Double = 1.0,
    private val spin: Double = 0.35,
) : DitherShader {
    // Per pixel, what does not change with time: the arms' phase, the disc and the core.
    private var phase = DoubleArray(0)
    private var disc = DoubleArray(0)
    private var core = DoubleArray(0)
    private var outside = BooleanArray(0)

    override fun init(width: Int, height: Int) {
        val n = width * height
        phase = DoubleArray(n); disc = DoubleArray(n); core = DoubleArray(n); outside = BooleanArray(n)
        val unit = min(width, height) / 2.0 * scale
        val c = cos(-0.5)
        val s = sin(-0.5)
        var i = 0
        for (yy in 0 until height) {
            for (xx in 0 until width) {
                val x = (xx - width * centerX) / unit
                val y = (yy - height * centerY) / unit
                val u = x * c - y * s
                val w = (x * s + y * c) / 0.62
                // g.r and g.th are Float32Arrays in the reference.
                val radius = sqrt(u * u + w * w).toFloat().toDouble()
                val th = atan2(w, u).toFloat().toDouble()
                outside[i] = radius > 1.05
                phase[i] = 2 * th - 5.2 * ln(radius + 0.06)
                disc[i] = exp(-radius * 2.4) * min(1.0, (1.05 - radius) / 0.35)
                core[i] = 1.15 * exp(-radius * radius * 60)
                i++
            }
        }
    }

    override fun at(i: Int, t: Double): Double {
        if (outside[i]) return 0.0
        val wave = 0.5 + 0.5 * cos(phase[i] - t * spin)
        val arms = wave * wave * wave
        val v = disc[i] * (0.25 + 1.1 * arms) + core[i]
        return if (v > 1) 1.0 else v
    }
}

/**
 * `pixelSky`: a whole sky in 4dp pixels, twinkling, with the odd shooting star; redrawn about
 * every 90 ms. Transparent where there is no star.
 */
class PixelSky(override val width: Int, override val height: Int, private val random: Random = Random(SEED)) : PixelScene {
    override val pixels = IntArray(width * height)
    override val frameMs: Long = 90

    private val count = (width * height * 0.0048).roundToInt()
    private val sx = IntArray(count)
    private val sy = IntArray(count)
    private val sc = IntArray(count)
    private val sp = DoubleArray(count)
    private val ss = DoubleArray(count)
    private val big = BooleanArray(count)

    private var shooting = false
    private var shootStart = 0.0
    private var shootX = 0.0
    private var shootY = 0.0
    private var shootVx = 0.0
    private var shootVy = 0.0

    init {
        require(width > 0 && height > 0) { "empty sky" }
        for (i in 0 until count) {
            val k = random.nextDouble()
            val c = if (k < 0.5) 0 else if (k < 0.74) 1 else if (k < 0.88) 2 else if (k < 0.95) 3 else if (k < 0.99) 4 else 5
            sx[i] = (random.nextDouble() * width).toInt()
            sy[i] = (random.nextDouble() * height).toInt()
            sc[i] = c
            sp[i] = random.nextDouble() * 6.28
            ss[i] = 0.5 + random.nextDouble() * 2
            big[i] = c >= 4 && random.nextDouble() < 0.25
        }
    }

    val starCount: Int get() = count

    override fun render(t: Double) {
        pixels.fill(0)
        for (i in 0 until count) {
            val tw = sin(sp[i] + t * ss[i])
            var c = sc[i] + (if (tw > 0.75) 1 else if (tw < -0.6) -1 else 0)
            if (c < 0) continue
            if (c > 5) c = 5
            put(sx[i], sy[i], COLORS[c])
            if (big[i] && tw > 0.2) {
                val halo = COLORS[max(0, c - 2)]
                put(sx[i] - 1, sy[i], halo); put(sx[i] + 1, sy[i], halo)
                put(sx[i], sy[i] - 1, halo); put(sx[i], sy[i] + 1, halo)
            }
        }
        if (shooting) {
            val e = t - shootStart
            if (e > 1.1) {
                shooting = false
            } else {
                val hx = shootX + e * shootVx
                val hy = shootY + e * shootVy
                for (j in 0 until 14) {
                    val color = COLORS[if (j < 2) 5 else if (j < 5) 4 else if (j < 9) 2 else 1]
                    put(Math.round(hx - j * shootVx / 60).toInt(), Math.round(hy - j * shootVy / 60).toInt(), color)
                }
            }
        } else if (random.nextDouble() < 0.004) {
            shooting = true
            shootStart = t
            shootX = random.nextDouble() * width * 0.7
            shootY = random.nextDouble() * height * 0.35
            shootVx = 90 + random.nextDouble() * 60
            shootVy = 30 + random.nextDouble() * 30
        }
    }

    private fun put(x: Int, y: Int, color: Int) {
        if (x < 0 || y < 0 || x >= width || y >= height) return
        pixels[y * width + x] = color
    }

    companion object {
        const val SEED = 0x736B_79L

        /** The sky's colours (bundle.js `pixelSky` COL). */
        val COLORS = intArrayOf(
            0xFF252C66.toInt(),
            0xFF2E47F5.toInt(),
            0xFF6F82FF.toInt(),
            0xFFA4A9C8.toInt(),
            0xFFF2F3F8.toInt(),
            0xFFFFC43D.toInt(),
        )
    }
}

/** The finger and the black hole (reference: dither-espaco.html). Pure, so it's unit-tested. */
object BlackHoleTouch {
    /** The hole's centre, as a fraction of the view's height (the shader's cy = 0.52 H). */
    const val CENTER_Y = 0.52f

    /** A tap within this many horizon radii bursts the particles (the reference's 110px button). */
    const val TAP_RADII = 1.4f

    /** Collapse of the orbits for a finger at ([dx], [dy]) from the centre of a [viewWidth]-wide hole: 1 at the horizon, 0 far away. */
    fun pull(dx: Float, dy: Float, viewWidth: Float): Double {
        if (viewWidth <= 0f) return 0.0
        val distance = kotlin.math.sqrt(dx * dx + dy * dy)
        return (1.25 - distance / (viewWidth * 0.5)).coerceIn(0.0, 1.0)
    }

    /** Whether ([dx], [dy]) is on the horizon of a hole drawn [viewHeight] tall (radius R in half-heights). */
    fun onHorizon(dx: Float, dy: Float, viewHeight: Float): Boolean {
        val radius = BlackHoleShader.R * viewHeight / 2 * TAP_RADII
        return dx * dx + dy * dy <= radius * radius
    }
}
