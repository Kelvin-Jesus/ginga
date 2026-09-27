package dev.ginga.decoder

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertSame

class AnnexBTest {
    @Test
    fun detectsThreeAndFourByteStartCodes() {
        assertEquals(4, AnnexB.startCodeLength(byteArrayOf(0, 0, 0, 1, 0x40)))
        assertEquals(3, AnnexB.startCodeLength(byteArrayOf(0, 0, 1, 0x40)))
        assertEquals(0, AnnexB.startCodeLength(byteArrayOf(0x40, 0x01)))
        assertEquals(0, AnnexB.startCodeLength(byteArrayOf(0, 0)))
    }

    @Test
    fun addsAStartCodeOnlyWhenMissing() {
        val bare = byteArrayOf(0x42, 0x01)
        assertContentEquals(byteArrayOf(0, 0, 0, 1, 0x42, 0x01), AnnexB.withStartCode(bare))
        val prefixed = byteArrayOf(0, 0, 1, 0x42)
        assertSame(prefixed, AnnexB.withStartCode(prefixed))
    }

    @Test
    fun readsNalUnitTypes() {
        assertEquals(32, AnnexB.hevcNalType(byteArrayOf(0x40, 0x01))) // VPS
        assertEquals(33, AnnexB.hevcNalType(byteArrayOf(0, 0, 0, 1, 0x42, 0x01))) // SPS
        assertEquals(34, AnnexB.hevcNalType(byteArrayOf(0x44, 0x01))) // PPS
        assertEquals(7, AnnexB.avcNalType(byteArrayOf(0x67)))
        assertEquals(8, AnnexB.avcNalType(byteArrayOf(0, 0, 1, 0x68)))
        assertEquals(-1, AnnexB.avcNalType(byteArrayOf(0, 0, 1)))
    }
}
