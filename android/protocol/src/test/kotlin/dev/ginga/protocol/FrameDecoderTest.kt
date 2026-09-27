package dev.ginga.protocol

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class FrameDecoderTest {
    private val ping = Frame(MessageType.PING, FrameFlags.NONE, StreamId.CONTROL, byteArrayOf(0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2))
    private val video = Frame(MessageType.VIDEO_FRAME, FrameFlags.KEYFRAME, StreamId.VIDEO, ByteArray(5000) { it.toByte() })
    private val empty = Frame(MessageType(0x7E), FrameFlags.IGNORABLE, StreamId.TELEMETRY, ByteArray(0))

    @Test
    fun headerLayoutMatchesTheSpecification() {
        val bytes = FrameCodec.encode(Frame(MessageType.INPUT, FrameFlags(0x0102), StreamId(0x0304), byteArrayOf(9, 8, 7)))
        // magic "GN" · fver 1 · type 0x11 · flags 0x0102 · stream 0x0304 · length 3 · payload
        assertEquals("474e" + "01" + "11" + "0102" + "0304" + "00000003" + "090807", bytes.toHex())
    }

    @Test
    fun roundTripsSingleFrames() {
        for (frame in listOf(ping, video, empty)) {
            val decoded = FrameDecoder().feed(FrameCodec.encode(frame))
            assertEquals(listOf(frame), decoded)
        }
    }

    @Test
    fun reassemblesByteByByteDelivery() {
        val bytes = FrameCodec.encode(ping) + FrameCodec.encode(video)
        val decoder = FrameDecoder()
        val frames = mutableListOf<Frame>()
        for (i in bytes.indices) frames += decoder.feed(bytes, i, 1)
        assertEquals(listOf(ping, video), frames)
        assertEquals(0, decoder.bufferedByteCount)
    }

    @Test
    fun splitsCoalescedFrames() {
        val bytes = FrameCodec.encode(ping) + FrameCodec.encode(empty) + FrameCodec.encode(video) + FrameCodec.encode(ping)
        assertEquals(listOf(ping, empty, video, ping), FrameDecoder().feed(bytes))
    }

    @Test
    fun handlesArbitraryChunkBoundaries() {
        val bytes = FrameCodec.encode(video) + FrameCodec.encode(ping) + FrameCodec.encode(video)
        for (chunk in listOf(3, 11, 12, 13, 1000, 4999)) {
            val decoder = FrameDecoder()
            val frames = mutableListOf<Frame>()
            var offset = 0
            while (offset < bytes.size) {
                val length = minOf(chunk, bytes.size - offset)
                decoder.feed(bytes, offset, length) { frames += it }
                offset += length
            }
            assertEquals(listOf(video, ping, video), frames, "chunk size $chunk")
        }
    }

    @Test
    fun incompleteInputYieldsNothingYet() {
        val bytes = FrameCodec.encode(video)
        val decoder = FrameDecoder()
        assertTrue(decoder.feed(bytes, 0, 11).isEmpty())
        assertTrue(decoder.feed(bytes, 11, 100).isEmpty())
        assertEquals(111, decoder.bufferedByteCount)
        val rest = decoder.feed(bytes, 111, bytes.size - 111)
        assertEquals(1, rest.size)
        assertContentEquals(video.payload, rest.single().payload)
    }

    @Test
    fun rejectsBadMagic() {
        val bytes = FrameCodec.encode(ping).also { it[0] = 0x55 }
        val error = assertFailsWith<ProtocolException.BadMagic> { FrameDecoder().feed(bytes) }
        assertEquals(0x554E, error.value)
        assertTrue(error.isFatalForConnection)
    }

    @Test
    fun rejectsUnsupportedFramingVersion() {
        val bytes = FrameCodec.encode(ping).also { it[2] = 2 }
        val error = assertFailsWith<ProtocolException.UnsupportedFramingVersion> { FrameDecoder().feed(bytes) }
        assertEquals(2, error.version)
    }

    @Test
    fun rejectsPayloadsOver16MiB() {
        val header = FrameCodec.header(ping)
        // length = 16 MiB + 1
        val tooLong = FrameCodec.MAX_PAYLOAD_LENGTH + 1
        header[8] = (tooLong ushr 24).toByte()
        header[9] = (tooLong ushr 16).toByte()
        header[10] = (tooLong ushr 8).toByte()
        header[11] = tooLong.toByte()
        val error = assertFailsWith<ProtocolException.PayloadTooLarge> { FrameDecoder().feed(header) }
        assertEquals(tooLong.toLong(), error.length)
    }

    @Test
    fun accepts16MiBExactlyAsTheLimit() {
        val header = FrameCodec.header(ping)
        val limit = FrameCodec.MAX_PAYLOAD_LENGTH
        header[8] = (limit ushr 24).toByte()
        header[9] = (limit ushr 16).toByte()
        header[10] = (limit ushr 8).toByte()
        header[11] = limit.toByte()
        val decoder = FrameDecoder()
        assertTrue(decoder.feed(header).isEmpty())
        assertEquals(FrameCodec.HEADER_SIZE, decoder.bufferedByteCount)
    }

    @Test
    fun rejectsLengthsThatOverflowAnInt() {
        val header = FrameCodec.header(ping)
        header[8] = 0xFF.toByte()
        header[9] = 0xFF.toByte()
        header[10] = 0xFF.toByte()
        header[11] = 0xFF.toByte()
        val error = assertFailsWith<ProtocolException.PayloadTooLarge> { FrameDecoder().feed(header) }
        assertEquals(0xFFFF_FFFFL, error.length)
    }

    @Test
    fun staysFailedAfterAFramingError() {
        val decoder = FrameDecoder()
        assertFailsWith<ProtocolException.BadMagic> { decoder.feed(byteArrayOf(0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0)) }
        assertFailsWith<ProtocolException.BadMagic> { decoder.feed(FrameCodec.encode(ping)) }
    }

    @Test
    fun preservesUnknownFlagsAndStreams() {
        val frame = Frame(MessageType(0x42), FrameFlags(0xFFFF), StreamId(0xBEEF), byteArrayOf(1))
        val decoded = FrameDecoder().feed(FrameCodec.encode(frame)).single()
        assertEquals(frame, decoded)
        assertTrue(decoded.flags.isIgnorable && decoded.flags.isKeyframe && decoded.flags.isDiscardable)
    }

    @Test
    fun resyncSkipsLeftoverBytesBeforeTheFirstFrame() {
        val welcome = FrameCodec.encode(Frame(MessageType.WELCOME, FrameFlags.NONE, StreamId.CONTROL, "{}".encodeToByteArray()))
        // The tail of a previous connection's partial write, including a false "GN" start.
        val garbage = "b0b4".hexToBytes() + byteArrayOf(0x47, 0x4E, 0x07, 0x7F) + ByteArray(20) { (it * 37).toByte() }
        val decoder = FrameDecoder(resyncUntilFirstFrame = true)
        val stream = garbage + welcome
        val frames = mutableListOf<Frame>()
        for (i in stream.indices step 5) decoder.feed(stream, i, minOf(5, stream.size - i)) { frames += it } // split reads too
        assertEquals(MessageType.WELCOME, frames.single().type)
        assertEquals(garbage.size.toLong(), decoder.skippedByteCount)
    }

    @Test
    fun afterTheFirstFrameABadHeaderIsStillAnError() {
        val ping = FrameCodec.encode(MessageCodec.encode(Ping(1, 2)))
        val decoder = FrameDecoder(resyncUntilFirstFrame = true)
        assertEquals(1, decoder.feed(ping).size)
        assertFailsWith<ProtocolException.BadMagic> { decoder.feed(ByteArray(12) { 0x7F }) }
    }

    @Test
    fun withoutResyncLeftoverBytesAreAnError() {
        assertFailsWith<ProtocolException.BadMagic> { FrameDecoder().feed("b0b4".hexToBytes() + ByteArray(10)) }
    }

    @Test
    fun resyncRejectsImplausibleHeaders() {
        // Unknown non-IGNORABLE type, then an oversized length: both skipped, then a real PONG.
        val unknownType = byteArrayOf(0x47, 0x4E, 0x01, 0x7D, 0, 0, 0, 0, 0, 0, 0, 0)
        val tooLong = byteArrayOf(0x47, 0x4E, 0x01, 0x01, 0, 0, 0, 0, 0x7F, 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte())
        val pong = FrameCodec.encode(MessageCodec.encode(Pong(1, 2, 3, 4)))
        val decoder = FrameDecoder(resyncUntilFirstFrame = true)
        val frames = decoder.feed(unknownType + tooLong + pong)
        assertEquals(Pong(1, 2, 3, 4), MessageCodec.decode(frames.single()))
        assertEquals(24L, decoder.skippedByteCount)
    }
}
