package dev.ginga.protocol

/**
 * Incremental parser for stream transports (§2): feed arbitrary chunks, receive complete frames.
 *
 * Frames split across reads and several frames coalesced into one read are both handled. The
 * payload of a frame is allocated once, when its header is complete, and filled in place, so
 * large video frames are never copied more than once.
 *
 * Payload arrays come from [allocator], so video payloads can be recycled through a
 * [ByteArrayPool] (the emitted [Frame] then has an array longer than its [Frame.payloadLength]).
 *
 * A framing error (bad magic, unsupported framing version, payload over 16 MiB) is thrown as a
 * [ProtocolException] and leaves the decoder failed: the stream is unsynchronised and the
 * connection must be closed. Further calls rethrow the same error.
 *
 * With [resyncUntilFirstFrame] (links that can start with the tail of an earlier connection, such
 * as a reopened USB accessory), bytes are skipped one at a time until a plausible header appears —
 * magic, framing version 1, a known or IGNORABLE type, a length within the limit — and only until
 * the first frame is complete; from then on any bad header is an error as usual.
 *
 * Not thread-safe; use one instance per connection from a single reader thread.
 */
class FrameDecoder(
    private val maxPayloadLength: Int = FrameCodec.MAX_PAYLOAD_LENGTH,
    private val allocator: PayloadAllocator = PayloadAllocator.EXACT,
    resyncUntilFirstFrame: Boolean = false,
) {
    private var resyncing = resyncUntilFirstFrame

    /** Bytes skipped while looking for the first frame ([resyncUntilFirstFrame]). */
    var skippedByteCount: Long = 0
        private set

    private val header = ByteArray(FrameCodec.HEADER_SIZE)
    private var headerFill = 0
    private var pendingType = MessageType.HELLO
    private var pendingFlags = FrameFlags.NONE
    private var pendingStream = StreamId.CONTROL
    private var payload: ByteArray? = null
    private var payloadLength = 0
    private var payloadFill = 0
    private var failure: ProtocolException? = null

    /** Bytes of an incomplete frame held right now. */
    val bufferedByteCount: Int get() = headerFill + payloadFill

    /**
     * Consumes `bytes[offset until offset + length]` and calls [onFrame] for every frame that
     * became complete, in stream order.
     *
     * @throws ProtocolException on a framing error; see the class documentation.
     */
    fun feed(bytes: ByteArray, offset: Int = 0, length: Int = bytes.size - offset, onFrame: (Frame) -> Unit) {
        require(offset >= 0 && length >= 0 && offset + length <= bytes.size) { "range out of bounds" }
        failure?.let { throw it }
        var position = offset
        val end = offset + length
        while (position < end) {
            val body = payload
            if (body == null) {
                val count = minOf(FrameCodec.HEADER_SIZE - headerFill, end - position)
                bytes.copyInto(header, headerFill, position, position + count)
                headerFill += count
                position += count
                if (headerFill == FrameCodec.HEADER_SIZE) {
                    if (resyncing && !plausibleHeader()) {
                        // Not a frame start: drop one byte and look again.
                        header.copyInto(header, 0, 1, FrameCodec.HEADER_SIZE)
                        headerFill = FrameCodec.HEADER_SIZE - 1
                        skippedByteCount++
                        continue
                    }
                    val announced = parseHeader()
                    if (announced == 0) {
                        emit(EMPTY, 0, onFrame)
                    } else {
                        val array = allocator.allocate(pendingType, announced)
                        check(array.size >= announced) { "allocator returned ${array.size} < $announced bytes" }
                        payload = array
                        payloadLength = announced
                        payloadFill = 0
                    }
                }
            } else {
                val count = minOf(payloadLength - payloadFill, end - position)
                bytes.copyInto(body, payloadFill, position, position + count)
                payloadFill += count
                position += count
                if (payloadFill == payloadLength) emit(body, payloadLength, onFrame)
            }
        }
    }

    /** Convenience for tests and simple callers: the frames completed by this chunk. */
    fun feed(bytes: ByteArray, offset: Int = 0, length: Int = bytes.size - offset): List<Frame> {
        val frames = ArrayList<Frame>(2)
        feed(bytes, offset, length) { frames += it }
        return frames
    }

    private fun plausibleHeader(): Boolean {
        if (u16(0) != FrameCodec.MAGIC || (header[2].toInt() and 0xFF) != FrameCodec.FRAMING_VERSION) return false
        val type = MessageType(header[3].toInt() and 0xFF)
        if (!type.isKnown && !FrameFlags(u16(4)).isIgnorable) return false
        val length = (u16(8).toLong() shl 16) or u16(10).toLong()
        return length <= maxPayloadLength
    }

    /** Reads the completed header in place (no allocation per frame). */
    private fun parseHeader(): Int {
        val magic = u16(0)
        if (magic != FrameCodec.MAGIC) fail(ProtocolException.BadMagic(magic))
        val version = header[2].toInt() and 0xFF
        if (version != FrameCodec.FRAMING_VERSION) fail(ProtocolException.UnsupportedFramingVersion(version))
        pendingType = MessageType(header[3].toInt() and 0xFF)
        pendingFlags = FrameFlags(u16(4))
        pendingStream = StreamId(u16(6))
        val length = (u16(8).toLong() shl 16) or u16(10).toLong()
        if (length > maxPayloadLength) fail(ProtocolException.PayloadTooLarge(length))
        return length.toInt()
    }

    private fun u16(at: Int): Int = ((header[at].toInt() and 0xFF) shl 8) or (header[at + 1].toInt() and 0xFF)

    private fun emit(body: ByteArray, length: Int, onFrame: (Frame) -> Unit) {
        val frame = Frame(pendingType, pendingFlags, pendingStream, body, length)
        resyncing = false
        headerFill = 0
        payload = null
        payloadLength = 0
        payloadFill = 0
        onFrame(frame)
    }

    private fun fail(error: ProtocolException): Nothing {
        failure = error
        throw error
    }

    private companion object {
        val EMPTY = ByteArray(0)
    }
}
