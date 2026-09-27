package dev.ginga.decoder

import android.media.MediaCodecInfo
import android.media.MediaCodecInfo.CodecCapabilities
import android.media.MediaCodecInfo.CodecProfileLevel
import android.media.MediaCodecList
import android.os.Build

/** A decoder's capabilities as advertised in HELLO `decoders`. */
data class DecoderCapability(
    val mimeType: String,
    val codecName: String,
    /** Profile names such as `main`, `main10`, `high`. */
    val profiles: List<String>,
    val maxWidth: Int,
    val maxHeight: Int,
    val maxFps: Double,
    val lowLatency: Boolean,
)

/** Reads the device's decoders from `MediaCodecList` (the Android side of [DecoderConfigPlanner]). */
object CodecCatalog {

    /** Every decoder for [mimeType], in `MediaCodecList` order. */
    fun candidates(mimeType: String): List<CodecCandidate> = decoderInfos(mimeType).mapNotNull { info ->
        val capabilities = capabilitiesOf(info, mimeType) ?: return@mapNotNull null
        val video = capabilities.videoCapabilities
        CodecCandidate(
            name = info.name,
            mimeType = mimeType,
            isHardwareAccelerated = info.isHardwareAccelerated,
            isSoftwareOnly = info.isSoftwareOnly,
            isVendor = info.isVendor,
            isAlias = info.isAlias,
            supportsLowLatency = capabilities.isFeatureSupported(CodecCapabilities.FEATURE_LowLatency),
            sizeSupport = SizeSupport { width, height -> video?.isSizeSupported(width, height) == true },
        )
    }

    /** This device's SoC. */
    fun socInfo(): SocInfo = SocInfo(Build.SOC_MANUFACTURER, Build.SOC_MODEL, Build.HARDWARE)

    /**
     * The decoder the planner would pick for [mimeType] at [width]×[height], described for HELLO;
     * null when the device has no decoder for it.
     */
    fun capability(mimeType: String, width: Int, height: Int): DecoderCapability? {
        val candidates = candidates(mimeType)
        if (candidates.isEmpty()) return null
        val plan = try {
            DecoderConfigPlanner.plan(DecoderRequest(mimeType, width, height), candidates, socInfo())
        } catch (e: NoDecoderException) {
            return null
        }
        val info = decoderInfos(mimeType).firstOrNull { it.name == plan.codecName } ?: return null
        val capabilities = capabilitiesOf(info, mimeType) ?: return null
        val video = capabilities.videoCapabilities ?: return null
        val maxFps = try {
            if (video.isSizeSupported(width, height)) video.getSupportedFrameRatesFor(width, height).upper
            else video.supportedFrameRates.upper.toDouble()
        } catch (e: IllegalArgumentException) {
            video.supportedFrameRates.upper.toDouble()
        }
        return DecoderCapability(
            mimeType = mimeType,
            codecName = info.name,
            profiles = capabilities.profileLevels.map { it.profile }.distinct().mapNotNull { CodecProfiles.name(mimeType, it) },
            maxWidth = video.supportedWidths.upper,
            maxHeight = video.supportedHeights.upper,
            maxFps = maxFps,
            lowLatency = plan.lowLatency,
        )
    }

    private fun decoderInfos(mimeType: String): List<MediaCodecInfo> =
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { info ->
            !info.isEncoder && info.supportedTypes.any { it.equals(mimeType, ignoreCase = true) }
        }

    private fun capabilitiesOf(info: MediaCodecInfo, mimeType: String): CodecCapabilities? {
        val type = info.supportedTypes.firstOrNull { it.equals(mimeType, ignoreCase = true) } ?: return null
        return try {
            info.getCapabilitiesForType(type)
        } catch (e: IllegalArgumentException) {
            null
        }
    }
}

/** Names for `CodecProfileLevel` profile constants, as used in HELLO. */
object CodecProfiles {
    fun name(mimeType: String, profile: Int): String? = when (mimeType.lowercase()) {
        DecoderConfigPlanner.MIME_HEVC -> when (profile) {
            CodecProfileLevel.HEVCProfileMain -> "main"
            CodecProfileLevel.HEVCProfileMain10 -> "main10"
            CodecProfileLevel.HEVCProfileMainStill -> "main-still"
            CodecProfileLevel.HEVCProfileMain10HDR10 -> "main10-hdr10"
            CodecProfileLevel.HEVCProfileMain10HDR10Plus -> "main10-hdr10plus"
            else -> null
        }
        DecoderConfigPlanner.MIME_AVC -> when (profile) {
            CodecProfileLevel.AVCProfileBaseline -> "baseline"
            CodecProfileLevel.AVCProfileConstrainedBaseline -> "constrained-baseline"
            CodecProfileLevel.AVCProfileMain -> "main"
            CodecProfileLevel.AVCProfileExtended -> "extended"
            CodecProfileLevel.AVCProfileHigh -> "high"
            CodecProfileLevel.AVCProfileConstrainedHigh -> "constrained-high"
            CodecProfileLevel.AVCProfileHigh10 -> "high10"
            CodecProfileLevel.AVCProfileHigh422 -> "high422"
            CodecProfileLevel.AVCProfileHigh444 -> "high444"
            else -> null
        }
        else -> null
    }
}
