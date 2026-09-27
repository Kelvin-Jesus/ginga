package dev.ginga.decoder

/** Whether a decoder accepts a frame size. Abstracted so the planner runs on the JVM. */
fun interface SizeSupport {
    fun isSupported(width: Int, height: Int): Boolean

    companion object {
        /** Upper bounds per axis, either orientation (a rough stand-in for `isSizeSupported`). */
        fun upTo(maxWidth: Int, maxHeight: Int): SizeSupport = SizeSupport { width, height ->
            (width <= maxWidth && height <= maxHeight) || (height <= maxWidth && width <= maxHeight)
        }
    }
}

/**
 * What the planner needs to know about one decoder: a snapshot of `MediaCodecInfo` and its
 * capabilities for one MIME type.
 */
data class CodecCandidate(
    val name: String,
    val mimeType: String,
    val isHardwareAccelerated: Boolean,
    val isSoftwareOnly: Boolean,
    val isVendor: Boolean,
    val isAlias: Boolean,
    /** `CodecCapabilities.FEATURE_LowLatency` (API 30). */
    val supportsLowLatency: Boolean,
    val sizeSupport: SizeSupport,
) {
    /** Software decoders are never chosen: they can't keep up with a desktop stream and burn the CPU. */
    val isSoftware: Boolean
        get() = isSoftwareOnly || name.startsWith("OMX.google.", ignoreCase = true) ||
            name.startsWith("c2.android.", ignoreCase = true)
}

/** SoC / codec vendors whose decoders have vendor-specific low-latency switches. */
enum class CodecVendor {
    MEDIATEK,
    QUALCOMM,
    EXYNOS,
    OTHER,
    ;

    companion object {
        /** Classifies by codec name first (the decoder is what matters), then by SoC. */
        fun of(codecName: String, soc: SocInfo): CodecVendor {
            val name = codecName.lowercase()
            return when {
                name.startsWith("c2.mtk.") || name.startsWith("omx.mtk.") -> MEDIATEK
                name.startsWith("c2.qti.") || name.startsWith("omx.qcom.") -> QUALCOMM
                name.startsWith("c2.exynos.") || name.startsWith("omx.exynos.") -> EXYNOS
                name.startsWith("c2.android.") || name.startsWith("omx.google.") -> OTHER
                else -> soc.vendor
            }
        }
    }
}

/** `Build.SOC_MANUFACTURER`, `Build.SOC_MODEL`, `Build.HARDWARE`. */
data class SocInfo(val manufacturer: String, val model: String, val hardware: String) {
    val vendor: CodecVendor
        get() {
            val maker = manufacturer.lowercase()
            val hw = hardware.lowercase()
            return when {
                "mediatek" in maker || hw.startsWith("mt") -> CodecVendor.MEDIATEK
                "qti" in maker || "qualcomm" in maker || hw.startsWith("qcom") -> CodecVendor.QUALCOMM
                "samsung" in maker || hw.startsWith("s5e") || hw.startsWith("exynos") -> CodecVendor.EXYNOS
                else -> CodecVendor.OTHER
            }
        }
}

/**
 * Colour description of the stream as `MediaFormat` constants (`COLOR_STANDARD_*`,
 * `COLOR_RANGE_*`, `COLOR_TRANSFER_*`). Null members are left to the bitstream.
 */
data class ColorAspects(val standard: Int?, val range: Int?, val transfer: Int?) {
    companion object {
        // Values of the MediaFormat constants (API 24), spelled out so the planner stays pure.
        private const val STANDARD_BT709 = 1
        private const val STANDARD_BT601_PAL = 2
        private const val STANDARD_BT601_NTSC = 4
        private const val STANDARD_BT2020 = 6
        private const val RANGE_FULL = 1
        private const val RANGE_LIMITED = 2
        private const val TRANSFER_SDR_VIDEO = 3
        private const val TRANSFER_ST2084 = 6
        private const val TRANSFER_HLG = 7

        /** Maps WELCOME `stream` colour names (`bt709`, `video`, …). Unknown names become null. */
        fun fromNames(primaries: String?, transfer: String?, range: String?): ColorAspects = ColorAspects(
            standard = when (primaries?.lowercase()) {
                "bt709" -> STANDARD_BT709
                "bt2020" -> STANDARD_BT2020
                "bt601", "smpte170m" -> STANDARD_BT601_NTSC
                "bt470bg" -> STANDARD_BT601_PAL
                else -> null
            },
            range = when (range?.lowercase()) {
                "video", "limited" -> RANGE_LIMITED
                "full" -> RANGE_FULL
                else -> null
            },
            transfer = when (transfer?.lowercase()) {
                "bt709", "bt601", "smpte170m", "sdr" -> TRANSFER_SDR_VIDEO
                "pq", "st2084" -> TRANSFER_ST2084
                "hlg" -> TRANSFER_HLG
                else -> null
            },
        )
    }
}

/** What to decode. */
data class DecoderRequest(
    /** `video/hevc` or `video/avc`. */
    val mimeType: String,
    val width: Int,
    val height: Int,
    val frameRate: Double? = null,
    /** VPS/SPS/PPS (HEVC) or SPS/PPS (H.264), with or without start codes. */
    val parameterSets: List<ByteArray> = emptyList(),
    val color: ColorAspects? = null,
    /**
     * `operating-rate` = [frameRate] × this. 1 (default) lets the decoder clock just fast enough
     * for the stream (lowest power). 2 buys latency with power: on the Tab S11 at 60 fps it cut
     * decode p50 from 13.7 to 11.2 ms. Never unbounded (`Short.MAX_VALUE` pins the clocks).
     */
    val operatingRateFactor: Double = 1.0,
) {
    init {
        require(width > 0 && height > 0) { "invalid size ${width}x$height" }
        require(operatingRateFactor in 1.0..4.0) { "operatingRateFactor must be within 1..4" }
    }
}

/** A typed `MediaFormat` value. */
sealed interface FormatValue {
    data class IntValue(val value: Int) : FormatValue
    data class FloatValue(val value: Float) : FormatValue
}

/**
 * One `MediaFormat` key. [optional] entries are hints that a picky codec may reject; the decoder
 * retries without them when `configure` fails.
 */
data class FormatEntry(val key: String, val value: FormatValue, val optional: Boolean)

/** The planner's decision: which codec, and exactly how to configure it. */
class DecoderPlan(
    val codecName: String,
    val mimeType: String,
    val width: Int,
    val height: Int,
    val vendor: CodecVendor,
    /** The codec advertises `FEATURE_LowLatency`, so `low-latency=1` is requested. */
    val lowLatency: Boolean,
    val entries: List<FormatEntry>,
    /** `csd-0` (and `csd-1` for H.264) with Annex‑B start codes. */
    val codecSpecificData: List<Pair<String, ByteArray>>,
    /** Why this codec was chosen, for the log. */
    val notes: List<String>,
) {
    /** The integer value of [key], if planned. */
    fun intValue(key: String): Int? = (entries.firstOrNull { it.key == key }?.value as? FormatValue.IntValue)?.value

    /** The same plan without optional entries. */
    fun withoutOptionalEntries(): DecoderPlan =
        DecoderPlan(codecName, mimeType, width, height, vendor, lowLatency, entries.filterNot { it.optional }, codecSpecificData, notes)

    /** The same plan with `max-input-size` of at least [bytes] (for a frame that didn't fit). */
    fun withMaxInputSize(bytes: Int): DecoderPlan {
        val entry = FormatEntry(DecoderConfigPlanner.KEY_MAX_INPUT_SIZE, FormatValue.IntValue(bytes), optional = false)
        val others = entries.filterNot { it.key == DecoderConfigPlanner.KEY_MAX_INPUT_SIZE }
        return DecoderPlan(codecName, mimeType, width, height, vendor, lowLatency, others + entry, codecSpecificData, notes)
    }

    /** The stream's frame rate, if the plan carries one (`frame-rate`). */
    val frameRate: Float?
        get() = (entries.firstOrNull { it.key == DecoderConfigPlanner.KEY_FRAME_RATE }?.value as? FormatValue.FloatValue)?.value

    override fun toString(): String =
        "DecoderPlan(codec=$codecName, ${width}x$height, vendor=$vendor, lowLatency=$lowLatency, " +
            "entries=${entries.joinToString { "${it.key}=${it.value}" }}, csd=${codecSpecificData.map { "${it.first}:${it.second.size}" }})"
}

/** Thrown when no decoder exists for a MIME type. */
class NoDecoderException(message: String) : Exception(message)
