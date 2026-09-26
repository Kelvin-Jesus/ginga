package dev.tab2mac.protocol

/**
 * A message type byte (PROTOCOL.md §3). Unknown values are representable so that
 * IGNORABLE messages from newer peers can be skipped instead of failing.
 */
@JvmInline
value class MessageType(val code: Int) {
    init {
        require(code in 0..0xFF) { "message type must be a u8, was $code" }
    }

    /** The §3 name (`HELLO`, `VIDEO_FRAME`, …) or `UNKNOWN(0x7e)`. */
    val displayName: String get() = NAMES[code] ?: "UNKNOWN(0x%02x)".format(code)

    /** Whether this implementation knows the type. */
    val isKnown: Boolean get() = code in NAMES

    /** JSON-encoded control message (as opposed to the binary hot-path messages). */
    val isJson: Boolean get() = isKnown && this !in BINARY

    /** The stream a known type travels on (§3 table); CONTROL for unknown types. */
    val defaultStream: StreamId
        get() = when (this) {
            STREAM_FORMAT, KEYFRAME_REQUEST, VIDEO_FRAME -> StreamId.VIDEO
            INPUT, KEY -> StreamId.INPUT
            CURSOR, CURSOR_SHAPE -> StreamId.CURSOR
            RECEIVER_REPORT -> StreamId.TELEMETRY
            else -> StreamId.CONTROL
        }

    override fun toString(): String = displayName

    companion object {
        val HELLO = MessageType(0x01)
        val WELCOME = MessageType(0x02)
        val CONFIGURE = MessageType(0x03)
        val STREAM_FORMAT = MessageType(0x04)
        val RECEIVER_REPORT = MessageType(0x05)
        val KEYFRAME_REQUEST = MessageType(0x06)

        /** Wi‑Fi only (§6); sent with IGNORABLE. */
        val PAIRING = MessageType(0x07)

        /** §6b, IGNORABLE: the no-router key, over an authenticated session. */
        val DIRECT_LINK = MessageType(0x08)
        val ERROR = MessageType(0x0E)
        val GOODBYE = MessageType(0x0F)
        val VIDEO_FRAME = MessageType(0x10)
        val INPUT = MessageType(0x11)

        /** §3.3b, IGNORABLE: the pointer's position, drawn by the tablet. */
        val CURSOR = MessageType(0x12)

        /** §3.3b, IGNORABLE: a pointer image, sent once per shape per session. */
        val CURSOR_SHAPE = MessageType(0x13)

        /** §3.3c, IGNORABLE: a key of a keyboard attached to the tablet. */
        val KEY = MessageType(0x14)
        val PING = MessageType(0x20)
        val PONG = MessageType(0x21)

        private val NAMES: Map<Int, String> = mapOf(
            0x01 to "HELLO",
            0x02 to "WELCOME",
            0x03 to "CONFIGURE",
            0x04 to "STREAM_FORMAT",
            0x05 to "RECEIVER_REPORT",
            0x06 to "KEYFRAME_REQUEST",
            0x07 to "PAIRING",
            0x08 to "DIRECT_LINK",
            0x0E to "ERROR",
            0x0F to "GOODBYE",
            0x10 to "VIDEO_FRAME",
            0x11 to "INPUT",
            0x12 to "CURSOR",
            0x13 to "CURSOR_SHAPE",
            0x14 to "KEY",
            0x20 to "PING",
            0x21 to "PONG",
        )

        private val BINARY = setOf(VIDEO_FRAME, INPUT, CURSOR, CURSOR_SHAPE, KEY, PING, PONG)

        /** Looks a type up by its §3 name, e.g. `"STREAM_FORMAT"`. */
        fun fromName(name: String): MessageType? =
            NAMES.entries.firstOrNull { it.value == name }?.let { MessageType(it.key) }
    }
}

/** Header flags (§2). Reserved bits are preserved on receipt and never set by this implementation. */
@JvmInline
value class FrameFlags(val bits: Int) {
    init {
        require(bits in 0..0xFFFF) { "flags must be a u16, was $bits" }
    }

    /** Receivers that don't know the type may skip the message. */
    val isIgnorable: Boolean get() = bits and IGNORABLE.bits != 0

    /** Video: IDR/IRAP frame. */
    val isKeyframe: Boolean get() = bits and KEYFRAME.bits != 0

    /** May be dropped under backpressure (§4). */
    val isDiscardable: Boolean get() = bits and DISCARDABLE.bits != 0

    operator fun plus(other: FrameFlags): FrameFlags = FrameFlags(bits or other.bits)

    operator fun contains(other: FrameFlags): Boolean = bits and other.bits == other.bits

    override fun toString(): String = "0x%04x".format(bits)

    companion object {
        val NONE = FrameFlags(0)
        val IGNORABLE = FrameFlags(1 shl 0)
        val KEYFRAME = FrameFlags(1 shl 1)
        val DISCARDABLE = FrameFlags(1 shl 2)
    }
}

/** Logical stream (§2). Unknown values are preserved. */
@JvmInline
value class StreamId(val id: Int) {
    init {
        require(id in 0..0xFFFF) { "stream must be a u16, was $id" }
    }

    override fun toString(): String = when (this) {
        CONTROL -> "control"
        VIDEO -> "video"
        INPUT -> "input"
        CURSOR -> "cursor"
        TELEMETRY -> "telemetry"
        else -> "stream-$id"
    }

    companion object {
        val CONTROL = StreamId(0)
        val VIDEO = StreamId(1)
        val INPUT = StreamId(2)
        val CURSOR = StreamId(3)
        val TELEMETRY = StreamId(4)
    }
}

/**
 * One framed message before its payload is interpreted (§2): the 12-byte header fields plus
 * the payload, which is `payload[0 until payloadLength]`. The array can be longer than the
 * payload when it comes from a [ByteArrayPool] (received VIDEO_FRAMEs), so always use
 * [payloadLength], never `payload.size`.
 */
class Frame(
    val type: MessageType,
    val flags: FrameFlags,
    val stream: StreamId,
    val payload: ByteArray,
    val payloadLength: Int = payload.size,
) {
    init {
        require(payloadLength in 0..payload.size) { "payloadLength $payloadLength outside 0..${payload.size}" }
        require(payloadLength <= FrameCodec.MAX_PAYLOAD_LENGTH) {
            "payload of $payloadLength bytes exceeds ${FrameCodec.MAX_PAYLOAD_LENGTH}"
        }
    }

    /** Header plus payload, as it travels on the wire. */
    val wireSize: Int get() = FrameCodec.HEADER_SIZE + payloadLength

    /** A copy of exactly the payload bytes. */
    fun payloadBytes(): ByteArray = payload.copyOf(payloadLength)

    override fun equals(other: Any?): Boolean {
        if (other !is Frame || type != other.type || flags != other.flags || stream != other.stream) return false
        if (payloadLength != other.payloadLength) return false
        for (i in 0 until payloadLength) if (payload[i] != other.payload[i]) return false
        return true
    }

    override fun hashCode(): Int {
        var hash = ((type.code * 31 + flags.bits) * 31 + stream.id) * 31 + payloadLength
        for (i in 0 until minOf(payloadLength, 64)) hash = hash * 31 + payload[i]
        return hash
    }

    override fun toString(): String = "Frame(type=$type, flags=$flags, stream=$stream, length=$payloadLength)"
}

/** Encodes the §2 framing. Decoding of byte streams is [FrameDecoder]'s job. */
object FrameCodec {
    /** Bytes in the fixed header. */
    const val HEADER_SIZE: Int = 12

    /** `"T2"`. */
    const val MAGIC: Int = 0x5432

    /** Framing version; changes only for incompatible framing changes. */
    const val FRAMING_VERSION: Int = 1

    /** 16 MiB. Larger payloads are a protocol error. */
    const val MAX_PAYLOAD_LENGTH: Int = 16 * 1024 * 1024

    /** The 12-byte header of [frame]. */
    fun header(frame: Frame): ByteArray = ByteArray(HEADER_SIZE).also { writeHeader(frame, it) }

    /** Writes the header of [frame] into `destination[offset until offset + 12]` (no allocation). */
    fun writeHeader(frame: Frame, destination: ByteArray, offset: Int = 0) {
        writeHeader(destination, offset, frame.type, frame.flags, frame.stream, frame.payloadLength)
    }

    /** Header followed by payload in one array. */
    fun encode(frame: Frame): ByteArray {
        val bytes = ByteArray(frame.wireSize)
        writeHeader(frame, bytes)
        frame.payload.copyInto(bytes, HEADER_SIZE, 0, frame.payloadLength)
        return bytes
    }

    private fun writeHeader(
        destination: ByteArray,
        offset: Int,
        type: MessageType,
        flags: FrameFlags,
        stream: StreamId,
        payloadLength: Int,
    ) {
        var i = offset
        destination[i++] = (MAGIC ushr 8).toByte()
        destination[i++] = MAGIC.toByte()
        destination[i++] = FRAMING_VERSION.toByte()
        destination[i++] = type.code.toByte()
        destination[i++] = (flags.bits ushr 8).toByte()
        destination[i++] = flags.bits.toByte()
        destination[i++] = (stream.id ushr 8).toByte()
        destination[i++] = stream.id.toByte()
        destination[i++] = (payloadLength ushr 24).toByte()
        destination[i++] = (payloadLength ushr 16).toByte()
        destination[i++] = (payloadLength ushr 8).toByte()
        destination[i] = payloadLength.toByte()
    }
}
