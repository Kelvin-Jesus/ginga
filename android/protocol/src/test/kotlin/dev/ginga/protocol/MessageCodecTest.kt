package dev.ginga.protocol

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

class MessageCodecTest {

    private val display = DisplayDescription(17, "Galaxy Tab S11", PixelDimensions(1280, 800), true, 60.0, Orientation.LANDSCAPE)
    private val stream = StreamDescription(Codec.HEVC, 2560, 1600, 60.0, 40_000)

    private val allMessages: List<Message> = listOf(
        Hello(
            versions = VersionRange(1, 1),
            app = Hello.App("Ginga for Android", "0.1.0"),
            device = Hello.Device("samsung", "SM-X730", "16", "7f0c2a91d3e84b5c"),
            display = Hello.Display(2560, 1600, 274, listOf(60.0, 120.0), 0, wideColor = true),
            decoders = listOf(Hello.Decoder("video/hevc", listOf("main"), 4096, 2176, 120.0, true)),
            input = Hello.Input(Hello.Input.Touch(10), Hello.Input.Stylus(pressure = true, tilt = true, hover = true, buttons = 1)),
            transport = TransportKind.ADB_TCP,
            features = listOf(Feature.CLOCK_SYNC, Feature.RECEIVER_REPORT),
            resume = Hello.Resume("b3f1"),
        ),
        Welcome(1, "b3f1", Welcome.Mac("MacBook Air", "26.6.2", "0.3.0"), display, stream, listOf(Feature.CLOCK_SYNC)),
        Configure(request = Configure.Request(orientation = Orientation.PORTRAIT)),
        Configure(display = display, stream = stream),
        StreamFormat(Codec.HEVC, 2560, 1600, listOf(byteArrayOf(0x40, 0x01), byteArrayOf(0x42, 0x01), byteArrayOf(0x44, 0x01))),
        ReceiverReport(lastFrameId = 18234, framesReceived = 60, decodeMs = ReceiverReport.Percentiles(6.1, 9.8), clockOffsetUs = -1_234_567, rttUs = 850),
        KeyframeRequest(KeyframeReason.DECODER_ERROR, 18230),
        ErrorMessage(ErrorCode.INCOMPATIBLE_VERSION, "no common protocol version"),
        Goodbye(GoodbyeReason.USER),
        Pairing(PairingState.REQUIRED, "MacBook Air"),
        DirectLink("0102030405060708", "55".repeat(32)),
        Pairing(PairingState.COMMIT, commitment = "052c957131b84f9b12e9519024c730dbf4fa95abac4b8d2e5b1118b2cef8ec89"),
        Pairing(PairingState.REVEAL, nonce = "44".repeat(32)),
        VideoFrame(1, 1_234_567_890_123, 5500, isKeyframe = true, data = byteArrayOf(0, 0, 0, 1, 0x26, 0x01)),
        VideoFrame(0xFFFF_FFFFL, -1L, 0, isKeyframe = false, data = ByteArray(0), isDiscardable = true),
        InputMessage(
            sequence = 7, eventTimeUs = 987_655_000_000, kind = InputKind.STYLUS, action = InputAction.HOVER_MOVE,
            pointers = listOf(PointerRecord(0, ToolType.STYLUS, PointerButtons.STYLUS_PRIMARY, 1000, 2000, 0, 1200, -3400, 12)),
        ),
        InputMessage(1, 2, InputKind.TOUCH, InputAction.POINTER_DOWN, List(10) { PointerRecord(it, ToolType.FINGER, x = 65535, y = 0, pressure = 65535, tiltX = -32767, tiltY = 32767) }),
        KeyMessage(5, 987_655_000_000, KeyAction.DOWN, 0x04, 0x0002),
        KeyMessage(0xFFFF_FFFFL, -1L, KeyAction.UP, 0xE3, 0x01FF),
        CursorPosition(3, 5_000_789, 32768, 32768, visible = true, shapeId = 7),
        CursorPosition(0xFFFF_FFFFL, -1L, 0, 65535, visible = false, shapeId = 0),
        CursorShape(7, 34, 44, 8, 6, byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47)),
        Ping(42, 1_000_000),
        Pong(0xFFFF_FFFFL, 1_000_000, 5_000_123, 5_000_456),
    )

    @Test
    fun everyMessageRoundTrips() {
        for (message in allMessages) {
            val bytes = FrameCodec.encode(MessageCodec.encode(message))
            val decoded = MessageCodec.decode(FrameDecoder().feed(bytes).single())
            assertEquals(message, decoded, "round trip of ${message.type}")
        }
    }

    @Test
    fun messagesTravelOnTheirSpecifiedStreams() {
        val expected = mapOf(
            MessageType.HELLO to StreamId.CONTROL,
            MessageType.WELCOME to StreamId.CONTROL,
            MessageType.CONFIGURE to StreamId.CONTROL,
            MessageType.STREAM_FORMAT to StreamId.VIDEO,
            MessageType.RECEIVER_REPORT to StreamId.TELEMETRY,
            MessageType.KEYFRAME_REQUEST to StreamId.VIDEO,
            MessageType.ERROR to StreamId.CONTROL,
            MessageType.GOODBYE to StreamId.CONTROL,
            MessageType.PAIRING to StreamId.CONTROL,
            MessageType.DIRECT_LINK to StreamId.CONTROL,
            MessageType.VIDEO_FRAME to StreamId.VIDEO,
            MessageType.INPUT to StreamId.INPUT,
            MessageType.KEY to StreamId.INPUT,
            MessageType.CURSOR to StreamId.CURSOR,
            MessageType.CURSOR_SHAPE to StreamId.CURSOR,
            MessageType.PING to StreamId.CONTROL,
            MessageType.PONG to StreamId.CONTROL,
        )
        for (message in allMessages) {
            assertEquals(expected.getValue(message.type), MessageCodec.encode(message).stream, "${message.type}")
        }
    }

    @Test
    fun videoFlagsFollowTheFrame() {
        val key = MessageCodec.encode(VideoFrame(1, 0, 0, isKeyframe = true, data = ByteArray(1)))
        assertEquals(FrameFlags.KEYFRAME, key.flags)
        val delta = MessageCodec.encode(VideoFrame(2, 0, 0, isKeyframe = false, data = ByteArray(1), isDiscardable = true))
        assertEquals(FrameFlags.DISCARDABLE, delta.flags)
        assertTrue((MessageCodec.decode(key) as VideoFrame).isKeyframe)
        assertFalse((MessageCodec.decode(delta) as VideoFrame).isKeyframe)
    }

    @Test
    fun unknownTypesDecodeWithTheirFlagsIgnorableOrNot() {
        val ignorable = Frame(MessageType(0x7E), FrameFlags.IGNORABLE, StreamId.TELEMETRY, "future".encodeToByteArray())
        val skipped = assertIs<UnknownMessage>(MessageCodec.decode(ignorable))
        assertEquals(0x7E, skipped.rawType)
        assertTrue(skipped.flags.isIgnorable)
        assertEquals(ignorable, MessageCodec.encode(skipped))

        // Not IGNORABLE: still decoded; the session answers ERROR unsupported and carries on.
        val strict = Frame(MessageType(0x7D), FrameFlags.NONE, StreamId.CONTROL, "{}".encodeToByteArray())
        val unsupported = assertIs<UnknownMessage>(MessageCodec.decode(strict))
        assertFalse(unsupported.flags.isIgnorable)
        assertEquals(strict, MessageCodec.encode(unsupported))
    }

    @Test
    fun helloCarriesTheLoopbackTokenOnlyWhenSet() {
        val hello = allMessages.filterIsInstance<Hello>().single()
        val without = MessageCodec.encode(hello).payloadBytes().decodeToString()
        assertFalse("loopbackToken" in without, without)

        val token = "ab".repeat(32)
        val with = hello.copy(loopbackToken = token)
        val json = MessageCodec.encode(with).payloadBytes().decodeToString()
        assertTrue("\"loopbackToken\":\"$token\"" in json, json)
        assertEquals(with, MessageCodec.decode(MessageCodec.encode(with)))
        assertNull((MessageCodec.decode(MessageCodec.encode(hello)) as Hello).loopbackToken)
    }

    @Test
    fun helloCarriesPairingRequestedOnlyWhenSet() {
        val hello = allMessages.filterIsInstance<Hello>().single().copy(transport = TransportKind.WIFI_TLS)
        assertFalse("pairingRequested" in MessageCodec.encode(hello).payloadBytes().decodeToString())
        val requesting = hello.copy(pairingRequested = true)
        val json = MessageCodec.encode(requesting).payloadBytes().decodeToString()
        assertTrue("\"pairingRequested\":true" in json, json)
        assertEquals(requesting, MessageCodec.decode(MessageCodec.encode(requesting)))
        assertNull((MessageCodec.decode(MessageCodec.encode(hello)) as Hello).pairingRequested)
    }

    @Test
    fun pairingIsIgnorableJsonOnTheControlStream() {
        val frame = MessageCodec.encode(Pairing(PairingState.REQUIRED, "Kelvin's MacBook Air"))
        assertEquals(MessageType.PAIRING, frame.type)
        assertEquals(FrameFlags.IGNORABLE, frame.flags)
        assertEquals(StreamId.CONTROL, frame.stream)
        assertEquals("""{"state":"confirmed"}""", MessageCodec.encode(Pairing(PairingState.CONFIRMED)).payloadBytes().decodeToString())
        assertEquals(Pairing(PairingState.PAIRED), MessageCodec.decode(MessageCodec.encode(Pairing(PairingState.PAIRED))))
    }

    @Test
    fun truncatedBinaryPayloadsAreErrorsNotCrashes() {
        for (message in allMessages.filter { !it.type.isJson }) {
            val full = MessageCodec.encode(message)
            val minimum = when (message) {
                is VideoFrame -> VideoFrame.HEADER_LENGTH_V1
                is InputMessage -> full.payload.size
                is KeyMessage -> KeyMessage.HEADER_LENGTH_V1
                is CursorPosition -> CursorPosition.HEADER_LENGTH_V1
                is CursorShape -> CursorShape.HEADER_LENGTH_V1
                is Ping -> 12
                is Pong -> 28
                else -> error("unexpected $message")
            }
            for (length in 0 until minimum) {
                val cut = Frame(full.type, full.flags, full.stream, full.payload.copyOf(length))
                assertFailsWith<ProtocolException.Truncated>("${message.type} cut to $length") { MessageCodec.decode(cut) }
            }
        }
    }

    @Test
    fun cursorMessagesAreIgnorableBinaryOnTheCursorStream() {
        val position = MessageCodec.encode(CursorPosition(3, 5_000_789, 32768, 32768, visible = true, shapeId = 7))
        assertEquals(FrameFlags.IGNORABLE, position.flags)
        assertEquals(StreamId.CURSOR, position.stream)
        assertEquals("0018" + "00000003" + "00000000004c4e55" + "8000" + "8000" + "01" + "00" + "00000007", position.payloadBytes().toHex())
        val shape = MessageCodec.encode(CursorShape(7, 34, 44, 8, 6, byteArrayOf(1, 2)))
        assertEquals(FrameFlags.IGNORABLE, shape.flags)
        assertEquals("000e" + "00000007" + "0022" + "002c" + "0008" + "0006" + "0102", shape.payloadBytes().toHex())
    }

    @Test
    fun keyIsIgnorableBinaryOnTheInputStream() {
        val key = MessageCodec.encode(KeyMessage(5, 0x0102030405060708, KeyAction.DOWN, 0x87, 0x0102))
        assertEquals(FrameFlags.IGNORABLE, key.flags)
        assertEquals(StreamId.INPUT, key.stream)
        assertEquals("0014" + "00000005" + "0102030405060708" + "00" + "00" + "0087" + "0102", key.payloadBytes().toHex())
        // A newer peer's longer header is skipped.
        val longer = "0016" + "00000005" + "0102030405060708" + "01" + "00" + "00e3" + "0000" + "ffff"
        assertEquals(
            KeyMessage(5, 0x0102030405060708, KeyAction.UP, 0xE3, 0),
            MessageCodec.decode(Frame(MessageType.KEY, FrameFlags.IGNORABLE, StreamId.INPUT, longer.hexToBytes())),
        )
    }

    @Test
    fun newerCursorFieldsAreSkipped() {
        // A future CURSOR with 4 more header bytes, and a CURSOR_SHAPE with 2 more before the PNG.
        val position = "001c" + "00000003" + "00000000004c4e55" + "8000" + "8000" + "01" + "00" + "00000007" + "deadbeef"
        assertEquals(
            CursorPosition(3, 5_000_789, 32768, 32768, visible = true, shapeId = 7),
            MessageCodec.decode(Frame(MessageType.CURSOR, FrameFlags.IGNORABLE, StreamId.CURSOR, position.hexToBytes())),
        )
        val shape = "0010" + "00000007" + "0022" + "002c" + "0008" + "0006" + "ffff" + "0102"
        assertEquals(
            CursorShape(7, 34, 44, 8, 6, byteArrayOf(1, 2)),
            MessageCodec.decode(Frame(MessageType.CURSOR_SHAPE, FrameFlags.IGNORABLE, StreamId.CURSOR, shape.hexToBytes())),
        )
        val short = "0017" + "00000003" + "00000000004c4e55" + "8000" + "8000" + "01" + "00" + "000000"
        assertFailsWith<ProtocolException.Malformed> {
            MessageCodec.decode(Frame(MessageType.CURSOR, FrameFlags.IGNORABLE, StreamId.CURSOR, short.hexToBytes()))
        }
    }

    @Test
    fun headerLengthsBelowVersionOneAreRejected() {
        val video = MessageCodec.encode(VideoFrame(1, 2, 3, false, ByteArray(4)))
        video.payload[1] = 17
        assertFailsWith<ProtocolException.Malformed> { MessageCodec.decode(video) }

        val input = MessageCodec.encode(InputMessage(1, 2, InputKind.TOUCH, InputAction.DOWN, listOf(PointerRecord(0, ToolType.FINGER, x = 1, y = 2))))
        val shortHeader = input.payload.copyOf().also { it[1] = 15 }
        assertFailsWith<ProtocolException.Malformed> { MessageCodec.decode(Frame(input.type, input.flags, input.stream, shortHeader)) }
        // recordLength sits right after pointerCount (offset 17).
        val shortRecord = input.payload.copyOf().also { it[18] = 17 }
        assertFailsWith<ProtocolException.Malformed> { MessageCodec.decode(Frame(input.type, input.flags, input.stream, shortRecord)) }
    }

    @Test
    fun videoFrameSkipsFieldsAppendedByNewerSenders() {
        val payload = ByteWriter()
            .u16(22).u32(3).u64(1_234_567_923_457).u32(5000)
            .bytes(byteArrayOf(0xDE.toByte(), 0xAD.toByte(), 0xBE.toByte(), 0xEF.toByte()))
            .bytes(byteArrayOf(0, 0, 0, 1, 2, 1))
            .toByteArray()
        val frame = assertIs<VideoFrame>(MessageCodec.decode(Frame(MessageType.VIDEO_FRAME, FrameFlags.NONE, StreamId.VIDEO, payload)))
        assertEquals(3, frame.frameId)
        assertEquals(1_234_567_923_457, frame.captureTimeUs)
        assertEquals(5000, frame.encodeDurationUs)
        assertContentEquals(byteArrayOf(0, 0, 0, 1, 2, 1), frame.dataBytes())
    }

    @Test
    fun inputSkipsHeaderAndRecordFieldsAppendedByNewerSenders() {
        val payload = ByteWriter()
            .u16(20).u32(9).u64(987_655_032_000).u8(1).u8(2)
            .bytes(byteArrayOf(1, 2, 3, 4))
            .u8(2)
            .u16(22).u8(0).u8(1).u16(0).u16(32768).u16(16384).u16(0).i16(0).i16(0).u16(0).bytes(byteArrayOf(1, 2, 3, 4))
            .u16(18).u8(1).u8(1).u16(1).u16(100).u16(200).u16(300).i16(-5).i16(6).u16(7)
            .toByteArray()
        val input = assertIs<InputMessage>(MessageCodec.decode(Frame(MessageType.INPUT, FrameFlags.NONE, StreamId.INPUT, payload)))
        assertEquals(9, input.sequence)
        assertEquals(InputAction.UP, input.action)
        assertEquals(
            listOf(
                PointerRecord(0, ToolType.FINGER, PointerButtons.NONE, 32768, 16384),
                PointerRecord(1, ToolType.FINGER, PointerButtons.PRIMARY, 100, 200, 300, -5, 6, 7),
            ),
            input.pointers,
        )
    }

    @Test
    fun videoFramesAreDecodedWithoutCopyingThePayload() {
        val encoded = MessageCodec.encode(VideoFrame(5, 6, 7, isKeyframe = true, data = byteArrayOf(0, 0, 0, 1, 0x26)))
        // A pooled payload: the array is longer than the frame.
        val pooled = encoded.payload.copyOf(64)
        val frame = assertIs<VideoFrame>(MessageCodec.decode(Frame(encoded.type, encoded.flags, encoded.stream, pooled, encoded.payloadLength)))
        assertTrue(frame.data === pooled)
        assertEquals(VideoFrame.HEADER_LENGTH_V1, frame.dataOffset)
        assertEquals(5, frame.dataLength)
        assertContentEquals(byteArrayOf(0, 0, 0, 1, 0x26), frame.dataBytes())
        assertEquals(encoded, MessageCodec.encode(frame))
    }

    @Test
    fun pingAndPongIgnoreTrailingBytes() {
        val ping = MessageCodec.encode(Ping(1, 2))
        val longer = Frame(ping.type, ping.flags, ping.stream, ping.payload + byteArrayOf(9, 9))
        assertEquals(Ping(1, 2), MessageCodec.decode(longer))
    }

    @Test
    fun jsonIgnoresUnknownKeysAndDefaultsMissingOptionals() {
        val payload = """{"reason":"loss","future":{"x":[1,2]},"lastDecodedFrameId":null}""".encodeToByteArray()
        val decoded = MessageCodec.decode(Frame(MessageType.KEYFRAME_REQUEST, FrameFlags.NONE, StreamId.VIDEO, payload))
        assertEquals(KeyframeRequest(KeyframeReason.LOSS, null), decoded)

        val report = MessageCodec.decode(Frame(MessageType.RECEIVER_REPORT, FrameFlags.NONE, StreamId.TELEMETRY, "{}".encodeToByteArray()))
        assertEquals(ReceiverReport(), report)
    }

    @Test
    fun jsonOmitsNullOptionalsButKeepsRequiredDefaults() {
        val hello = allMessages.filterIsInstance<Hello>().single().copy(resume = null, input = null)
        val json = ProtocolJson.parseToJsonElement(MessageCodec.encode(hello).payload.decodeToString()).jsonObject
        assertFalse("resume" in json)
        assertFalse("input" in json)
        assertEquals("1", (json["protocol"] as JsonObject)["min"].toString())

        val streamJson = ProtocolJson.encodeToString(StreamDescription.serializer(), stream)
        assertTrue("\"primaries\":\"bt709\"" in streamJson, streamJson)
        assertTrue("\"range\":\"video\"" in streamJson, streamJson)
    }

    @Test
    fun unknownEnumerationValuesSurviveARoundTrip() {
        val payload = """{"reason":"sunspots"}""".encodeToByteArray()
        val goodbye = assertIs<Goodbye>(MessageCodec.decode(Frame(MessageType.GOODBYE, FrameFlags.NONE, StreamId.CONTROL, payload)))
        assertEquals("sunspots", goodbye.reason.value)
    }

    @Test
    fun invalidJsonIsReportedWithTheMessageName() {
        val broken = Frame(MessageType.WELCOME, FrameFlags.NONE, StreamId.CONTROL, "{\"protocol\":".encodeToByteArray())
        val error = assertFailsWith<ProtocolException.InvalidJson> { MessageCodec.decode(broken) }
        assertEquals("WELCOME", error.messageName)

        val missing = Frame(MessageType.GOODBYE, FrameFlags.NONE, StreamId.CONTROL, "{}".encodeToByteArray())
        assertFailsWith<ProtocolException.InvalidJson> { MessageCodec.decode(missing) }

        val badBase64 = Frame(MessageType.STREAM_FORMAT, FrameFlags.NONE, StreamId.VIDEO,
            """{"codec":"hevc","width":1,"height":1,"parameterSets":["%%%"]}""".encodeToByteArray())
        assertFailsWith<ProtocolException.InvalidJson> { MessageCodec.decode(badBase64) }
    }

    @Test
    fun streamFormatUsesStandardPaddedBase64() {
        val format = StreamFormat(Codec.HEVC, 2560, 1600, listOf(byteArrayOf(0x40, 0x01, 0x0C, 0x01, 0xFF.toByte(), 0xFF.toByte()), byteArrayOf(1)))
        val json = MessageCodec.encode(format).payload.decodeToString()
        assertTrue("\"QAEMAf//\"" in json, json)
        assertTrue("\"AQ==\"" in json, json)
    }

    @Test
    fun versionNegotiationPicksTheHighestCommonVersion() {
        assertEquals(1, VersionNegotiation.negotiate(VersionRange(1, 1)))
        assertEquals(1, VersionNegotiation.negotiate(VersionRange(1, 3)))
        assertEquals(2, VersionNegotiation.negotiate(VersionRange(1, 3), local = VersionRange(1, 2)))
        assertNull(VersionNegotiation.negotiate(VersionRange(2, 3)))
    }

    @Test
    fun valueRangesAreEnforcedLocally() {
        assertFailsWith<IllegalArgumentException> { PointerRecord(0, ToolType.FINGER, x = 65536, y = 0) }
        assertFailsWith<IllegalArgumentException> { Ping(-1, 0) }
        assertFailsWith<IllegalArgumentException> { InputMessage(0x1_0000_0000L, 0, InputKind.TOUCH, InputAction.DOWN, emptyList()) }
    }
}
