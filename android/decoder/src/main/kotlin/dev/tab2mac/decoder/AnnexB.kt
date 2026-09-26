package dev.tab2mac.decoder

/** Annex‑B helpers for codec-specific data (parameter sets with start codes). */
object AnnexB {
    /** The 4-byte start code MediaCodec expects in `csd-*` buffers. */
    val START_CODE: ByteArray get() = byteArrayOf(0, 0, 0, 1)

    /** Length of a leading start code (3 or 4 bytes), or 0 if there is none. */
    fun startCodeLength(nal: ByteArray): Int = when {
        nal.size >= 4 && nal[0] == ZERO && nal[1] == ZERO && nal[2] == ZERO && nal[3] == ONE -> 4
        nal.size >= 3 && nal[0] == ZERO && nal[1] == ZERO && nal[2] == ONE -> 3
        else -> 0
    }

    /** [nal] with a start code, unless it already has one. */
    fun withStartCode(nal: ByteArray): ByteArray = if (startCodeLength(nal) > 0) nal else START_CODE + nal

    /** Every NAL unit with a start code, concatenated. */
    fun join(nals: List<ByteArray>): ByteArray = nals.fold(ByteArray(0)) { acc, nal -> acc + withStartCode(nal) }

    /** H.264 `nal_unit_type` (7 = SPS, 8 = PPS), or -1 for an empty unit. */
    fun avcNalType(nal: ByteArray): Int {
        val offset = startCodeLength(nal)
        return if (nal.size > offset) nal[offset].toInt() and 0x1F else -1
    }

    /** HEVC `nal_unit_type` (32 = VPS, 33 = SPS, 34 = PPS), or -1 for an empty unit. */
    fun hevcNalType(nal: ByteArray): Int {
        val offset = startCodeLength(nal)
        return if (nal.size > offset) (nal[offset].toInt() ushr 1) and 0x3F else -1
    }

    private const val ZERO: Byte = 0
    private const val ONE: Byte = 1
}
