package dev.tab2mac.decoder

import dev.tab2mac.decoder.DecoderConfigPlanner.KEY_COLOR_RANGE
import dev.tab2mac.decoder.DecoderConfigPlanner.KEY_COLOR_STANDARD
import dev.tab2mac.decoder.DecoderConfigPlanner.KEY_EXYNOS_LOW_LATENCY
import dev.tab2mac.decoder.DecoderConfigPlanner.KEY_FRAME_RATE
import dev.tab2mac.decoder.DecoderConfigPlanner.KEY_LOW_LATENCY
import dev.tab2mac.decoder.DecoderConfigPlanner.KEY_MAX_INPUT_SIZE
import dev.tab2mac.decoder.DecoderConfigPlanner.KEY_MEDIATEK_LOW_LATENCY
import dev.tab2mac.decoder.DecoderConfigPlanner.KEY_OPERATING_RATE
import dev.tab2mac.decoder.DecoderConfigPlanner.KEY_PRIORITY
import dev.tab2mac.decoder.DecoderConfigPlanner.KEY_QUALCOMM_LOW_LATENCY
import dev.tab2mac.decoder.DecoderConfigPlanner.MIME_AVC
import dev.tab2mac.decoder.DecoderConfigPlanner.MIME_HEVC
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DecoderConfigPlannerTest {
    private val mediatek = SocInfo("Mediatek", "MT6991", "mt6991")
    private val qualcomm = SocInfo("QTI", "SM8750", "qcom")
    private val hevcParameterSets = listOf(byteArrayOf(0x40, 0x01, 0x0C), byteArrayOf(0x42, 0x01, 0x01), byteArrayOf(0x44, 0x01, 0xC1.toByte()))

    private fun candidate(
        name: String,
        mime: String = MIME_HEVC,
        lowLatency: Boolean = true,
        hardware: Boolean = true,
        software: Boolean = false,
        vendor: Boolean = true,
        alias: Boolean = false,
        size: SizeSupport = SizeSupport.upTo(4096, 2176),
    ) = CodecCandidate(name, mime, hardware, software, vendor, alias, lowLatency, size)

    private fun request(width: Int = 2560, height: Int = 1600, mime: String = MIME_HEVC, fps: Double? = 60.0) =
        DecoderRequest(mime, width, height, fps, hevcParameterSets, ColorAspects.fromNames("bt709", "bt709", "video"))

    @Test
    fun prefersTheLowLatencyHardwareDecoder() {
        val plan = DecoderConfigPlanner.plan(
            request(),
            listOf(
                candidate("c2.android.hevc.decoder", hardware = false, software = true, vendor = false),
                candidate("c2.mtk.hevc.decoder.plain", lowLatency = false),
                candidate("c2.mtk.hevc.decoder"),
            ),
            mediatek,
        )
        assertEquals("c2.mtk.hevc.decoder", plan.codecName)
        assertTrue(plan.lowLatency)
    }

    @Test
    fun keepsListOrderAmongEquals() {
        val plan = DecoderConfigPlanner.plan(request(), listOf(candidate("first"), candidate("second")), mediatek)
        assertEquals("first", plan.codecName)
    }

    @Test
    fun prefersRealCodecsOverAliases() {
        val withAlias = DecoderConfigPlanner.plan(
            request(), listOf(candidate("alias", alias = true), candidate("c2.real.hevc")), mediatek,
        )
        assertEquals("c2.real.hevc", withAlias.codecName)
    }

    @Test
    fun neverFallsBackToSoftwareDecoders() {
        val error = assertFailsWith<NoDecoderException> {
            DecoderConfigPlanner.plan(
                request(),
                listOf(
                    candidate("c2.android.hevc.decoder", lowLatency = false, hardware = false, software = true),
                    candidate("c2.vendor.unflagged", hardware = false),
                ),
                mediatek,
            )
        }
        assertTrue("no hardware decoder" in (error.message ?: ""))
    }

    @Test
    fun honoursSizeSupportIncludingPortrait() {
        val landscapeOnly = SizeSupport { w, h -> w <= 4096 && h <= 2176 }
        val plan = DecoderConfigPlanner.plan(
            request(width = 1600, height = 2560),
            listOf(candidate("c2.mtk.small", size = landscapeOnly), candidate("c2.mtk.big", lowLatency = false)),
            mediatek,
        )
        assertEquals("c2.mtk.big", plan.codecName)
        assertTrue(SizeSupport.upTo(4096, 2176).isSupported(1600, 2560))
    }

    @Test
    fun failsWithoutAnyDecoderForTheMimeType() {
        assertFailsWith<NoDecoderException> {
            DecoderConfigPlanner.plan(request(mime = MIME_AVC), listOf(candidate("c2.mtk.hevc.decoder")), mediatek)
        }
    }

    @Test
    fun mediatekGetsLowLatencyKeysAndOperatingRateAtTheStreamRate() {
        val plan = DecoderConfigPlanner.plan(request(), listOf(candidate("c2.mtk.hevc.decoder")), mediatek)
        assertEquals(CodecVendor.MEDIATEK, plan.vendor)
        assertEquals(1, plan.intValue(KEY_LOW_LATENCY))
        assertEquals(0, plan.intValue(KEY_PRIORITY))
        assertEquals(1, plan.intValue(KEY_MEDIATEK_LOW_LATENCY))
        assertEquals(FormatValue.FloatValue(60f), plan.entries.single { it.key == KEY_OPERATING_RATE }.value)
        assertNull(plan.intValue(KEY_QUALCOMM_LOW_LATENCY))
        assertEquals(2560 * 1600, plan.intValue(KEY_MAX_INPUT_SIZE))
        assertEquals(1, plan.intValue(KEY_COLOR_STANDARD))
        assertEquals(2, plan.intValue(KEY_COLOR_RANGE))
        assertEquals(FormatValue.FloatValue(60f), plan.entries.single { it.key == KEY_FRAME_RATE }.value)
    }

    @Test
    fun lowLatencyIsAlwaysRequestedButOptionalWhenNotAdvertised() {
        val plan = DecoderConfigPlanner.plan(request(), listOf(candidate("c2.mtk.hevc.decoder", lowLatency = false)), mediatek)
        assertFalse(plan.lowLatency)
        assertEquals(1, plan.intValue(KEY_LOW_LATENCY))
        assertTrue(plan.entries.single { it.key == KEY_LOW_LATENCY }.optional)
        assertNull(plan.withoutOptionalEntries().intValue(KEY_LOW_LATENCY))
        assertEquals(0, plan.intValue(KEY_PRIORITY))
    }

    @Test
    fun operatingRateIsNeverPinnedToTheMaximum() {
        val plan = DecoderConfigPlanner.plan(request(fps = 120.0), listOf(candidate("c2.qti.hevc.decoder.low_latency")), qualcomm)
        assertEquals(CodecVendor.QUALCOMM, plan.vendor)
        assertEquals(FormatValue.FloatValue(120f), plan.entries.single { it.key == KEY_OPERATING_RATE }.value)
        assertEquals(1, plan.intValue(KEY_QUALCOMM_LOW_LATENCY))
        assertNull(plan.intValue(KEY_MEDIATEK_LOW_LATENCY))
        val unknownRate = DecoderConfigPlanner.plan(request(fps = null), listOf(candidate("c2.qti.hevc.decoder")), qualcomm)
        assertTrue(unknownRate.entries.none { it.key == KEY_OPERATING_RATE })
    }

    @Test
    fun operatingRateHeadroomIsOptInAndBounded() {
        val boosted = DecoderConfigPlanner.plan(
            request().copy(operatingRateFactor = 2.0), listOf(candidate("c2.mtk.hevc.decoder")), mediatek,
        )
        assertEquals(FormatValue.FloatValue(120f), boosted.entries.single { it.key == KEY_OPERATING_RATE }.value)
        assertFailsWith<IllegalArgumentException> { request().copy(operatingRateFactor = 100.0) }
    }

    @Test
    fun mediatekPostProcessingIsDisabled() {
        val plan = DecoderConfigPlanner.plan(request(), listOf(candidate("c2.mtk.hevc.decoder")), mediatek)
        assertEquals(1, plan.intValue(DecoderConfigPlanner.KEY_MEDIATEK_VPP_DISABLED))
        val qti = DecoderConfigPlanner.plan(request(), listOf(candidate("c2.qti.hevc.decoder")), qualcomm)
        assertNull(qti.intValue(DecoderConfigPlanner.KEY_MEDIATEK_VPP_DISABLED))
    }

    @Test
    fun vendorIsTakenFromTheCodecBeforeTheSoc() {
        assertEquals(CodecVendor.EXYNOS, CodecVendor.of("c2.exynos.hevc.decoder", mediatek))
        assertEquals(CodecVendor.MEDIATEK, CodecVendor.of("c2.vendor.hevc.decoder", mediatek))
        assertEquals(CodecVendor.OTHER, CodecVendor.of("c2.android.hevc.decoder", mediatek))
        val exynos = DecoderConfigPlanner.plan(request(), listOf(candidate("c2.exynos.hevc.decoder")), mediatek)
        assertEquals(1, exynos.intValue(KEY_EXYNOS_LOW_LATENCY))
    }

    @Test
    fun optionalEntriesCanBeDropped() {
        val plan = DecoderConfigPlanner.plan(request(), listOf(candidate("c2.mtk.hevc.decoder")), mediatek)
        val minimal = plan.withoutOptionalEntries()
        assertEquals(setOf(KEY_LOW_LATENCY, KEY_MAX_INPUT_SIZE), minimal.entries.map { it.key }.toSet())
        assertEquals(plan.codecSpecificData, minimal.codecSpecificData)
    }

    @Test
    fun aPlanCanBeRebuiltWithBiggerInputBuffers() {
        val plan = DecoderConfigPlanner.plan(request(), listOf(candidate("c2.mtk.hevc.decoder")), mediatek)
        val bigger = plan.withMaxInputSize(10_000_000)
        assertEquals(10_000_000, bigger.intValue(KEY_MAX_INPUT_SIZE))
        assertEquals(1, bigger.entries.count { it.key == KEY_MAX_INPUT_SIZE })
        assertEquals(plan.entries.size, bigger.entries.size)
        assertEquals(60f, bigger.frameRate)
        assertEquals(null, DecoderConfigPlanner.plan(request(fps = null), listOf(candidate("c2.mtk.hevc.decoder")), mediatek).frameRate)
    }

    @Test
    fun hevcParameterSetsBecomeOneCsdWithStartCodes() {
        val csd = DecoderConfigPlanner.codecSpecificData(MIME_HEVC, hevcParameterSets)
        assertEquals(listOf("csd-0"), csd.map { it.first })
        assertContentEquals(
            byteArrayOf(0, 0, 0, 1, 0x40, 0x01, 0x0C, 0, 0, 0, 1, 0x42, 0x01, 0x01, 0, 0, 0, 1, 0x44, 0x01, 0xC1.toByte()),
            csd.single().second,
        )
    }

    @Test
    fun avcSplitsSpsAndPps() {
        val sps = byteArrayOf(0x67, 0x64, 0x00, 0x33)
        val pps = byteArrayOf(0, 0, 0, 1, 0x68, 0xEE.toByte(), 0x3C, 0x80.toByte())
        val csd = DecoderConfigPlanner.codecSpecificData(MIME_AVC, listOf(pps, sps))
        assertEquals(listOf("csd-0", "csd-1"), csd.map { it.first })
        assertContentEquals(byteArrayOf(0, 0, 0, 1) + sps, csd[0].second)
        assertContentEquals(pps, csd[1].second, "an existing start code isn't doubled")
    }

    @Test
    fun noParameterSetsMeansNoCsd() {
        assertTrue(DecoderConfigPlanner.codecSpecificData(MIME_HEVC, emptyList()).isEmpty())
        assertTrue(DecoderConfigPlanner.codecSpecificData(MIME_HEVC, listOf(byteArrayOf(0, 0, 1))).isEmpty())
    }

    @Test
    fun smallStreamsStillGetAOneMebibyteInputBuffer() {
        assertEquals(1 shl 20, DecoderConfigPlanner.maxInputSize(request(width = 640, height = 400)))
        assertEquals(2960 * 1848, DecoderConfigPlanner.maxInputSize(request(width = 2960, height = 1848)))
    }

    @Test
    fun colourNamesMapToMediaFormatConstants() {
        assertEquals(ColorAspects(1, 2, 3), ColorAspects.fromNames("bt709", "bt709", "video"))
        assertEquals(ColorAspects(6, 1, 6), ColorAspects.fromNames("BT2020", "pq", "full"))
        assertEquals(ColorAspects(null, null, null), ColorAspects.fromNames("xyz", null, "weird"))
    }
}
