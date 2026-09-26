package dev.tab2mac.decoder

/**
 * Chooses a decoder and its `MediaFormat` for the lowest latency at the lowest power (research §4).
 * Pure: it only sees [CodecCandidate] snapshots, so every rule is unit-tested on the JVM.
 *
 * Selection: hardware-accelerated decoders only (a software decoder can't keep up with a desktop
 * stream and burns the CPU; there is no silent fallback); `FEATURE_LowLatency` first; then
 * non-alias, vendor codecs; ties keep `MediaCodecList` order (the OEM's preference).
 *
 * Format:
 * - `low-latency=1` always: required when the codec advertises `FEATURE_LowLatency`, otherwise an
 *   optional hint that is dropped if `configure` rejects it;
 * - `priority=0` (realtime);
 * - `operating-rate` = the stream's frame rate on every vendor (optionally ×2, see
 *   [DecoderRequest.operatingRateFactor]). Never `Short.MAX_VALUE`, which pins the decoder clocks
 *   at maximum;
 * - vendor low-latency switches: MediaTek `vdec-lowlatency=1`, Qualcomm
 *   `vendor.qti-ext-dec-low-latency.enable=1`, Exynos `vendor.rtc-ext-dec-low-latency.enable=1`;
 * - `max-input-size` large enough for a keyframe;
 * - `csd-0` (+ `csd-1` for H.264) from the STREAM_FORMAT parameter sets with start codes.
 */
object DecoderConfigPlanner {
    // MediaFormat keys, spelled out so the planner has no Android dependency.
    const val KEY_LOW_LATENCY = "low-latency"
    const val KEY_PRIORITY = "priority"
    const val KEY_OPERATING_RATE = "operating-rate"
    const val KEY_MAX_INPUT_SIZE = "max-input-size"
    const val KEY_FRAME_RATE = "frame-rate"
    const val KEY_COLOR_STANDARD = "color-standard"
    const val KEY_COLOR_RANGE = "color-range"
    const val KEY_COLOR_TRANSFER = "color-transfer"
    const val KEY_MEDIATEK_LOW_LATENCY = "vdec-lowlatency"

    /** MediaTek video post-processing (MEMC, quality tuner, scaler): off for a desktop stream. */
    const val KEY_MEDIATEK_VPP_DISABLED = "vendor.mtk.ext.vdec.vpp.disabled.value"
    const val KEY_QUALCOMM_LOW_LATENCY = "vendor.qti-ext-dec-low-latency.enable"
    const val KEY_EXYNOS_LOW_LATENCY = "vendor.rtc-ext-dec-low-latency.enable"

    const val MIME_HEVC = "video/hevc"
    const val MIME_AVC = "video/avc"

    /** Smallest `max-input-size`, so small streams still fit an occasional large keyframe. */
    private const val MIN_INPUT_BUFFER = 1 shl 20

    /**
     * Picks the best candidate for [request].
     *
     * @throws NoDecoderException when no hardware decoder handles the MIME type.
     */
    fun plan(request: DecoderRequest, candidates: List<CodecCandidate>, soc: SocInfo): DecoderPlan {
        val notes = mutableListOf<String>()
        val matching = candidates.filter { it.mimeType.equals(request.mimeType, ignoreCase = true) }
        if (matching.isEmpty()) throw NoDecoderException("no decoder for ${request.mimeType}")

        val hardware = matching.filter { it.isHardwareAccelerated && !it.isSoftware }
        if (hardware.isEmpty()) {
            throw NoDecoderException("no hardware decoder for ${request.mimeType} (software decoders: ${matching.map { it.name }})")
        }
        val sized = hardware.filter { it.sizeSupport.isSupported(request.width, request.height) }.ifEmpty {
            notes += "no decoder reports ${request.width}x${request.height}; trying anyway"
            hardware
        }
        val chosen = sized.sortedWith(
            compareByDescending<CodecCandidate> { it.supportsLowLatency }
                .thenBy { it.isAlias }
                .thenByDescending { it.isVendor },
        ).first()
        notes += "chose ${chosen.name} of ${matching.map { it.name }}"

        val vendor = CodecVendor.of(chosen.name, soc)
        val entries = mutableListOf<FormatEntry>()
        entries += FormatEntry(KEY_LOW_LATENCY, FormatValue.IntValue(1), optional = !chosen.supportsLowLatency)
        entries += FormatEntry(KEY_PRIORITY, FormatValue.IntValue(0), optional = true)
        entries += FormatEntry(KEY_MAX_INPUT_SIZE, FormatValue.IntValue(maxInputSize(request)), optional = false)
        request.frameRate?.takeIf { it > 0 }?.let { fps ->
            entries += FormatEntry(KEY_FRAME_RATE, FormatValue.FloatValue(fps.toFloat()), optional = true)
            entries += FormatEntry(KEY_OPERATING_RATE, FormatValue.FloatValue((fps * request.operatingRateFactor).toFloat()), optional = true)
        }
        when (vendor) {
            CodecVendor.MEDIATEK -> {
                entries += FormatEntry(KEY_MEDIATEK_LOW_LATENCY, FormatValue.IntValue(1), optional = true)
                entries += FormatEntry(KEY_MEDIATEK_VPP_DISABLED, FormatValue.IntValue(1), optional = true)
            }
            CodecVendor.QUALCOMM -> entries += FormatEntry(KEY_QUALCOMM_LOW_LATENCY, FormatValue.IntValue(1), optional = true)
            CodecVendor.EXYNOS -> entries += FormatEntry(KEY_EXYNOS_LOW_LATENCY, FormatValue.IntValue(1), optional = true)
            CodecVendor.OTHER -> Unit
        }
        request.color?.let { color ->
            color.standard?.let { entries += FormatEntry(KEY_COLOR_STANDARD, FormatValue.IntValue(it), optional = true) }
            color.range?.let { entries += FormatEntry(KEY_COLOR_RANGE, FormatValue.IntValue(it), optional = true) }
            color.transfer?.let { entries += FormatEntry(KEY_COLOR_TRANSFER, FormatValue.IntValue(it), optional = true) }
        }

        return DecoderPlan(
            codecName = chosen.name,
            mimeType = request.mimeType,
            width = request.width,
            height = request.height,
            vendor = vendor,
            lowLatency = chosen.supportsLowLatency,
            entries = entries,
            codecSpecificData = codecSpecificData(request.mimeType, request.parameterSets),
            notes = notes,
        )
    }

    /** `csd-*` buffers: HEVC takes every parameter set in `csd-0`; H.264 splits SPS / PPS. */
    fun codecSpecificData(mimeType: String, parameterSets: List<ByteArray>): List<Pair<String, ByteArray>> {
        val sets = parameterSets.filter { it.size > AnnexB.startCodeLength(it) }
        if (sets.isEmpty()) return emptyList()
        if (!mimeType.equals(MIME_AVC, ignoreCase = true)) return listOf("csd-0" to AnnexB.join(sets))
        val sps = sets.filter { AnnexB.avcNalType(it) == 7 }
        val pps = sets.filter { AnnexB.avcNalType(it) == 8 }
        return if (sps.isNotEmpty() && pps.isNotEmpty()) {
            listOf("csd-0" to AnnexB.join(sps), "csd-1" to AnnexB.join(pps))
        } else {
            // Unrecognised units: keep the documented order (SPS first, then PPS).
            listOfNotNull("csd-0" to AnnexB.join(sets.take(1)), sets.drop(1).takeIf { it.isNotEmpty() }?.let { "csd-1" to AnnexB.join(it) })
        }
    }

    /** Room for a keyframe: one byte per pixel, at least 1 MiB. */
    fun maxInputSize(request: DecoderRequest): Int =
        maxOf(MIN_INPUT_BUFFER.toLong(), request.width.toLong() * request.height).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
}
