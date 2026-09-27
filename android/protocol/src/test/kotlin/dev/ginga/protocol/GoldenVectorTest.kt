package dev.ginga.protocol

import java.io.File
import java.math.BigInteger
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assume.assumeTrue

/**
 * Cross-language contract (PROTOCOL.md §9): every `protocol/test-vectors/<name>.json`, produced by
 * the Swift implementation, must
 * 1. decode from `hex` to exactly `decoded` (`{type, flags, stream, fields}`), and
 * 2. unless `decodeOnly`, re-encode from `decoded` to exactly `hex` (binary messages) or to the
 *    same header and an equal JSON value (JSON messages; key order may differ).
 *
 * Skipped, not failed, when the directory is missing or empty.
 */
class GoldenVectorTest {

    @Test
    fun everyCommittedVectorDecodesAndReencodes() {
        val directory = vectorDirectory()
        val files = directory?.listFiles { file -> file.isFile && file.extension == "json" }?.sortedBy { it.name }.orEmpty()
        assumeTrue("no golden vectors found (looked in $directory)", files.isNotEmpty())

        val failures = mutableListOf<String>()
        for (file in files) {
            try {
                checkVector(file)
            } catch (e: Throwable) {
                failures += "${file.name}: ${e.message ?: e}"
            }
        }
        println("golden vectors: ${files.size - failures.size}/${files.size} passed (${directory?.path})")
        assertTrue(failures.isEmpty(), "golden vector failures:\n" + failures.joinToString("\n"))
    }

    private fun checkVector(file: File) {
        val root = Json.parseToJsonElement(file.readText()).jsonObject
        val bytes = root.getValue("hex").jsonPrimitive.content.hexToBytes()
        val decodeOnly = root["decodeOnly"]?.jsonPrimitive?.booleanOrNull == true
        val expected = root.getValue("decoded").jsonObject

        // 1. hex → decoded
        val decoder = FrameDecoder()
        val frames = decoder.feed(bytes)
        check(frames.size == 1) { "expected exactly one frame, got ${frames.size}" }
        check(decoder.bufferedByteCount == 0) { "${decoder.bufferedByteCount} trailing bytes" }
        val frame = frames.single()
        val message = MessageCodec.decode(frame)
        JsonComparison.requireEqual(expected, GoldenDescriptor.describe(frame, message), "decoded")
        if (decodeOnly) return

        // 2. decoded → hex
        val rebuilt = MessageCodec.encode(GoldenDescriptor.message(expected))
        requireSameEncoding(frame, bytes, rebuilt, "re-encoding `decoded`")
        // 3. and the decoded message itself re-encodes identically.
        requireSameEncoding(frame, bytes, MessageCodec.encode(message), "re-encoding the decoded message")
    }

    private fun requireSameEncoding(original: Frame, originalBytes: ByteArray, reencoded: Frame, what: String) {
        if (original.type.isJson) {
            check(reencoded.type == original.type && reencoded.flags == original.flags && reencoded.stream == original.stream) {
                "$what: header differs ($reencoded vs $original)"
            }
            JsonComparison.requireEqual(
                Json.parseToJsonElement(original.payload.decodeToString()),
                Json.parseToJsonElement(reencoded.payload.decodeToString()),
                "$what payload",
            )
        } else {
            val bytes = FrameCodec.encode(reencoded)
            check(bytes.contentEquals(originalBytes)) { "$what is not byte-exact:\n  expected ${originalBytes.toHex()}\n  actual   ${bytes.toHex()}" }
        }
    }

    private fun vectorDirectory(): File? {
        val candidates = listOfNotNull(
            System.getProperty("ginga.testVectorsDir")?.let(::File),
            File("../../protocol/test-vectors"), // working directory = android/protocol
            File("../protocol/test-vectors"), // working directory = android
        )
        return candidates.firstOrNull { it.isDirectory } ?: candidates.firstOrNull()
    }
}

/** The §9 `decoded` descriptor: `{type, flags, stream, fields}`. */
internal object GoldenDescriptor {

    fun describe(frame: Frame, message: Message): JsonObject = buildJsonObject {
        put("type", if (message is UnknownMessage) "UNKNOWN" else frame.type.displayName)
        put("flags", frame.flags.bits)
        put("stream", frame.stream.id)
        put("fields", fields(message))
    }

    private fun fields(message: Message): JsonElement = when (message) {
        is VideoFrame -> buildJsonObject {
            put("frameId", message.frameId)
            put("captureTimeUs", unsigned(message.captureTimeUs))
            put("encodeDurationUs", message.encodeDurationUs)
            put("dataHex", message.dataBytes().toHex())
        }
        is InputMessage -> buildJsonObject {
            put("sequence", message.sequence)
            put("eventTimeUs", unsigned(message.eventTimeUs))
            put("kind", message.kind.raw)
            put("action", message.action.raw)
            put("pointers", JsonArray(message.pointers.map { pointer ->
                buildJsonObject {
                    put("pointerId", pointer.pointerId)
                    put("toolType", pointer.toolType.raw)
                    put("buttons", pointer.buttons.bits)
                    put("x", pointer.x)
                    put("y", pointer.y)
                    put("pressure", pointer.pressure)
                    put("tiltX", pointer.tiltX)
                    put("tiltY", pointer.tiltY)
                    put("distance", pointer.distance)
                }
            }))
        }
        is KeyMessage -> buildJsonObject {
            put("sequence", message.sequence)
            put("eventTimeUs", unsigned(message.eventTimeUs))
            put("action", message.action.raw)
            put("usage", message.usage)
            put("modifiers", message.modifiers)
        }
        is CursorPosition -> buildJsonObject {
            put("sequence", message.sequence)
            put("timeUs", unsigned(message.timeUs))
            put("x", message.x)
            put("y", message.y)
            put("visible", message.visible)
            put("shapeId", message.shapeId)
        }
        is CursorShape -> buildJsonObject {
            put("shapeId", message.shapeId)
            put("width", message.width)
            put("height", message.height)
            put("hotspotX", message.hotspotX)
            put("hotspotY", message.hotspotY)
            put("pngHex", message.png.toHex())
        }
        is Ping -> buildJsonObject {
            put("id", message.id)
            put("t1", unsigned(message.t1))
        }
        is Pong -> buildJsonObject {
            put("id", message.id)
            put("t1", unsigned(message.t1))
            put("t2", unsigned(message.t2))
            put("t3", unsigned(message.t3))
        }
        is UnknownMessage -> buildJsonObject {
            put("rawType", message.rawType)
            put("payloadHex", message.payload.toHex())
        }
        // JSON messages: the typed model's view of the payload, so that a field this
        // implementation doesn't model (or names differently) shows up as a difference.
        is ControlMessage -> Json.parseToJsonElement(MessageCodec.encode(message).payload.decodeToString())
    }

    /** Builds the message a descriptor describes (the inverse of [describe]). */
    fun message(descriptor: JsonObject): Message {
        val type = descriptor.getValue("type").jsonPrimitive.content
        val flags = FrameFlags(descriptor.int("flags"))
        val stream = StreamId(descriptor.int("stream"))
        val fields = descriptor.getValue("fields").jsonObject
        return when (type) {
            "UNKNOWN" -> UnknownMessage(fields.int("rawType"), flags, stream, fields.string("payloadHex").hexToBytes())
            "VIDEO_FRAME" -> VideoFrame(
                frameId = fields.long("frameId"),
                captureTimeUs = fields.u64("captureTimeUs"),
                encodeDurationUs = fields.long("encodeDurationUs"),
                isKeyframe = flags.isKeyframe,
                data = fields.string("dataHex").hexToBytes(),
                isDiscardable = flags.isDiscardable,
            )
            "INPUT" -> InputMessage(
                sequence = fields.long("sequence"),
                eventTimeUs = fields.u64("eventTimeUs"),
                kind = InputKind(fields.int("kind")),
                action = InputAction(fields.int("action")),
                pointers = fields.getValue("pointers").jsonArray.map { element ->
                    val pointer = element.jsonObject
                    PointerRecord(
                        pointerId = pointer.int("pointerId"),
                        toolType = ToolType(pointer.int("toolType")),
                        buttons = PointerButtons(pointer.int("buttons")),
                        x = pointer.int("x"),
                        y = pointer.int("y"),
                        pressure = pointer.int("pressure"),
                        tiltX = pointer.int("tiltX"),
                        tiltY = pointer.int("tiltY"),
                        distance = pointer.int("distance"),
                    )
                },
            )
            "KEY" -> KeyMessage(
                sequence = fields.long("sequence"),
                eventTimeUs = fields.u64("eventTimeUs"),
                action = KeyAction(fields.int("action")),
                usage = fields.int("usage"),
                modifiers = fields.int("modifiers"),
            )
            "CURSOR" -> CursorPosition(
                sequence = fields.long("sequence"),
                timeUs = fields.u64("timeUs"),
                x = fields.int("x"),
                y = fields.int("y"),
                visible = fields.getValue("visible").jsonPrimitive.boolean,
                shapeId = fields.long("shapeId"),
            )
            "CURSOR_SHAPE" -> CursorShape(
                shapeId = fields.long("shapeId"),
                width = fields.int("width"),
                height = fields.int("height"),
                hotspotX = fields.int("hotspotX"),
                hotspotY = fields.int("hotspotY"),
                png = fields.string("pngHex").hexToBytes(),
            )
            "PING" -> Ping(fields.long("id"), fields.u64("t1"))
            "PONG" -> Pong(fields.long("id"), fields.u64("t1"), fields.u64("t2"), fields.u64("t3"))
            "HELLO" -> ProtocolJson.decodeFromJsonElement(Hello.serializer(), fields)
            "WELCOME" -> ProtocolJson.decodeFromJsonElement(Welcome.serializer(), fields)
            "CONFIGURE" -> ProtocolJson.decodeFromJsonElement(Configure.serializer(), fields)
            "STREAM_FORMAT" -> ProtocolJson.decodeFromJsonElement(StreamFormat.serializer(), fields)
            "RECEIVER_REPORT" -> ProtocolJson.decodeFromJsonElement(ReceiverReport.serializer(), fields)
            "KEYFRAME_REQUEST" -> ProtocolJson.decodeFromJsonElement(KeyframeRequest.serializer(), fields)
            "ERROR" -> ProtocolJson.decodeFromJsonElement(ErrorMessage.serializer(), fields)
            "GOODBYE" -> ProtocolJson.decodeFromJsonElement(Goodbye.serializer(), fields)
            "PAIRING" -> ProtocolJson.decodeFromJsonElement(Pairing.serializer(), fields)
            "DIRECT_LINK" -> ProtocolJson.decodeFromJsonElement(DirectLink.serializer(), fields)
            else -> error("unknown descriptor type $type")
        }
    }

    private fun unsigned(value: Long): JsonPrimitive = JsonPrimitive(BigInteger(java.lang.Long.toUnsignedString(value)))

    private fun JsonObject.int(key: String): Int = getValue(key).jsonPrimitive.content.toInt()

    private fun JsonObject.long(key: String): Long = getValue(key).jsonPrimitive.content.toLong()

    private fun JsonObject.u64(key: String): Long = java.lang.Long.parseUnsignedLong(getValue(key).jsonPrimitive.content)

    private fun JsonObject.string(key: String): String = getValue(key).jsonPrimitive.content
}

/** Semantic JSON equality: key order is irrelevant and numbers compare by value (60 == 60.0). */
internal object JsonComparison {

    fun requireEqual(expected: JsonElement, actual: JsonElement, path: String) {
        difference(expected, actual, path)?.let { throw AssertionError(it) }
    }

    fun difference(expected: JsonElement, actual: JsonElement, path: String): String? = when {
        expected is JsonObject && actual is JsonObject -> {
            val missing = expected.keys - actual.keys
            val extra = actual.keys - expected.keys
            when {
                missing.isNotEmpty() -> "$path: missing ${missing.sorted()} (actual $actual)"
                extra.isNotEmpty() -> "$path: unexpected ${extra.sorted()} (actual $actual)"
                else -> expected.keys.sorted().firstNotNullOfOrNull { key ->
                    difference(expected.getValue(key), actual.getValue(key), "$path.$key")
                }
            }
        }
        expected is JsonArray && actual is JsonArray ->
            if (expected.size != actual.size) {
                "$path: expected ${expected.size} elements, got ${actual.size}"
            } else {
                expected.indices.firstNotNullOfOrNull { difference(expected[it], actual[it], "$path[$it]") }
            }
        expected is JsonNull || actual is JsonNull ->
            if (expected is JsonNull && actual is JsonNull) null else "$path: expected $expected, got $actual"
        expected is JsonPrimitive && actual is JsonPrimitive ->
            if (primitivesEqual(expected, actual)) null else "$path: expected $expected, got $actual"
        else -> "$path: expected $expected, got $actual"
    }

    private fun primitivesEqual(a: JsonPrimitive, b: JsonPrimitive): Boolean {
        if (a.isString || b.isString) return a.isString == b.isString && a.content == b.content
        if (a.content == b.content) return true
        val aLong = a.content.toLongOrNull()
        val bLong = b.content.toLongOrNull()
        if (aLong != null && bLong != null) return aLong == bLong
        val aDouble = a.content.toDoubleOrNull() ?: return false
        val bDouble = b.content.toDoubleOrNull() ?: return false
        return aDouble == bDouble
    }
}
