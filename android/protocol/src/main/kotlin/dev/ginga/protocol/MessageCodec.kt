package dev.ginga.protocol

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException

/** Converts between typed [Message]s and [Frame]s (§3). */
object MessageCodec {

    /** Frames [message] with the flags and stream its type requires. */
    fun encode(message: Message): Frame = when (message) {
        is Hello -> json(message, Hello.serializer())
        is Welcome -> json(message, Welcome.serializer())
        is Configure -> json(message, Configure.serializer())
        is StreamFormat -> json(message, StreamFormat.serializer())
        is ReceiverReport -> json(message, ReceiverReport.serializer())
        is KeyframeRequest -> json(message, KeyframeRequest.serializer())
        is ErrorMessage -> json(message, ErrorMessage.serializer())
        is Goodbye -> json(message, Goodbye.serializer())
        is Pairing -> json(message, Pairing.serializer(), FrameFlags.IGNORABLE)
        is DirectLink -> json(message, DirectLink.serializer(), FrameFlags.IGNORABLE)
        is VideoFrame -> encodeVideoFrame(message)
        is InputMessage -> encodeInput(message)
        is KeyMessage -> Frame(
            MessageType.KEY, FrameFlags.IGNORABLE, MessageType.KEY.defaultStream,
            ByteWriter(KeyMessage.HEADER_LENGTH_V1)
                .u16(KeyMessage.HEADER_LENGTH_V1)
                .u32(message.sequence)
                .u64(message.eventTimeUs)
                .u8(message.action.raw)
                .u8(0) // reserved
                .u16(message.usage)
                .u16(message.modifiers)
                .toByteArray(),
        )
        is CursorPosition -> Frame(
            MessageType.CURSOR, FrameFlags.IGNORABLE, MessageType.CURSOR.defaultStream,
            ByteWriter(CursorPosition.HEADER_LENGTH_V1)
                .u16(CursorPosition.HEADER_LENGTH_V1)
                .u32(message.sequence)
                .u64(message.timeUs)
                .u16(message.x)
                .u16(message.y)
                .u8(if (message.visible) 1 else 0)
                .u8(0) // reserved
                .u32(message.shapeId)
                .toByteArray(),
        )
        is CursorShape -> Frame(
            MessageType.CURSOR_SHAPE, FrameFlags.IGNORABLE, MessageType.CURSOR_SHAPE.defaultStream,
            ByteWriter(CursorShape.HEADER_LENGTH_V1 + message.png.size)
                .u16(CursorShape.HEADER_LENGTH_V1)
                .u32(message.shapeId)
                .u16(message.width)
                .u16(message.height)
                .u16(message.hotspotX)
                .u16(message.hotspotY)
                .bytes(message.png, 0, message.png.size)
                .toByteArray(),
        )
        is Ping -> Frame(
            MessageType.PING, FrameFlags.NONE, MessageType.PING.defaultStream,
            ByteWriter(12).u32(message.id).u64(message.t1).toByteArray(),
        )
        is Pong -> Frame(
            MessageType.PONG, FrameFlags.NONE, MessageType.PONG.defaultStream,
            ByteWriter(28).u32(message.id).u64(message.t1).u64(message.t2).u64(message.t3).toByteArray(),
        )
        is UnknownMessage -> Frame(MessageType(message.rawType), message.flags, message.stream, message.payload)
    }

    /**
     * Interprets a frame's payload. A type this implementation doesn't know becomes an
     * [UnknownMessage], IGNORABLE or not; the session skips the former and answers the latter
     * with ERROR `unsupported` (§1).
     *
     * @throws ProtocolException for malformed payloads.
     */
    fun decode(frame: Frame): Message = when (frame.type) {
        MessageType.HELLO -> json(frame, Hello.serializer())
        MessageType.WELCOME -> json(frame, Welcome.serializer())
        MessageType.CONFIGURE -> json(frame, Configure.serializer())
        MessageType.STREAM_FORMAT -> json(frame, StreamFormat.serializer())
        MessageType.RECEIVER_REPORT -> json(frame, ReceiverReport.serializer())
        MessageType.KEYFRAME_REQUEST -> json(frame, KeyframeRequest.serializer())
        MessageType.ERROR -> json(frame, ErrorMessage.serializer())
        MessageType.GOODBYE -> json(frame, Goodbye.serializer())
        MessageType.PAIRING -> json(frame, Pairing.serializer())
        MessageType.DIRECT_LINK -> json(frame, DirectLink.serializer())
        MessageType.VIDEO_FRAME -> decodeVideoFrame(frame)
        MessageType.INPUT -> decodeInput(frame)
        MessageType.KEY -> decodeKey(frame)
        MessageType.CURSOR -> decodeCursor(frame)
        MessageType.CURSOR_SHAPE -> decodeCursorShape(frame)
        MessageType.PING -> reader(frame, "PING").let { Ping(it.u32(), it.u64()) }
        MessageType.PONG -> reader(frame, "PONG").let { Pong(it.u32(), it.u64(), it.u64(), it.u64()) }
        else -> UnknownMessage(frame.type.code, frame.flags, frame.stream, frame.payloadBytes())
    }

    // JSON

    private fun <T : ControlMessage> json(message: T, serializer: KSerializer<T>, flags: FrameFlags = FrameFlags.NONE): Frame {
        val payload = ProtocolJson.encodeToString(serializer, message).encodeToByteArray()
        return Frame(message.type, flags, message.type.defaultStream, payload)
    }

    private fun reader(frame: Frame, context: String) = ByteReader(frame.payload, 0, frame.payloadLength, context)

    private fun <T : ControlMessage> json(frame: Frame, serializer: KSerializer<T>): T = try {
        ProtocolJson.decodeFromString(serializer, frame.payload.decodeToString(0, frame.payloadLength))
    } catch (e: SerializationException) {
        throw ProtocolException.InvalidJson(frame.type.displayName, e.message ?: e.javaClass.simpleName, e)
    } catch (e: IllegalArgumentException) {
        // Model invariants (for example a negative u32) surface as IllegalArgumentException.
        throw ProtocolException.InvalidJson(frame.type.displayName, e.message ?: e.javaClass.simpleName, e)
    }

    // VIDEO_FRAME (§3.2)

    private fun encodeVideoFrame(frame: VideoFrame): Frame {
        val payload = ByteWriter(VideoFrame.HEADER_LENGTH_V1 + frame.dataLength)
            .u16(VideoFrame.HEADER_LENGTH_V1)
            .u32(frame.frameId)
            .u64(frame.captureTimeUs)
            .u32(frame.encodeDurationUs)
            .bytes(frame.data, frame.dataOffset, frame.dataLength)
            .toByteArray()
        var flags = FrameFlags.NONE
        if (frame.isKeyframe) flags += FrameFlags.KEYFRAME
        if (frame.isDiscardable) flags += FrameFlags.DISCARDABLE
        return Frame(MessageType.VIDEO_FRAME, flags, MessageType.VIDEO_FRAME.defaultStream, payload)
    }

    /** Zero-copy: the access unit is a view into the frame's payload array. */
    private fun decodeVideoFrame(frame: Frame): VideoFrame {
        val reader = reader(frame, "VIDEO_FRAME")
        val headerLength = reader.u16()
        if (headerLength < VideoFrame.HEADER_LENGTH_V1) {
            throw ProtocolException.Malformed("VIDEO_FRAME headerLength $headerLength < ${VideoFrame.HEADER_LENGTH_V1}")
        }
        val frameId = reader.u32()
        val captureTimeUs = reader.u64()
        val encodeDurationUs = reader.u32()
        reader.skipTo(headerLength)
        return VideoFrame(
            frameId = frameId,
            captureTimeUs = captureTimeUs,
            encodeDurationUs = encodeDurationUs,
            isKeyframe = frame.flags.isKeyframe,
            data = frame.payload,
            isDiscardable = frame.flags.isDiscardable,
            dataOffset = headerLength,
            dataLength = frame.payloadLength - headerLength,
        )
    }

    // KEY (§3.3c)

    private fun decodeKey(frame: Frame): KeyMessage {
        val reader = reader(frame, "KEY")
        val headerLength = reader.u16()
        if (headerLength < KeyMessage.HEADER_LENGTH_V1) {
            throw ProtocolException.Malformed("KEY headerLength $headerLength < ${KeyMessage.HEADER_LENGTH_V1}")
        }
        val sequence = reader.u32()
        val eventTimeUs = reader.u64()
        val action = KeyAction(reader.u8())
        reader.u8() // reserved
        val usage = reader.u16()
        val modifiers = reader.u16()
        reader.skipTo(headerLength)
        return KeyMessage(sequence, eventTimeUs, action, usage, modifiers)
    }

    // CURSOR / CURSOR_SHAPE (§3.3b)

    private fun decodeCursor(frame: Frame): CursorPosition {
        val reader = reader(frame, "CURSOR")
        val headerLength = reader.u16()
        if (headerLength < CursorPosition.HEADER_LENGTH_V1) {
            throw ProtocolException.Malformed("CURSOR headerLength $headerLength < ${CursorPosition.HEADER_LENGTH_V1}")
        }
        val sequence = reader.u32()
        val timeUs = reader.u64()
        val x = reader.u16()
        val y = reader.u16()
        val visible = reader.u8() != 0
        reader.u8() // reserved
        val shapeId = reader.u32()
        reader.skipTo(headerLength)
        return CursorPosition(sequence, timeUs, x, y, visible, shapeId)
    }

    private fun decodeCursorShape(frame: Frame): CursorShape {
        val reader = reader(frame, "CURSOR_SHAPE")
        val headerLength = reader.u16()
        if (headerLength < CursorShape.HEADER_LENGTH_V1) {
            throw ProtocolException.Malformed("CURSOR_SHAPE headerLength $headerLength < ${CursorShape.HEADER_LENGTH_V1}")
        }
        val shapeId = reader.u32()
        val width = reader.u16()
        val height = reader.u16()
        val hotspotX = reader.u16()
        val hotspotY = reader.u16()
        reader.skipTo(headerLength)
        return CursorShape(shapeId, width, height, hotspotX, hotspotY, reader.rest())
    }

    // INPUT (§3.3)

    private fun encodeInput(input: InputMessage): Frame {
        val writer = ByteWriter(InputMessage.HEADER_LENGTH_V1 + 1 + input.pointers.size * PointerRecord.RECORD_LENGTH_V1)
            .u16(InputMessage.HEADER_LENGTH_V1)
            .u32(input.sequence)
            .u64(input.eventTimeUs)
            .u8(input.kind.raw)
            .u8(input.action.raw)
            .u8(input.pointers.size)
        for (pointer in input.pointers) {
            writer.u16(PointerRecord.RECORD_LENGTH_V1)
                .u8(pointer.pointerId)
                .u8(pointer.toolType.raw)
                .u16(pointer.buttons.bits)
                .u16(pointer.x)
                .u16(pointer.y)
                .u16(pointer.pressure)
                .i16(pointer.tiltX)
                .i16(pointer.tiltY)
                .u16(pointer.distance)
        }
        return Frame(MessageType.INPUT, FrameFlags.NONE, MessageType.INPUT.defaultStream, writer.toByteArray())
    }

    private fun decodeInput(frame: Frame): InputMessage {
        val reader = reader(frame, "INPUT")
        val headerLength = reader.u16()
        if (headerLength < InputMessage.HEADER_LENGTH_V1) {
            throw ProtocolException.Malformed("INPUT headerLength $headerLength < ${InputMessage.HEADER_LENGTH_V1}")
        }
        val sequence = reader.u32()
        val eventTimeUs = reader.u64()
        val kind = InputKind(reader.u8())
        val action = InputAction(reader.u8())
        reader.skipTo(headerLength)
        val count = reader.u8()
        val pointers = ArrayList<PointerRecord>(count)
        repeat(count) {
            val start = reader.position
            val recordLength = reader.u16()
            if (recordLength < PointerRecord.RECORD_LENGTH_V1) {
                throw ProtocolException.Malformed("INPUT recordLength $recordLength < ${PointerRecord.RECORD_LENGTH_V1}")
            }
            pointers += PointerRecord(
                pointerId = reader.u8(),
                toolType = ToolType(reader.u8()),
                buttons = PointerButtons(reader.u16()),
                x = reader.u16(),
                y = reader.u16(),
                pressure = reader.u16(),
                tiltX = reader.i16(),
                tiltY = reader.i16(),
                distance = reader.u16(),
            )
            reader.skipTo(start + recordLength)
        }
        return InputMessage(sequence, eventTimeUs, kind, action, pointers)
    }
}

/** Picks the protocol version both sides support (§3.1). */
object VersionNegotiation {
    /** Versions this implementation speaks. */
    val SUPPORTED: VersionRange = VersionRange(1, 1)

    /** The highest version within both ranges, or null when they don't overlap. */
    fun negotiate(remote: VersionRange, local: VersionRange = SUPPORTED): Int? {
        val high = minOf(local.max, remote.max)
        val low = maxOf(local.min, remote.min)
        return if (high >= low) high else null
    }
}
