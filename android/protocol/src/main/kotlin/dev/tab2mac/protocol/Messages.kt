package dev.tab2mac.protocol

/** A typed protocol message (§3). [MessageCodec] converts between messages and [Frame]s. */
sealed interface Message {
    /** The wire type. */
    val type: MessageType
}

/** JSON-encoded control messages (§3.1). */
sealed interface ControlMessage : Message

/** Largest value of the protocol's u32 fields. */
internal const val U32_MAX: Long = 0xFFFF_FFFFL

/**
 * VIDEO_FRAME (§3.2): one encoded access unit.
 *
 * The access unit is `data[dataOffset until dataOffset + dataLength]`. A decoded frame is a view
 * into the received payload (no copy); when that payload came from a [ByteArrayPool], it is only
 * valid until the receiver releases it.
 *
 * @property frameId u32, increases by 1 per encoded frame and wraps.
 * @property captureTimeUs WindowServer composition time on the Mac host clock (§5), µs.
 * @property encodeDurationUs u32, submit → encoder output on the Mac, µs.
 * @property isKeyframe the header's KEYFRAME flag (IDR/IRAP).
 * @property isDiscardable the header's DISCARDABLE flag (no later frame references this one).
 */
class VideoFrame(
    val frameId: Long,
    val captureTimeUs: Long,
    val encodeDurationUs: Long,
    val isKeyframe: Boolean,
    val data: ByteArray,
    val isDiscardable: Boolean = false,
    val dataOffset: Int = 0,
    val dataLength: Int = data.size - dataOffset,
) : Message {
    init {
        require(frameId in 0..U32_MAX) { "frameId must be a u32" }
        require(encodeDurationUs in 0..U32_MAX) { "encodeDurationUs must be a u32" }
        require(dataOffset >= 0 && dataLength >= 0 && dataOffset + dataLength <= data.size) { "data range out of bounds" }
    }

    override val type: MessageType get() = MessageType.VIDEO_FRAME

    /** A copy of exactly the access unit. */
    fun dataBytes(): ByteArray = data.copyOfRange(dataOffset, dataOffset + dataLength)

    override fun equals(other: Any?): Boolean {
        if (other !is VideoFrame || frameId != other.frameId || captureTimeUs != other.captureTimeUs ||
            encodeDurationUs != other.encodeDurationUs || isKeyframe != other.isKeyframe ||
            isDiscardable != other.isDiscardable || dataLength != other.dataLength
        ) {
            return false
        }
        for (i in 0 until dataLength) if (data[dataOffset + i] != other.data[other.dataOffset + i]) return false
        return true
    }

    override fun hashCode(): Int = ((frameId.hashCode() * 31 + captureTimeUs.hashCode()) * 31 + dataLength)

    override fun toString(): String =
        "VideoFrame(frameId=$frameId, captureTimeUs=$captureTimeUs, encodeDurationUs=$encodeDurationUs, " +
            "keyframe=$isKeyframe, discardable=$isDiscardable, bytes=$dataLength)"

    companion object {
        /** v1 headerLength: 2 + 4 + 8 + 4. */
        const val HEADER_LENGTH_V1: Int = 18
    }
}

/** INPUT `kind` (§3.3). Unknown values are preserved. */
@JvmInline
value class InputKind(val raw: Int) {
    init {
        require(raw in 0..0xFF) { "kind must be a u8" }
    }

    companion object {
        val TOUCH = InputKind(1)
        val STYLUS = InputKind(2)
        val MOUSE = InputKind(3)
    }
}

/** INPUT `action` (§3.3). Unknown values are preserved. */
@JvmInline
value class InputAction(val raw: Int) {
    init {
        require(raw in 0..0xFF) { "action must be a u8" }
    }

    companion object {
        val DOWN = InputAction(0)
        val MOVE = InputAction(1)
        val UP = InputAction(2)
        val CANCEL = InputAction(3)
        val HOVER_ENTER = InputAction(4)
        val HOVER_MOVE = InputAction(5)
        val HOVER_EXIT = InputAction(6)

        /** An additional pointer went down; the changed pointer is the first record (see README). */
        val POINTER_DOWN = InputAction(7)

        /** An additional pointer went up; the changed pointer is the first record (see README). */
        val POINTER_UP = InputAction(8)
    }
}

/** Pointer `toolType` (§3.3). Unknown values are preserved. */
@JvmInline
value class ToolType(val raw: Int) {
    init {
        require(raw in 0..0xFF) { "toolType must be a u8" }
    }

    companion object {
        val UNKNOWN = ToolType(0)
        val FINGER = ToolType(1)
        val STYLUS = ToolType(2)
        val ERASER = ToolType(3)
        val MOUSE = ToolType(4)
    }
}

/** Pointer `buttons` bit mask (§3.3). */
@JvmInline
value class PointerButtons(val bits: Int) {
    init {
        require(bits in 0..0xFFFF) { "buttons must be a u16" }
    }

    operator fun plus(other: PointerButtons): PointerButtons = PointerButtons(bits or other.bits)

    operator fun contains(other: PointerButtons): Boolean = bits and other.bits == other.bits

    companion object {
        val NONE = PointerButtons(0)
        val PRIMARY = PointerButtons(1 shl 0)
        val SECONDARY = PointerButtons(1 shl 1)
        val STYLUS_PRIMARY = PointerButtons(1 shl 2)
        val STYLUS_SECONDARY = PointerButtons(1 shl 3)
    }
}

/**
 * One pointer of an INPUT message (§3.3).
 *
 * @property x normalised 0…65535 across the stream's width (current orientation).
 * @property y normalised 0…65535 across the stream's height.
 * @property pressure 0…65535, 0 while hovering.
 * @property tiltX −32767…32767 ↔ −90°…+90°; positive leans the pen's top end towards +x.
 * @property tiltY −32767…32767 ↔ −90°…+90°; positive leans the pen's top end towards +y.
 * @property distance hover distance in device units, 0 if unknown.
 */
data class PointerRecord(
    val pointerId: Int,
    val toolType: ToolType,
    val buttons: PointerButtons = PointerButtons.NONE,
    val x: Int,
    val y: Int,
    val pressure: Int = 0,
    val tiltX: Int = 0,
    val tiltY: Int = 0,
    val distance: Int = 0,
) {
    init {
        require(pointerId in 0..0xFF) { "pointerId must be a u8" }
        require(x in 0..0xFFFF && y in 0..0xFFFF) { "coordinates must be u16" }
        require(pressure in 0..0xFFFF) { "pressure must be a u16" }
        require(tiltX in Short.MIN_VALUE..Short.MAX_VALUE && tiltY in Short.MIN_VALUE..Short.MAX_VALUE) {
            "tilt must be an i16"
        }
        require(distance in 0..0xFFFF) { "distance must be a u16" }
    }

    companion object {
        /** v1 recordLength: 2 + 1 + 1 + 2 + 2 + 2 + 2 + 2 + 2 + 2. */
        const val RECORD_LENGTH_V1: Int = 18

        /** Largest normalised coordinate / pressure. */
        const val MAX_NORMALIZED: Int = 0xFFFF

        /** Tilt value for ±90°. */
        const val MAX_TILT: Int = 32767
    }
}

/**
 * INPUT (§3.3): one touch, stylus or mouse event.
 *
 * @property sequence u32, increases by 1 per message and wraps.
 * @property eventTimeUs Android clock (§5): `MotionEvent` event time in µs.
 */
data class InputMessage(
    val sequence: Long,
    val eventTimeUs: Long,
    val kind: InputKind,
    val action: InputAction,
    val pointers: List<PointerRecord>,
) : Message {
    init {
        require(sequence in 0..U32_MAX) { "sequence must be a u32" }
        require(pointers.size <= 0xFF) { "at most 255 pointers" }
    }

    override val type: MessageType get() = MessageType.INPUT

    companion object {
        /** v1 headerLength: 2 + 4 + 8 + 1 + 1 (pointerCount follows the header). */
        const val HEADER_LENGTH_V1: Int = 16
    }
}

/** PING (§3.4): `id` u32, `t1` sender clock at send (µs). */
data class Ping(val id: Long, val t1: Long) : Message {
    init {
        require(id in 0..U32_MAX) { "id must be a u32" }
    }

    override val type: MessageType get() = MessageType.PING
}

/**
 * CURSOR (§3.3b, Mac → tablet): where the pointer's hotspot is, [x]/[y] normalized to 0…65535
 * across the display (as INPUT). [visible] false: it is on another display. [shapeId] names a
 * [CursorShape] sent earlier (never 0 while visible). [timeUs] is the Mac clock.
 */
data class CursorPosition(
    val sequence: Long,
    val timeUs: Long,
    val x: Int,
    val y: Int,
    val visible: Boolean,
    val shapeId: Long,
) : Message {
    init {
        require(sequence in 0..U32_MAX) { "sequence must be a u32" }
        require(x in 0..0xFFFF && y in 0..0xFFFF) { "x and y must be u16" }
        require(shapeId in 0..U32_MAX) { "shapeId must be a u32" }
    }

    override val type: MessageType get() = MessageType.CURSOR

    companion object {
        const val HEADER_LENGTH_V1: Int = 24
    }
}

/**
 * CURSOR_SHAPE (§3.3b, Mac → tablet): pointer image [shapeId] (nonzero; the same image always has
 * the same id), [width] × [height] stream pixels with its hotspot, as a PNG with alpha. Receivers
 * cache it by id for the session.
 */
class CursorShape(
    val shapeId: Long,
    val width: Int,
    val height: Int,
    val hotspotX: Int,
    val hotspotY: Int,
    val png: ByteArray,
) : Message {
    init {
        require(shapeId in 0..U32_MAX) { "shapeId must be a u32" }
        require(width in 0..0xFFFF && height in 0..0xFFFF && hotspotX in 0..0xFFFF && hotspotY in 0..0xFFFF) { "sizes must be u16" }
    }

    override val type: MessageType get() = MessageType.CURSOR_SHAPE

    override fun equals(other: Any?): Boolean =
        other is CursorShape && shapeId == other.shapeId && width == other.width && height == other.height &&
            hotspotX == other.hotspotX && hotspotY == other.hotspotY && png.contentEquals(other.png)

    override fun hashCode(): Int = (shapeId.hashCode() * 31 + width) * 31 + height

    override fun toString(): String =
        "CursorShape(shapeId=$shapeId, ${width}x$height, hotspot=$hotspotX,$hotspotY, png=${png.size} bytes)"

    companion object {
        const val HEADER_LENGTH_V1: Int = 14
    }
}

/** KEY `action` (§3.3c). */
@JvmInline
value class KeyAction(val raw: Int) {
    companion object {
        /** Pressed; a held key repeats with more downs. */
        val DOWN = KeyAction(0)
        val UP = KeyAction(1)
    }
}

/**
 * KEY (§3.3c, tablet → Mac): a physical key of a keyboard attached to the tablet, as a USB HID
 * [usage] on the Keyboard/Keypad page 0x07 (modifiers are keys too, 0xE0–0xE7). [modifiers] is the
 * state after this event: bit 0 left control, 1 left shift, 2 left alt, 3 left meta, 4–7 the
 * right ones, 8 caps lock on. The Mac applies its own layout.
 */
data class KeyMessage(
    val sequence: Long,
    val eventTimeUs: Long,
    val action: KeyAction,
    val usage: Int,
    val modifiers: Int,
) : Message {
    init {
        require(sequence in 0..U32_MAX) { "sequence must be a u32" }
        require(action.raw in 0..0xFF) { "action must be a u8" }
        require(usage in 0..0xFFFF && modifiers in 0..0xFFFF) { "usage and modifiers must be u16" }
    }

    override val type: MessageType get() = MessageType.KEY

    companion object {
        const val HEADER_LENGTH_V1: Int = 20
    }
}

/** PONG (§3.4): echoes `id` and `t1`; `t2`/`t3` are the responder's clock at receipt and send (µs). */
data class Pong(val id: Long, val t1: Long, val t2: Long, val t3: Long) : Message {
    init {
        require(id in 0..U32_MAX) { "id must be a u32" }
    }

    override val type: MessageType get() = MessageType.PONG
}

/**
 * A type this implementation doesn't know. Receivers skip it when [flags] has IGNORABLE and
 * answer ERROR `unsupported` otherwise (§1); either way the connection stays open. Kept intact so
 * it can be logged or re-encoded.
 */
class UnknownMessage(
    val rawType: Int,
    val flags: FrameFlags,
    val stream: StreamId,
    val payload: ByteArray,
) : Message {
    override val type: MessageType get() = MessageType(rawType)

    override fun equals(other: Any?): Boolean =
        other is UnknownMessage && rawType == other.rawType && flags == other.flags && stream == other.stream &&
            payload.contentEquals(other.payload)

    override fun hashCode(): Int = rawType * 31 + payload.contentHashCode()

    override fun toString(): String = "UnknownMessage(type=0x%02x, flags=$flags, stream=$stream, bytes=${payload.size})".format(rawType)
}
