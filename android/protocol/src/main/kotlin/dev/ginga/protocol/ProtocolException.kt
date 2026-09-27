package dev.ginga.protocol

/** Everything that can be wrong with bytes received from a peer. Never thrown for local programming errors. */
sealed class ProtocolException(message: String, cause: Throwable? = null) : Exception(message, cause) {

    /**
     * Framing errors leave the byte stream unsynchronised. Per §2 the receiver sends ERROR and
     * closes the connection. Other errors concern a single message, which can be skipped.
     */
    open val isFatalForConnection: Boolean get() = false

    /** The first two header bytes weren't `"GN"`. */
    class BadMagic(val value: Int) : ProtocolException("bad magic 0x%04x".format(value)) {
        override val isFatalForConnection: Boolean get() = true
    }

    /** The framing version byte isn't [FrameCodec.FRAMING_VERSION]. */
    class UnsupportedFramingVersion(val version: Int) : ProtocolException("unsupported framing version $version") {
        override val isFatalForConnection: Boolean get() = true
    }

    /** The header announced more than [FrameCodec.MAX_PAYLOAD_LENGTH] bytes. */
    class PayloadTooLarge(val length: Long) :
        ProtocolException("payload of $length bytes exceeds ${FrameCodec.MAX_PAYLOAD_LENGTH}") {
        override val isFatalForConnection: Boolean get() = true
    }

    /** A binary payload ended before a required field. */
    class Truncated(detail: String) : ProtocolException("truncated message: $detail")

    /** A binary payload is structurally invalid (for example a headerLength below v1). */
    class Malformed(detail: String) : ProtocolException("malformed message: $detail")

    /** A JSON payload didn't parse into the message's schema. */
    class InvalidJson(val messageName: String, reason: String, cause: Throwable? = null) :
        ProtocolException("invalid $messageName JSON: $reason", cause)
}
